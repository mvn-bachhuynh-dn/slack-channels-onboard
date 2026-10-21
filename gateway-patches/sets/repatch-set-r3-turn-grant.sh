#!/usr/bin/env bash
# ============================================================================
# Set R3 — "one approval per prompt" for maintainers (2026-10-20).
#
# Live test: one investigation prompt from a maintainer produced ~15 owner cards
# (its commands used `grep -r`, `$VAR`, `> file`, `npx tsx` … which no durable
# rule can cover), and an unanswered card timed out after 2 min, after which the
# model simply tried another command and posted ANOTHER card.
#
# 1. The maintainer card gets a 4th button:
#      [Cho phép 1 lần] [Cho phép cả lượt này] [Luôn cho phép: …] [Từ chối]
#    "Cho phép cả lượt này" (owner only) approves this call AND every later
#    maintainer call in the SAME TURN (the reply to that one Slack message), at
#    most 30 min / 200 calls, while the call stays inside the workspace:
#      - file tools: every path inside the channel workspace and not a secret
#        name (same READ/WRITE checks as Sets P/Q)
#      - shell: no path token outside the workspace (only /dev/null, /dev/stdout,
#        /dev/stderr allowed), no ~ / $HOME, no URL (://), no secret-looking
#        name, none of: curl wget ssh scp sftp rsync nc ncat netcat socat telnet
#        ftp sudo su doas pkexec eval crontab systemctl
#      - MCP / fetch / other tool kinds: never covered
#    Anything not covered still posts a normal card. Keystone/deny-list hook
#    denials stay final. Keyed by the turn's approval decider (one per turn),
#    held weakly: the grant dies with the turn.
# 2. "Từ chối", or a card left unanswered until it expires, ends asking for the
#    rest of that turn: later maintainer requests are denied without a new card
#    (the model is told the owner declined), so no card storm.
#
# Requires Set R/R2. Idempotent via marker _kc_turn_grant_v1.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set R3: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_turn_grant_v1"
plans = []


def plan(rel, needs, edits, tail=""):
    p = site / rel
    s = p.read_text()
    if MARK in s:
        print(f"Set R3: {rel} already applied — no-op")
        return
    for n in needs:
        if n not in s:
            print(f"Set R3: FAIL — {rel} lacks {n}"); sys.exit(1)
    for old, _new in edits:
        if s.count(old) != 1:
            print(f"Set R3: FAIL {rel} anchor count={s.count(old)} for {old[:70]!r}"); sys.exit(1)
    for old, new in edits:
        s = s.replace(old, new)
    plans.append((p, s + tail))


# ---------------------------------------------------------------- card
plan(
    "slack/renderer.py",
    ["_kc_maintainer_ask_owner_v1"],
    [(
        "    buttons = [{\n"
        "        \"type\": \"button\", \"text\": {\"type\": \"plain_text\", \"text\": \"Cho phép 1 lần\"}, \"style\": \"primary\",\n"
        "        \"action_id\": f\"{TOOL_APPROVE_ACTION_PREFIX}{key}\", \"value\": token,\n"
        "    }]\n",
        "    buttons = [{\n"
        "        \"type\": \"button\", \"text\": {\"type\": \"plain_text\", \"text\": \"Cho phép 1 lần\"}, \"style\": \"primary\",\n"
        "        \"action_id\": f\"{TOOL_APPROVE_ACTION_PREFIX}{key}\", \"value\": token,\n"
        "    }, {  # Set R3 (" + MARK + ")\n"
        "        \"type\": \"button\", \"text\": {\"type\": \"plain_text\", \"text\": \"Cho phép cả lượt này\"},\n"
        "        \"action_id\": f\"{KC_TURN_ACTION_PREFIX}{key}\", \"value\": token,\n"
        "    }]\n",
    )],
    r'''

# ---------------------------------------------------------------------------
# Set R3 (''' + MARK + r'''): per-turn maintainer grants. Keyed by the turn's
# SlackApprovalDecider (one per turn), weakly, so a grant dies with its turn.
# ---------------------------------------------------------------------------
import weakref as _kc_weakref

KC_TURN_ACTION_PREFIX = "mc_tool_kcturn_"
KC_TURN_GRANT_SECS = 1800.0
KC_TURN_GRANT_MAX = 200
_KC_TURN_STATE: "_kc_weakref.WeakKeyDictionary" = _kc_weakref.WeakKeyDictionary()
''',
)

