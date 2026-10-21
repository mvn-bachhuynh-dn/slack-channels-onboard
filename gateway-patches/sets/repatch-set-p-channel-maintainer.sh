#!/usr/bin/env bash
# ============================================================================
# Set P — per-channel MAINTAINER role (option B, chosen 2026-10-19).
#
# Roles: owner (KIROCREW_OWNER_ID, full) > maintainer (per channel) > member
# (slack.allowed_users, read-only via Set O2).
#
# A maintainer of channel C, on a turn in C whose session cwd is C's workspace:
#   - everything a member may do (read/search/think + trusted safe MCP reads)
#   - Edit/Write ONLY on files inside that workspace (realpath, symlinks
#     resolved), never under .git/ .kiro/ .claude/ .github/ .husky/ ... and never
#     .env* / .envrc / .mcp.json / .npmrc / keys (paths that would turn an edit
#     into code execution or secret access for the OWNER)
#   - shell ONLY read-only git (status diff log show blame ls-files shortlog
#     rev-parse, `branch` listing), optionally via `rtk git`, no shell
#     metacharacters, no git global options except `-C <the workspace>`.
#   NOT allowed: delete/move, fetch, spawn/cron/send/run, buttons (Set O3),
#   DM (Set M2), /kirocrew slash (Set O3), dashboard linked slot (Set O3).
#   Test/build commands are deliberately absent: with write access, `npm test`
#   runs code the maintainer just wrote = arbitrary shell as the owner.
#
# Roles file: $KIROCREW_HOME/channel-roles.json (default ~/.kiro/crew), e.g.
#   {"channels": {"C0XXXXXXXXX": {"maintainers": ["U0XXXXXXXXX"]}}}
# Kept OUT of config.json on purpose: ChannelConfig.from_dict drops unknown
# keys, so a dashboard config save would silently strip them. The maintainer
# must ALSO be in slack.allowed_users (that list decides who may talk at all).
# Read on every tool call; any error => no maintainer (fail closed).
#
# Hooks into Set O2's gate in slack/transport_dispatch.py. Requires O2.
# Idempotent via marker _kc_channel_maintainer_v1.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set P: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_channel_maintainer_v1"
p = site / "slack/transport_dispatch.py"
s = p.read_text()
if MARK in s:
    print("Set P: already applied — no-op")
