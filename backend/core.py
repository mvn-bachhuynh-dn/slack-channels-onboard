"""Pure planning logic for slack-channels-onboard (no gateway imports, unit-testable).

Everything here works on plain dicts shaped like ``config.json`` so the same
rules drive the dashboard page, the background poller, and the tests.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

VALID_ACTIVATIONS = ("always", "mention", "observe", "review", "off")
VALID_MODES = ("auto", "notify", "off")

DEFAULT_SETTINGS: dict[str, Any] = {
    # auto   -> onboard a new channel as soon as it is detected
    # notify -> only DM the owner that a new channel is waiting
    # off    -> no background detection (the page still works)
    "mode": "auto",
    "workspace_root": "~/Projects",
    "activation": "mention",
    "thread_follow": True,
    # Only act on a channel when the owner is a member of it, so someone who
    # can merely invite the bot cannot make the gateway create agents.
    "require_owner_member": True,
    # Give each channel its own private member memory (created by the gateway's
    # own member-memory path). False shares the default store.
    "dedicated_memory": True,
    "poll_secs": 300,
}

_SLUG_RE = re.compile(r"[^a-z0-9_-]+")
_MAX_NAME = 48


def slugify(raw: str) -> str:
    """Turn a Slack channel name into a safe agent/workspace name."""
    s = _SLUG_RE.sub("-", raw.strip().lower().lstrip("#")).strip("-_")
    return s[:_MAX_NAME].strip("-_") or "channel"


def normalize_settings(raw: Any) -> dict[str, Any]:
    """Merge *raw* over the defaults, dropping anything invalid."""
    out = dict(DEFAULT_SETTINGS)
    if not isinstance(raw, dict):
        return out
    if raw.get("mode") in VALID_MODES:
        out["mode"] = raw["mode"]
    if isinstance(raw.get("workspace_root"), str) and raw["workspace_root"].strip():
        out["workspace_root"] = raw["workspace_root"].strip()
    if raw.get("activation") in VALID_ACTIVATIONS:
        out["activation"] = raw["activation"]
    for key in ("thread_follow", "require_owner_member", "dedicated_memory"):
        if isinstance(raw.get(key), bool):
            out[key] = raw[key]
    poll = raw.get("poll_secs")
    if isinstance(poll, int) and not isinstance(poll, bool):
        out["poll_secs"] = max(60, min(poll, 3600))
    return out


def channel_rows(cfg: dict, bot_channels: list[dict]) -> list[dict]:
    """One row per channel the bot is in or that has a binding.

    A row carries what the page shows and edits: the binding (agent, activation,
    thread_follow), the agent's workspace and directory, and the memory store.
    """
    channels = cfg.get("slack", {}).get("channels", {}) or {}
    agents = cfg.get("agents", {}) or {}
    workspaces = cfg.get("workspaces", {}) or {}
    names = {c.get("id"): c.get("name", "") for c in bot_channels if c.get("id")}
    rows = []
    for cid in sorted(set(names) | set(channels)):
        binding = channels.get(cid)
        row: dict[str, Any] = {
            "id": cid,
            "name": names.get(cid, ""),
            "bot_member": cid in names,
            "configured": binding is not None,
        }
        if binding is not None:
            agent_name = binding.get("agent", "")
            agent = agents.get(agent_name, {}) if agent_name else {}
            ws_key = agent.get("workspace", "") if agent else ""
            row.update(
                agent=agent_name,
                activation=binding.get("activation", "mention"),
                thread_follow=binding.get("thread_follow", True),
                workspace=ws_key,
                workspace_dir=(workspaces.get(ws_key) or {}).get("dir", "") if ws_key else "",
                memory_store=agent.get("memory_store", "") if agent else "",
            )
        rows.append(row)
    return rows


def pending_channels(cfg: dict, bot_channels: list[dict]) -> list[dict]:
    """Bot channels (not DMs) that have no binding yet."""
    channels = cfg.get("slack", {}).get("channels", {}) or {}
    return [
        c
        for c in bot_channels
        if c.get("id") and not str(c["id"]).startswith("D") and c["id"] not in channels
    ]


def unique_name(cfg: dict, base: str) -> str:
    """*base*, or *base*-N, free in both agents and workspaces."""
    taken = set(cfg.get("agents", {}) or {}) | set(cfg.get("workspaces", {}) or {})
    if base not in taken:
        return base
    n = 2
    while f"{base}-{n}" in taken:
        n += 1
    return f"{base}-{n}"


def plan_onboard(
    cfg: dict,
    *,
    channel_id: str,
    channel_name: str,
    settings: dict,
    name: str | None = None,
    workspace_dir: str | None = None,
) -> dict[str, Any]:
    """Decide the bundle for a NEW channel. Raises ValueError when not allowed."""
    if not channel_id or channel_id.startswith("D"):
        raise ValueError("only channels can be onboarded, not DMs")
    if channel_id in (cfg.get("slack", {}).get("channels", {}) or {}):
        raise ValueError(f"channel {channel_id} is already onboarded")
    agent_name = unique_name(cfg, slugify(name or channel_name or channel_id))
    ws_dir = workspace_dir or str(Path(settings["workspace_root"]).expanduser() / agent_name)
    ws_dir = str(Path(ws_dir).expanduser())
    if not Path(ws_dir).is_absolute():
        raise ValueError("workspace directory must be an absolute path")
    return {
        "name": agent_name,
        "workspace": agent_name,
        "workspace_dir": ws_dir,
        "binding": {
            "activation": settings["activation"],
            "agent": agent_name,
            "thread_follow": bool(settings["thread_follow"]),
        },
        "dedicated_memory": bool(settings["dedicated_memory"]),
    }


def set_workspace(data: dict, key: str, ws_dir: str) -> dict:
    """config.json mutator: point workspaces.<key> at *ws_dir*."""
    data.setdefault("workspaces", {}).setdefault(key, {})["dir"] = ws_dir
    return data


def set_binding(data: dict, channel_id: str, **fields: Any) -> dict:
    """config.json mutator: merge *fields* into slack.channels.<id>."""
    ch = data.setdefault("slack", {}).setdefault("channels", {}).setdefault(channel_id, {})
    ch.update({k: v for k, v in fields.items() if v is not None})
    return data


def remove_binding(data: dict, channel_id: str) -> dict:
    """config.json mutator: drop ``slack.channels.<channel_id>`` only.

    The agent, its workspace and its memory are left alone: another channel may
    share them, and a memory store is not something to delete from a list view.
    """
    channels = (data.get("slack", {}) or {}).get("channels", {}) or {}
    if channel_id not in channels:
        raise ValueError(f"channel {channel_id} is not onboarded")
    del channels[channel_id]
    return data


def validate_reconfigure(
    activation: Any = None, thread_follow: Any = None, workspace_dir: Any = None
) -> list[str]:
    """Return problems with a reconfigure request (empty == valid)."""
    errors = []
    if activation is not None and activation not in VALID_ACTIVATIONS:
        errors.append(f"activation must be one of {list(VALID_ACTIVATIONS)}")
    if thread_follow is not None and not isinstance(thread_follow, bool):
        errors.append("thread_follow must be true or false")
    if workspace_dir is not None:
        if not isinstance(workspace_dir, str) or not workspace_dir.strip():
            errors.append("workspace_dir must be a non-empty string")
        elif not Path(workspace_dir).expanduser().is_absolute():
            errors.append("workspace_dir must be an absolute path")
        elif not Path(workspace_dir).expanduser().is_dir():
            errors.append(f"workspace_dir does not exist: {workspace_dir}")
    if activation is None and thread_follow is None and workspace_dir is None:
        errors.append("nothing to change")
    return errors



# ------------------------------------------------------- people (slice 4)
#
# Two lists, two homes, matching what the gateway (with the local Set K / Set P
# patches) actually reads:
#   * members      -> config.json ``slack.allowed_users`` (list of
#                     ``{"slack_id", "name"}`` objects; the loader silently drops
#                     an entry without ``slack_id``) — who may talk to the bot;
#   * maintainers  -> ``<data home>/channel-roles.json``
#                     ``{"channels": {"C…": {"maintainers": ["U…"], "commands": [...]}}}``
#                     — who gets scoped write + read-only git in ONE channel, and
#                     which commands they may run there without a prompt. Kept out of
#                     config.json because ``ChannelConfig.from_dict`` drops
#                     unknown keys, so a dashboard config save would strip them.
# A maintainer must also be a member; these helpers enforce that.

_USER_ID_RE = re.compile(r"^[UW][A-Z0-9]{2,20}$")
_CHANNEL_ID_RE = re.compile(r"^[CG][A-Z0-9]{1,20}$")
_MAX_NAME_LEN = 120


def valid_user_id(uid: Any) -> bool:
    return isinstance(uid, str) and bool(_USER_ID_RE.match(uid))


def member_entries(cfg: dict) -> list[dict]:
    """``slack.allowed_users`` as clean ``{"slack_id", "name"}`` entries."""
    out = []
    seen = set()
    for item in (cfg.get("slack", {}) or {}).get("allowed_users", []) or []:
        if not isinstance(item, dict):
            continue
        uid = item.get("slack_id")
        if valid_user_id(uid) and uid not in seen:
            seen.add(uid)
            out.append({"slack_id": uid, "name": str(item.get("name") or "")[:_MAX_NAME_LEN]})
    return out


def normalize_members(raw: Any, owner: str = "") -> list[dict]:
    """Validate a members request. Raises ValueError on a bad entry.

    The owner is dropped (always allowed, never listed); duplicates collapse.
    """
    if not isinstance(raw, list):
        raise ValueError("members must be a list")
    out, seen = [], set()
    for item in raw:
        if isinstance(item, str):
            item = {"slack_id": item}
        if not isinstance(item, dict):
            raise ValueError("each member must be an object with slack_id")
        uid = str(item.get("slack_id", "")).strip()
        if not valid_user_id(uid):
            raise ValueError(f"invalid Slack user id: {uid!r}")
        if uid == owner or uid in seen:
            continue
        seen.add(uid)
        out.append({"slack_id": uid, "name": str(item.get("name") or "")[:_MAX_NAME_LEN]})
    return out


def set_members(data: dict, members: list[dict]) -> dict:
    """config.json mutator: replace ``slack.allowed_users``."""
    data.setdefault("slack", {})["allowed_users"] = [dict(m) for m in members]
    return data


# Approved maintainer commands (gateway Set P2, ``channels.<C>.commands``). The
# ids MUST match ``transport_dispatch.KC_MAINTAINER_COMMAND_IDS``; an id the gate
# does not know is ignored there, so a typo here grants nothing.
COMMAND_CATALOG: tuple[dict, ...] = (
    {"id": "fs", "label": "File ops (rm/mv/cp/mkdir)", "example": "rm temp/x.txt"},
    {"id": "ls", "label": "Read via shell (ls, cat, grep, find…)", "example": "ls -la api"},
    {"id": "git-read", "label": "Git read-only (status, log, diff…)", "example": "git status"},
    {"id": "typecheck", "label": "Typecheck", "example": "npx tsc --noEmit"},
    {"id": "lint", "label": "Lint", "example": "npm run lint"},
    {"id": "build", "label": "Build", "example": "npm run build"},
    {"id": "deploy", "label": "Deploy (production)", "example": "npm run deploy / npx wrangler deploy"},
    {"id": "git-write", "label": "Git add/commit/branch/push (not main)", "example": "git push -u origin feat/x"},
    {"id": "gh-pr", "label": "GitHub PR create/view", "example": "gh pr create --title ..."},
    {"id": "wrangler-tail", "label": "Worker logs", "example": "npx wrangler tail"},
)
COMMAND_IDS = tuple(c["id"] for c in COMMAND_CATALOG)

# Owner-approved extra programs (gateway Set R, ``channels.<C>.programs``),
# usually added from Slack with "Always allow". Mirrors the gate: a program
# that is a shell, interpreter, network/remote, package-manager or privilege
# tool is never storable (it would be arbitrary code as the owner).
_PROGRAM_RE = re.compile(r"^[a-z][a-z0-9._+-]{0,31}$")
PROGRAM_NEVER = frozenset(
    {"sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh", "env", "sudo", "su", "doas", "pkexec",
     "eval", "exec", "xargs", "nohup", "setsid", "timeout", "nice", "ionice", "stdbuf", "busybox", "time",
     "watch", "script", "expect", "python", "python2", "python3", "pip", "pip3", "pipx", "uv", "uvx",
     "node", "nodejs", "deno", "bun", "perl", "ruby", "php", "lua", "awk", "gawk", "mawk", "tclsh",
     "osascript", "curl", "wget", "ssh", "scp", "sftp", "rsync", "nc", "ncat", "netcat", "socat",
     "telnet", "ftp", "openssl", "gpg", "npm", "npx", "pnpm", "yarn", "make", "cmake", "cargo", "go",
     "docker", "podman", "kubectl", "terraform", "aws", "gcloud", "az", "wrangler", "git", "gh",
     "rm", "mv", "cp", "ln", "chmod", "chown", "chgrp", "dd", "tee", "truncate", "shred", "install",
     "crontab", "at", "systemctl", "service", "kill", "pkill", "killall", "mount", "umount",
     "kirocrew", "kiro-cli", "claude", "rtk", "proxy", "cd", "source", "alias", "export", "unset", "set"}
)


def valid_program(name: Any) -> bool:
    return (
        isinstance(name, str) and bool(_PROGRAM_RE.match(name)) and name not in PROGRAM_NEVER
        and not name.startswith("rtk")
    )


def _entry(maintainers: list[str], commands: list[str], is_open: bool = False, programs: list[str] | None = None) -> dict:
    out: dict = {}
    if is_open:
        out["open"] = True
    progs = sorted({p for p in programs or [] if valid_program(p)})
    if progs:
        out["programs"] = progs
    if maintainers:
        out["maintainers"] = sorted(set(maintainers))
    if commands:
        out["commands"] = [c for c in COMMAND_IDS if c in set(commands)]
    return out


def normalize_roles(raw: Any) -> dict:
    """Clean a roles document; anything malformed is dropped (never raised)."""
    out: dict = {"channels": {}}
    chans = raw.get("channels") if isinstance(raw, dict) else None
    if not isinstance(chans, dict):
        return out
    for cid, entry in chans.items():
        if not (isinstance(cid, str) and _CHANNEL_ID_RE.match(cid) and isinstance(entry, dict)):
            continue
        ids = [u for u in entry.get("maintainers") or [] if valid_user_id(u)]
        cmds = [c for c in entry.get("commands") or [] if c in COMMAND_IDS]
        clean = _entry(ids, cmds, entry.get("open") is True, entry.get("programs") or [])
        if clean:
            out["channels"][cid] = clean
    return out


def set_maintainers(roles: dict, channel_id: str, ids: Any, member_ids: set[str]) -> dict:
    """Return a NEW roles doc with *channel_id*'s maintainers replaced.

    Every maintainer must already be a member (``slack.allowed_users``): the
    allowlist decides who may talk at all, so a maintainer outside it could
    never use the role.
    """
    if not (isinstance(channel_id, str) and _CHANNEL_ID_RE.match(channel_id)):
        raise ValueError(f"invalid channel id: {channel_id!r}")
    if not isinstance(ids, list) or not all(isinstance(u, str) for u in ids):
        raise ValueError("maintainers must be a list of Slack user ids")
    bad = [u for u in ids if not valid_user_id(u)]
    if bad:
        raise ValueError(f"invalid Slack user id: {bad[0]!r}")
    outsiders = sorted(set(ids) - member_ids)
    if outsiders:
        raise ValueError(f"not a member (add to members first): {', '.join(outsiders)}")
    new = normalize_roles(roles)
    cur = new["channels"].get(channel_id) or {}
    _put(new, channel_id, _entry(ids, cur.get("commands", []), cur.get("open") is True, cur.get("programs", [])))
    return new


def _put(roles: dict, channel_id: str, entry: dict) -> None:
    if entry:
        roles["channels"][channel_id] = entry
    else:
        roles["channels"].pop(channel_id, None)


def set_commands(roles: dict, channel_id: str, cmds: Any) -> dict:
    """Return a NEW roles doc with *channel_id*'s approved commands replaced.

    Kept even when the channel has no maintainer yet, so the approval survives
    removing and re-adding a maintainer.
    """
    if not (isinstance(channel_id, str) and _CHANNEL_ID_RE.match(channel_id)):
        raise ValueError(f"invalid channel id: {channel_id!r}")
    if not isinstance(cmds, list) or not all(isinstance(c, str) for c in cmds):
        raise ValueError("commands must be a list of command ids")
    unknown = sorted(set(cmds) - set(COMMAND_IDS))
    if unknown:
        raise ValueError(f"unknown command id: {unknown[0]!r}")
    new = normalize_roles(roles)
    cur = new["channels"].get(channel_id) or {}
    _put(new, channel_id, _entry(cur.get("maintainers", []), cmds, cur.get("open") is True, cur.get("programs", [])))
    return new


def set_programs(roles: dict, channel_id: str, progs: Any) -> dict:
    """Return a NEW roles doc with *channel_id*'s approved programs replaced."""
    if not (isinstance(channel_id, str) and _CHANNEL_ID_RE.match(channel_id)):
        raise ValueError(f"invalid channel id: {channel_id!r}")
    if not isinstance(progs, list) or not all(isinstance(p, str) for p in progs):
        raise ValueError("programs must be a list of program names")
    bad = [p for p in progs if not valid_program(p)]
    if bad:
        raise ValueError(f"program not allowed: {bad[0]!r}")
    new = normalize_roles(roles)
    cur = new["channels"].get(channel_id) or {}
    _put(new, channel_id, _entry(cur.get("maintainers", []), cur.get("commands", []), cur.get("open") is True, progs))
    return new