# ---------------------------------------------------------------- click
plan(
    "slack/interactions.py",
    ["_kc_maintainer_ask_owner_v1"],
    [
        (
            "        or action_id.startswith(TOOL_DENY_ACTION_PREFIX)\n    ):\n",
            "        or action_id.startswith(TOOL_DENY_ACTION_PREFIX)\n"
            f"        or action_id.startswith(\"mc_tool_kcturn_\")  # Set R3 ({MARK})\n    ):\n",
        ),
        (
            "        approved = is_trust or action_id.startswith(TOOL_APPROVE_ACTION_PREFIX)\n",
            "        _kc_turn_click = action_id.startswith(\"mc_tool_kcturn_\")  # Set R3\n"
            "        approved = is_trust or _kc_turn_click or action_id.startswith(TOOL_APPROVE_ACTION_PREFIX)\n",
        ),
        (
            "            is_trust = False\n            _kc_rmod._KC_ASK_OWNER.pop(approval_key, None)\n",
            "            # Set R3: per-turn grant / per-turn refusal, keyed by the turn's decider.\n"
            "            _kc_dec = (_kc_entry.get(\"decider\") or (lambda: None))()\n"
            "            _kc_live = bool(SlackApprovalDecider.session_for(approval_key, nonce=press_nonce))\n"
            "            if _kc_dec is not None and _kc_live:\n"
            "                import time as _kc_time\n"
            "                if _kc_turn_click and is_owner(user_id):\n"
            "                    _kc_rmod._KC_TURN_STATE[_kc_dec] = {\n"
            "                        \"mode\": \"allow\", \"until\": _kc_time.monotonic() + _kc_rmod.KC_TURN_GRANT_SECS,\n"
            "                        \"left\": _kc_rmod.KC_TURN_GRANT_MAX, \"by\": user_id,\n"
            "                    }\n"
            "                    _kc_persisted = _kc_persisted or \"cả lượt này (trong workspace)\"\n"
            "                    sel().log_api_access(caller=user_id, operation=\"slack.maintainer_turn_grant\",\n"
            "                                         outcome=\"allowed\", source=\"slack\",\n"
            "                                         resources=f\"channel={_kc_entry.get('channel')} maintainer={_kc_entry.get('user')}\")\n"
            "                elif not approved:\n"
            "                    _kc_rmod._KC_TURN_STATE[_kc_dec] = {\"mode\": \"deny\", \"until\": _kc_time.monotonic() + _kc_rmod.KC_TURN_GRANT_SECS}\n"
            "            is_trust = False\n            _kc_rmod._KC_ASK_OWNER.pop(approval_key, None)\n",
        ),
    ],
)

