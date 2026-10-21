#!/usr/bin/env bash
# ============================================================================
# Set Q — (B) non-owner READS scoped to the channel workspace, and
#         (A) "open channel": every human member of an opted-in channel may
#             talk to the bot THERE as a read-only member (2026-10-20).
#
# B, slack/transport_dispatch.py (_tool_gate): Set O2's member allow set is
#   narrowed for every non-owner (members AND maintainers):
#     - read/search tools: every path they name (path/file_path/filePath at any
#       depth, a Glob tool's pattern) must pass Set P3's _kc_read_target_ok
#       against the workspace of the CHANNEL's agent; a relative path / a call
#       with no path is only allowed when the live session cwd IS that
#       workspace (else it would resolve elsewhere, e.g. the pool cwd).
#     - trusted MCP reads: only Read/Glob/Grep (same path rule) and
#       WorkspaceSearch (cwd must be the workspace). Dropped for non-owners:
#       local_knowledge_search, learn_list, cron_list, spawn_list/status,
#       artifact_* — they read state of OTHER projects.
#     - shell: `ls` / `tree` / `pwd` inside the workspace (Set P3 grammar),
#       auto-approved; nothing else.
#   LIMIT: git history is not path-filtered for maintainers (`git show <sha>`
#   can print a secret that was committed). Remove + rotate committed secrets.
#
# A, slack/events.py (_route_message admission): a sender NOT in
#   slack.allowed_users is admitted when channel-roles.json has
#   channels.<C>.open = true AND Slack users.info says: human (not bot/app),
#   active, not a guest (is_restricted / is_ultra_restricted), not a Slack
#   Connect stranger, and team_id == the channel's home workspace. Admission is
#   for THAT channel only and carries member rights (O2/Q above, O3 buttons and
#   slash owner-only, M2 DMs owner-only). Cached 10 min (deny 2 min), fail
#   closed on any error. SEL: slack.open_channel_member.
#   Not covered (stays deny, fail closed): `!stop`, linked dashboard threads,
#   inbound-spool replay — those still require slack.allowed_users.
#
# Requires Sets O2, P, P2, P3. Idempotent via marker _kc_open_channel_v1.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set Q: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_open_channel_v1"


def patch(rel, needs, edits, tail):
    p = site / rel
    s = p.read_text()
    if MARK in s:
        print(f"Set Q: {rel} already applied — no-op")
        return
    for n in needs:
        if n not in s:
            print(f"Set Q: FAIL — {rel} lacks {n}; apply prerequisite Sets first"); sys.exit(1)
    for old, _new in edits:
        if s.count(old) != 1:
            print(f"Set Q: FAIL {rel} anchor count={s.count(old)} for {old[:60]!r} — re-derive"); sys.exit(1)
    for old, new in edits:
        s = s.replace(old, new)
    s += tail
    shutil.copy2(p, p.with_name(p.name + f".bak-setq-{stamp}"))
    p.write_text(s)
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()
    print(f"Set Q: patched {rel}")