def set_open(roles: dict, channel_id: str, is_open: Any) -> dict:
    """Return a NEW roles doc with *channel_id*'s open flag set (gateway Set Q:
    every human member of the channel may talk to the bot there, read-only)."""
    if not (isinstance(channel_id, str) and _CHANNEL_ID_RE.match(channel_id)):
        raise ValueError(f"invalid channel id: {channel_id!r}")
    if not isinstance(is_open, bool):
        raise ValueError("open must be true or false")
    new = normalize_roles(roles)
    cur = new["channels"].get(channel_id) or {}
    _put(new, channel_id, _entry(cur.get("maintainers", []), cur.get("commands", []), is_open, cur.get("programs", [])))
    return new


def prune_roles(roles: dict, member_ids: set[str]) -> dict:
    """Drop maintainers who are no longer members (after a member removal)."""
    new = normalize_roles(roles)
    for cid in list(new["channels"]):
        cur = new["channels"][cid]
        kept = [u for u in cur.get("maintainers", []) if u in member_ids]
        _put(new, cid, _entry(kept, cur.get("commands", []), cur.get("open") is True, cur.get("programs", [])))
    return new


def people_view(cfg: dict, roles: dict, bot_channels: list[dict]) -> dict:
    """What the People card shows: members + maintainers per configured channel."""
    members = member_entries(cfg)
    roles = normalize_roles(roles)
    by_chan = roles["channels"]
    rows = [
        {
            "id": r["id"],
            "name": r["name"],
            "agent": r.get("agent", ""),
            "workspace_dir": r.get("workspace_dir", ""),
            "maintainers": (by_chan.get(r["id"]) or {}).get("maintainers", []),
            "commands": (by_chan.get(r["id"]) or {}).get("commands", []),
            "open": (by_chan.get(r["id"]) or {}).get("open") is True,
            "programs": (by_chan.get(r["id"]) or {}).get("programs", []),
        }
        for r in channel_rows(cfg, bot_channels)
        if r["configured"]
    ]
    return {"members": members, "channels": rows, "command_catalog": [dict(c) for c in COMMAND_CATALOG]}
