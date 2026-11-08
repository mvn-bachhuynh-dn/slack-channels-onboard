"""Repo watch -- code-based cron, no LLM, one job per repository.

``ctx.message`` is a JSON object::

    {"repo": "owner/name", "name": "erp-dental", "channel": "C0..."}

``channel`` may be empty: the report then goes to the owner's DM.

Every run (hourly) asks GitHub, through the ``gh`` CLI, for four things and
reports ONLY what is new since the last run, so a quiet repo costs nothing and
says nothing:

  * the latest run of each workflow on the default branch, when it failed;
  * open Dependabot alerts of severity high or critical;
  * open non-bot pull requests with no update for STALE_DAYS days;
  * issues opened since the previous run.

The first run for a repo reports the failing workflows and the high/critical
alerts that exist right now (they are actionable) and records stale pull
requests and issues silently, so the channel is not flooded with old items.

Read-only: nothing here writes to GitHub or to the repository.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from kiro_crew.cron_script import Skip

WORK_DIR = Path(os.environ.get("KIROCREW_HOME") or Path.home() / ".kiro" / "crew") / "repo_watch"
STALE_DAYS = 3
GH_TIMEOUT_SECS = 60
ERRORS_BEFORE_ALERT = 3
MAX_LINES = 8


def _gh(args: list[str]) -> Any:
    proc = subprocess.run(
        ["gh", *args],
        capture_output=True,
        text=True,
        timeout=GH_TIMEOUT_SECS,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout or "gh failed").strip()[:300])
    return json.loads(proc.stdout) if proc.stdout.strip() else []


def _parse_ts(text: str) -> float:
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def _load_state(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_state(path: Path, state: dict[str, Any]) -> None:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")


def _collect(repo: str, state: dict[str, Any], first: bool, now: float) -> list[str]:
    lines: list[str] = []

    runs = _gh(
        [
            "run",
            "list",
            "-R",
            repo,
            "--limit",
            "30",
            "--json",
            "databaseId,workflowName,conclusion,headBranch,url,event,createdAt",
        ]
    )
    default_branch = _gh(["repo", "view", repo, "--json", "defaultBranchRef"])
    main = (default_branch.get("defaultBranchRef") or {}).get("name") or "main"
    latest: dict[str, dict[str, Any]] = {}
    for run in runs:
        if run.get("headBranch") != main or not run.get("conclusion"):
            continue
        latest.setdefault(run.get("workflowName", "?"), run)
    seen_runs = set(state.get("runs", []))
    for name, run in latest.items():
        if run["conclusion"] in ("failure", "timed_out") and run["databaseId"] not in seen_runs:
            lines.append(f"🔴 CI đỏ trên `{main}`: {name} <{run['url']}|run {run['databaseId']}>")
            seen_runs.add(run["databaseId"])
    state["runs"] = sorted(seen_runs)[-200:]

    try:
        alerts = _gh(["api", f"repos/{repo}/dependabot/alerts?state=open&per_page=50"])
    except RuntimeError:
        alerts = []  # no permission for alerts: not an error worth paging
    seen_alerts = set(state.get("alerts", []))
    for alert in alerts:
        severity = (alert.get("security_advisory") or {}).get("severity", "")
        if severity not in ("high", "critical") or alert["number"] in seen_alerts:
            continue
        pkg = (alert.get("dependency") or {}).get("package", {}).get("name", "?")
        summary = (alert.get("security_advisory") or {}).get("summary", "")
        lines.append(
            f"🛡️ Dependabot {severity}: `{pkg}` {summary[:80]} <{alert.get('html_url', '')}|#{alert['number']}>"
        )
        seen_alerts.add(alert["number"])
    state["alerts"] = sorted(seen_alerts)[-300:]

    prs = _gh(
        [
            "pr",
            "list",
            "-R",
            repo,
            "--state",
            "open",
            "--limit",
            "50",
            "--json",
            "number,title,url,updatedAt,author",
        ]
    )
    seen_prs = set(state.get("stale_prs", []))
    for pr in prs:
        if (pr.get("author") or {}).get("is_bot"):
            continue
        stale = now - _parse_ts(pr["updatedAt"]) > STALE_DAYS * 86400
        if stale and pr["number"] not in seen_prs:
            seen_prs.add(pr["number"])
            if not first:
                lines.append(f"⏳ PR treo >{STALE_DAYS} ngày: <{pr['url']}|#{pr['number']}> {pr['title'][:70]}")
    state["stale_prs"] = sorted(seen_prs)[-200:]

    issues = _gh(
        [
            "issue",
            "list",
            "-R",
            repo,
            "--state",
            "open",
            "--limit",
            "30",
            "--json",
            "number,title,url,createdAt",
        ]
    )
    last_run = float(state.get("last_run", 0.0))
    for issue in issues:
        if not first and _parse_ts(issue["createdAt"]) > last_run:
            lines.append(f"🆕 Issue mới: <{issue['url']}|#{issue['number']}> {issue['title'][:70]}")
    return lines


def run(ctx: Any) -> None:
    cfg = json.loads(ctx.message)
    repo, name = cfg["repo"], cfg.get("name", cfg["repo"])
    channel = cfg.get("channel") or ""
    state_path = WORK_DIR / (repo.replace("/", "__") + ".json")
    state = _load_state(state_path)
    first = "last_run" not in state
    now = time.time()

    try:
        lines = _collect(repo, state, first, now)
    except (RuntimeError, subprocess.TimeoutExpired, ValueError, OSError) as exc:
        state["errors"] = int(state.get("errors", 0)) + 1
        _save_state(state_path, state)
        if state["errors"] == ERRORS_BEFORE_ALERT:
            ctx.notify(
                f"⚠️ repo-watch `{name}` lỗi {ERRORS_BEFORE_ALERT} lần liên tiếp: {str(exc)[:200]}",
                **({"channel": channel} if channel else {}),
            )
        raise Skip()

    state["errors"] = 0
    state["last_run"] = now
    _save_state(state_path, state)
    if not lines:
        raise Skip()
    shown = lines[:MAX_LINES]
    if len(lines) > MAX_LINES:
        shown.append(f"… và {len(lines) - MAX_LINES} mục nữa")
    head = f"*{name}* ({repo}): {'lần đầu theo dõi, hiện có' if first else 'có thay đổi mới'}"
    ctx.notify("\n".join([head, *shown]), **({"channel": channel} if channel else {}))