else:
    if "_kc_member_readonly_v2" not in s:
        print("Set P: FAIL — Set O2 not present; apply O2 first"); sys.exit(1)
    OLD = "            if not _kc_is_owner(user_id) and not _kc_member_tool_allowed(event):\n"
    NEW = (
        f"            # Set P ({MARK}): a channel maintainer gets scoped write + git reads.\n"
        "            if (\n"
        "                not _kc_is_owner(user_id)\n"
        "                and not _kc_member_tool_allowed(event)\n"
        "                and not _kc_maintainer_tool_allowed(\n"
        "                    event, user_id, channel, agent_override, gateway, getattr(client, \"cwd\", None)\n"
        "                )\n"
        "            ):\n"
    )
    if s.count(OLD) != 1:
        print(f"Set P: FAIL anchor count={s.count(OLD)} — layout changed, re-derive"); sys.exit(1)
    s = s.replace(OLD, NEW)
    s += '''

# ---------------------------------------------------------------------------
# Set P (''' + MARK + '''): per-channel maintainer role. See
# ~/.kiro/crew/repatch-set-p-channel-maintainer.sh for the full contract.
# ---------------------------------------------------------------------------
_KC_GIT_READ_SUBCMDS = frozenset(
    {"status", "diff", "log", "show", "blame", "ls-files", "shortlog", "rev-parse", "branch"}
)
_KC_GIT_BRANCH_FLAGS = frozenset(
    {"-a", "-r", "-v", "-vv", "--all", "--remotes", "--list", "--show-current", "--no-color"}
)
_KC_GIT_DENY_ARG_PREFIXES = ("--output", "--ext-diff", "--exec", "--textconv", "--git-dir", "--work-tree")
_KC_SHELL_META = frozenset(";&|$`<>(){}\\\\\\n\\r")
_KC_DENY_DIRS = frozenset(
    {".git", ".kiro", ".claude", ".github", ".gitlab", ".husky", ".githooks", ".vscode",
     ".idea", ".devcontainer", ".circleci", ".ssh", ".aws", ".gnupg", "node_modules"}
)
_KC_DENY_FILES = frozenset(
    {".envrc", ".mcp.json", ".npmrc", ".yarnrc", ".yarnrc.yml", ".pypirc", ".netrc",
     ".gitmodules", ".gitattributes", ".gitconfig", ".pre-commit-config.yaml", "id_rsa", "id_ed25519"}
)
_KC_DENY_SUFFIXES = (".pem", ".key", ".p12", ".pfx")


def _kc_roles_path() -> Any:
    import os
    from pathlib import Path

    home = os.environ.get("KIROCREW_HOME") or str(Path.home() / ".kiro" / "crew")
    return Path(home) / "channel-roles.json"


def _kc_is_channel_maintainer(user_id: str, channel: str) -> bool:
    """True when *user_id* is listed as a maintainer of *channel*. Fail closed."""
    if not user_id or not channel:
        return False
    try:
        import json

        data = json.loads(_kc_roles_path().read_text(encoding="utf-8"))
        entry = ((data or {}).get("channels") or {}).get(channel) or {}
        return user_id in set(entry.get("maintainers") or [])
    except Exception:
        return False


def _kc_inside(root: str, path: str) -> bool:
    import os

    try:
        return os.path.commonpath([root, path]) == root
    except ValueError:
        return False


def _kc_write_target_ok(path: str, root: str) -> bool:
    import os

    expanded = os.path.expanduser(os.path.expandvars(path))
    if not os.path.isabs(expanded):
        return False
    real = os.path.realpath(expanded)
    if real == root or not _kc_inside(root, real):
        return False
    parts = os.path.relpath(real, root).split(os.sep)
    if any(part in _KC_DENY_DIRS for part in parts[:-1]):
        return False
    name = parts[-1]
    low = name.lower()
    if low in _KC_DENY_FILES or low.startswith(".env") or low.endswith(_KC_DENY_SUFFIXES):
        return False
    if name in _KC_DENY_DIRS:
        return False
    return True


def _kc_git_read_ok(cmd: str, root: str) -> bool:
    import os
    import shlex

    if not cmd or any(ch in _KC_SHELL_META for ch in cmd):
        return False
    try:
        toks = shlex.split(cmd)
    except ValueError:
        return False
    if toks and toks[0] == "rtk":
        toks = toks[1:]
    if not toks or toks[0] != "git":
        return False
    i = 1
    while i < len(toks) and toks[i].startswith("-"):
        if toks[i] == "--no-pager":
            i += 1
            continue
        if toks[i] == "-C" and i + 1 < len(toks):
            if os.path.realpath(os.path.expanduser(toks[i + 1])) != root:
                return False
            i += 2
            continue
        return False  # -c, --exec-path, --git-dir, --config-env, ... denied
    if i >= len(toks) or toks[i] not in _KC_GIT_READ_SUBCMDS:
        return False
    sub, args = toks[i], toks[i + 1 :]
    if any(a.startswith(_KC_GIT_DENY_ARG_PREFIXES) for a in args):
        return False
    if sub == "branch" and any(a not in _KC_GIT_BRANCH_FLAGS for a in args):
        return False  # listing only: no create/delete/rename
    return True


def _kc_maintainer_tool_allowed(
    event: Any, user_id: str, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any
) -> bool:
    """Scoped write + read-only git for a maintainer of THIS channel's workspace.

    The write root is the workspace of the channel's configured agent, and the
    live session must run there too (a ``!agent`` switch to another workspace
    drops the maintainer back to member). Deny by default on every doubt.
    """
    import os

    if not _kc_is_channel_maintainer(user_id, channel):
        return False
    _ka, ws = _agent_workspace_binding(gateway, channel_agent)
    if not ws or not session_cwd:
        return False
    root = os.path.realpath(os.path.expanduser(ws))
    if os.path.realpath(os.path.expanduser(str(session_cwd))) != root or root == os.sep:
        return False
    kind = (getattr(event, "tool_kind", "") or "").lower()
    allowed = False
    if getattr(event, "is_shell", False):
        allowed = _kc_git_read_ok(getattr(event, "shell_command", None) or "", root)
    elif kind == "edit" or getattr(event, "diff_path", ""):
        from kiro_crew.platform.tool_paths import edit_target_candidates

        cands = edit_target_candidates(
            getattr(event, "raw_tool_params", None), getattr(event, "diff_path", "") or ""
        )
        allowed = bool(cands) and not cands.truncated and not cands.unanchored
        allowed = allowed and all(_kc_write_target_ok(str(c), root) for c in cands)
    if allowed:
        sel().log_api_access(
            caller=user_id,
            operation="slack.channel_maintainer",
            outcome="allowed",
            source="slack",
            resources=f"channel={channel} kind={kind} tool={getattr(event, 'tool_name', '')}",
        )
    return allowed
'''
    shutil.copy2(p, p.with_name(p.name + f".bak-setp-{stamp}"))
    p.write_text(s)
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()
    print("Set P: patched slack/transport_dispatch.py")

import importlib
TD = importlib.import_module("kiro_crew.slack.transport_dispatch")
for n in ("_kc_maintainer_tool_allowed", "_kc_git_read_ok", "_kc_write_target_ok", "_agent_workspace_binding", "sel"):
    assert hasattr(TD, n), n
print("Set P: OK (imports + names verified)")
PY