# ---------------------------------------------------------------- gate
plan(
    "slack/transport_dispatch.py",
    ["_kc_rtk_normalize_v1"],
    [(
        "                if not _kc_ask_owner_register(\n"
        "                    event, user_id, channel, agent_override, gateway, getattr(client, \"cwd\", None), decider\n"
        "                ):\n"
        "                    return \"deny\"\n"
        "                _kc_ask = True\n",
        f"                _kc_turn = _kc_turn_verdict(  # Set R3 ({MARK})\n"
        "                    event, user_id, channel, agent_override, gateway, getattr(client, \"cwd\", None), decider\n"
        "                )\n"
        "                if _kc_turn == \"allow\":\n"
        "                    _kc_auto = True\n"
        "                elif _kc_turn == \"deny\" or not _kc_ask_owner_register(\n"
        "                    event, user_id, channel, agent_override, gateway, getattr(client, \"cwd\", None), decider\n"
        "                ):\n"
        "                    return \"deny\"\n"
        "                else:\n"
        "                    _kc_ask = True\n",
    )],
    r'''

# ---------------------------------------------------------------------------
# Set R3 (''' + MARK + r'''): per-turn grant / refusal for maintainer asks.
# See ~/.kiro/crew/repatch-set-r3-turn-grant.sh.
# ---------------------------------------------------------------------------
_KC_TURN_NEVER_WORDS = frozenset(
    {"curl", "wget", "ssh", "scp", "sftp", "rsync", "nc", "ncat", "netcat", "socat", "telnet", "ftp",
     "sudo", "su", "doas", "pkexec", "eval", "crontab", "systemctl"}
)
_KC_TURN_DEV_OK = frozenset({"/dev/null", "/dev/stdout", "/dev/stderr"})
_KC_TURN_TOKEN_RE = __import__("re").compile(r"[^\s'\"=;&|<>()`,]+")


def _kc_turn_covers(event: Any, root: str) -> bool:
    """Whether a per-turn grant may answer this call: it stays inside the workspace."""
    import os

    if getattr(event, "is_shell", False):
        cmd = getattr(event, "shell_command", None) or ""
        if not cmd or "\n" in cmd or "://" in cmd or "$HOME" in cmd or "${HOME" in cmd:
            return False
        for tok in _KC_TURN_TOKEN_RE.findall(cmd):
            t = tok.strip()
            if not t:
                continue
            if t in _KC_TURN_NEVER_WORDS or os.path.basename(t) in _KC_TURN_NEVER_WORDS:
                return False
            if t.startswith("~"):
                return False
            if t in _KC_TURN_DEV_OK:
                continue
            name = t.rstrip("/").rsplit("/", 1)[-1]
            if name and _KC_SECRET_NAME_RE.search(name):
                return False
            if "/" in t or t.startswith("."):
                real = os.path.realpath(t if os.path.isabs(t) else os.path.join(root, t))
                if not _kc_inside(root, real):
                    return False
                parts = os.path.relpath(real, root).split(os.sep) if real != root else []
                if any(p in _KC_READ_DENY_DIRS - {".git"} for p in parts):
                    return False
        return True
    kind = (getattr(event, "tool_kind", "") or "").lower()
    if getattr(event, "mcp_server_name", "") or kind not in ("read", "search", "edit", "delete", "move"):
        return False
    from kiro_crew.platform.tool_paths import edit_target_candidates

    cands = edit_target_candidates(getattr(event, "raw_tool_params", None), getattr(event, "diff_path", "") or "")
    if cands.truncated or cands.unanchored:
        return False
    check = _kc_read_target_ok if kind in ("read", "search") else _kc_write_target_ok
    for c in cands:
        x = os.path.expanduser(str(c))
        if not os.path.isabs(x):
            x = os.path.join(root, x)
        if not check(x, root):
            return False
    return True


def _kc_turn_verdict(
    event: Any, user_id: str, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any, decider: Any
) -> str:
    """'allow' (owner granted the rest of this turn), 'deny' (owner declined / let a card
    expire this turn), or '' (ask as usual)."""
    import time

    if decider is None or not _kc_is_channel_maintainer(user_id, channel):
        return ""
    try:
        from kiro_crew.slack import renderer as _r
        from kiro_crew.constants import DENY_CAUSE_APPROVAL_TIMEOUT
    except Exception:
        return ""
    st = _r._KC_TURN_STATE.get(decider)
    now = time.monotonic()
    if getattr(decider, "last_deny_cause", "") == DENY_CAUSE_APPROVAL_TIMEOUT and not (st and st.get("mode") == "allow"):
        st = {"mode": "deny", "until": now + _r.KC_TURN_GRANT_SECS}
        _r._KC_TURN_STATE[decider] = st
    if not st or st.get("until", 0) < now:
        return ""
    if st.get("mode") == "deny":
        sel().log_api_access(caller=user_id, operation="slack.maintainer_ask_owner", outcome="denied",
                             source="slack", resources=f"channel={channel}", error="owner declined this turn")
        return "deny"
    root, cwd_ok = _kc_channel_root(channel_agent, gateway, session_cwd)
    if not root or not cwd_ok or st.get("left", 0) <= 0 or not _kc_turn_covers(event, root):
        return ""
    st["left"] = st.get("left", 0) - 1
    sel().log_api_access(caller=user_id, operation="slack.maintainer_turn_grant", outcome="used",
                         source="slack", resources=f"channel={channel} left={st['left']} kind={getattr(event, 'tool_kind', '')}")
    return "allow"


_kc_r_ask_owner_register = _kc_ask_owner_register


def _kc_ask_owner_register(  # noqa: F811
    event: Any, user_id: str, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any, decider: Any
) -> bool:
    """Set R register, plus a weak reference to the turn's decider for the R3 buttons."""
    import weakref

    ok = _kc_r_ask_owner_register(event, user_id, channel, channel_agent, gateway, session_cwd, decider)
    if ok:
        try:
            from kiro_crew.slack import renderer as _r

            key = _r._approval_registry_key(getattr(decider, "session_key", "") or "", getattr(event, "request_id", ""))
            if key in _r._KC_ASK_OWNER:
                _r._KC_ASK_OWNER[key]["decider"] = weakref.ref(decider)
        except Exception:
            pass
    return ok
''',
)

for p, text in plans:
    shutil.copy2(p, p.with_name(p.name + f".bak-setr3-{stamp}"))
    p.write_text(text)
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()
    print(f"Set R3: patched {p.relative_to(site)}")

import importlib, inspect
TD = importlib.import_module("kiro_crew.slack.transport_dispatch")
R = importlib.import_module("kiro_crew.slack.renderer")
I = importlib.import_module("kiro_crew.slack.interactions")
assert hasattr(TD, "_kc_turn_verdict") and hasattr(R, "_KC_TURN_STATE")
assert "mc_tool_kcturn_" in inspect.getsource(I)
print("Set R3: OK")
PY