# ---------------------------------------------------------------- B (reads)
patch(
    "slack/transport_dispatch.py",
    ["_kc_maintainer_file_ops_v1"],
    [
        (
            "            _kc_auto = not _kc_is_owner(user_id) and _kc_maintainer_cmd_approved(\n"
            "                event, user_id, channel, agent_override, gateway, getattr(client, \"cwd\", None)\n"
            "            )\n",
            "            _kc_auto = not _kc_is_owner(user_id) and _kc_maintainer_cmd_approved(\n"
            "                event, user_id, channel, agent_override, gateway, getattr(client, \"cwd\", None)\n"
            "            )\n"
            f"            # Set Q ({MARK}): non-owner reads/listing scoped to the channel workspace.\n"
            "            _kc_auto = _kc_auto or (\n"
            "                not _kc_is_owner(user_id)\n"
            "                and _kc_member_shell_ok(event, channel, agent_override, gateway, getattr(client, \"cwd\", None))\n"
            "            )\n",
        ),
        (
            "                and not _kc_member_tool_allowed(event)\n",
            "                and not _kc_member_tool_scoped(\n"
            "                    event, channel, agent_override, gateway, getattr(client, \"cwd\", None)\n"
            "                )\n",
        ),
    ],
    r'''

# ---------------------------------------------------------------------------
# Set Q (''' + MARK + r'''): non-owner reads scoped to the channel workspace.
# See ~/.kiro/crew/repatch-set-q-open-channel-scoped-read.sh.
# ---------------------------------------------------------------------------
_KC_MEMBER_PATH_TOOLS = frozenset({"Read", "Glob", "Grep"})
_KC_MEMBER_CWD_TOOLS = frozenset({"WorkspaceSearch"})
_KC_MEMBER_DENY_TOOLS = frozenset(
    {"local_knowledge_search", "learn_list", "cron_list", "spawn_list", "spawn_status",
     "artifact_get", "artifact_list", "artifact_versions", "knowledge"}
)


def _kc_channel_root(channel_agent: Any, gateway: Any, session_cwd: Any) -> Any:
    """(workspace root, session cwd is that root) for the channel's agent, or (None, False)."""
    import os

    _ka, ws = _agent_workspace_binding(gateway, channel_agent)
    if not ws:
        return None, False
    root = os.path.realpath(os.path.expanduser(ws))
    if root == os.sep:
        return None, False
    cwd_ok = bool(session_cwd) and os.path.realpath(os.path.expanduser(str(session_cwd))) == root
    return root, cwd_ok


def _kc_glob_base(pattern: str) -> str:
    import os

    cut = len(pattern)
    for ch in "*?[{":
        i = pattern.find(ch)
        if i >= 0:
            cut = min(cut, i)
    head = pattern[:cut]
    return head if head.endswith(os.sep) or cut == len(pattern) else os.path.dirname(head)


def _kc_member_tool_scoped(event: Any, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any) -> bool:
    """Set O2's read-only allow set, narrowed to the channel workspace. Deny on doubt."""
    import os

    if getattr(event, "is_shell", False) or not _kc_member_tool_allowed(event):
        return False
    kind = (getattr(event, "tool_kind", "") or "").lower()
    if kind == "think":
        return True
    name = getattr(event, "tool_name", "") or ""
    if name in _KC_MEMBER_DENY_TOOLS:
        return False
    if (getattr(event, "mcp_server_name", "") or "") and name not in _KC_MEMBER_PATH_TOOLS | _KC_MEMBER_CWD_TOOLS:
        return False  # an MCP read can reach state outside this workspace
    root, cwd_ok = _kc_channel_root(channel_agent, gateway, session_cwd)
    if not root:
        return False
    if name in _KC_MEMBER_CWD_TOOLS:
        return cwd_ok
    from kiro_crew.platform.tool_paths import target_paths

    raw = getattr(event, "raw_tool_params", None)
    cands = target_paths(raw)
    if cands.truncated:
        return False
    paths = [str(c) for c in cands]
    title = (getattr(event, "title", "") or "").lower()
    if isinstance(raw, dict) and ("glob" in name.lower() or title.startswith("glob")):
        pat = raw.get("pattern")
        if isinstance(pat, str) and pat:
            paths.append(_kc_glob_base(pat) or ".")
    if not paths:
        return cwd_ok
    for x in paths:
        x = os.path.expanduser(x)
        if not os.path.isabs(x):
            if not cwd_ok:
                return False
            x = os.path.join(root, x)
        if not _kc_read_target_ok(x, root):
            return False
    return True


def _kc_member_shell_ok(event: Any, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any) -> bool:
    """`ls` / `tree` / `pwd` inside the channel workspace, for any non-owner sender."""
    if not getattr(event, "is_shell", False):
        return False
    root, cwd_ok = _kc_channel_root(channel_agent, gateway, session_cwd)
    if not root or not cwd_ok:
        return False
    ids = _kc_approved_cmd_ids(getattr(event, "shell_command", None) or "", root)
    return bool(ids) and set(ids) <= {"ls"}
''',
)

# ---------------------------------------------------------------- A (admission)
patch(
    "slack/events.py",
    ["_kc_dm_owner_only_v2"],
    [
        (
            "    _owner_authorized = is_allowed_user(sender_id)\n",
            "    _owner_authorized = is_allowed_user(sender_id)\n"
            f"    # Set Q ({MARK}): open channel -> any human member of THIS channel, read-only.\n"
            "    if not _owner_authorized and not from_trusted_bot:\n"
            "        _owner_authorized = await _kc_open_channel_admit(orch, channel, sender_id)\n",
        ),
    ],
    r'''

# ---------------------------------------------------------------------------
# Set Q (''' + MARK + r'''): open-channel admission. See
# ~/.kiro/crew/repatch-set-q-open-channel-scoped-read.sh.
# ---------------------------------------------------------------------------
_KC_OPEN_CACHE: dict = {}
_KC_OPEN_CACHE_MAX = 2000
_KC_OPEN_TTL_OK = 600.0
_KC_OPEN_TTL_DENY = 120.0


def _kc_channel_is_open(channel: str) -> bool:
    try:
        import json

        from kiro_crew.slack.transport_dispatch import _kc_roles_path

        data = json.loads(_kc_roles_path().read_text(encoding="utf-8"))
        entry = ((data or {}).get("channels") or {}).get(channel) or {}
        return entry.get("open") is True
    except Exception:
        return False


async def _kc_open_channel_user_ok(orch: Any, channel: str, user_id: str) -> tuple:
    """(ok, reason) from Slack users.info. Fail closed."""
    client = getattr(orch, "slack", None)
    web = getattr(client, "_web", None)
    if web is None:
        return False, "no slack client"
    resp = await web.users_info(user=user_id)
    u = (resp.get("user") if hasattr(resp, "get") else None) or {}
    if not u or u.get("id") != user_id:
        return False, "users.info empty"
    if u.get("is_bot") or u.get("is_app_user") or user_id == "USLACKBOT":
        return False, "bot"
    if u.get("deleted"):
        return False, "deactivated"
    if u.get("is_restricted") or u.get("is_ultra_restricted"):
        return False, "guest"
    if u.get("is_stranger"):
        return False, "slack connect stranger"
    home = (getattr(client, "_channel_team", None) or {}).get(channel, "")
    if not home:
        try:
            auth = await web.auth_test()
            home = str(auth.get("team_id") or "")
        except Exception:
            home = ""
    team = str(u.get("team_id") or (u.get("profile") or {}).get("team") or "")
    if not home or team != home:
        return False, f"other workspace ({team or '?'})"
    return True, "ok"


async def _kc_open_channel_admit(orch: Any, channel: str, user_id: str) -> bool:
    import time

    if not user_id or not channel or channel[:1] not in ("C", "G"):
        return False
    if not _kc_channel_is_open(channel):
        return False
    key = (channel, user_id)
    now = time.monotonic()
    hit = _KC_OPEN_CACHE.get(key)
    if hit and hit[0] > now:
        return hit[1]
    try:
        ok, reason = await _kc_open_channel_user_ok(orch, channel, user_id)
    except Exception as exc:  # noqa: BLE001 - fail closed
        ok, reason = False, f"lookup failed: {type(exc).__name__}"
    if len(_KC_OPEN_CACHE) >= _KC_OPEN_CACHE_MAX:
        _KC_OPEN_CACHE.clear()
    _KC_OPEN_CACHE[key] = (now + (_KC_OPEN_TTL_OK if ok else _KC_OPEN_TTL_DENY), ok)
    sel().log_api_access(
        caller=user_id,
        operation="slack.open_channel_member",
        outcome="allowed" if ok else "denied",
        source="slack",
        resources=f"channel={channel}",
        error="" if ok else reason,
    )
    logger.info("Set Q: open channel %s %s %s (%s)", channel, "admitted" if ok else "refused", user_id, reason)
    return ok
''',
)

import importlib
TD = importlib.import_module("kiro_crew.slack.transport_dispatch")
EV = importlib.import_module("kiro_crew.slack.events")
for mod, n in ((TD, "_kc_member_tool_scoped"), (TD, "_kc_member_shell_ok"), (EV, "_kc_open_channel_admit")):
    assert hasattr(mod, n), n
print("Set Q: OK (imports + names verified)")
PY
