#!/usr/bin/env bash
# ============================================================================
# Set M — Slack DM is OWNER-ONLY (non-owner DMs are dropped silently).
#
# PROBLEM: the allow-list (Set K) grants "may chat with the bot" GLOBALLY — it
# does not distinguish a message sent in an approved CHANNEL from a private
# Direct Message. So an allow-listed non-owner could DM the bot
# directly, outside any channel the operator added them to. That is a privilege
# the operator never intended to grant.
#
# FIX: at the very top of `handle_message` (slack/handler.py), drop any message
# whose channel is a DM (Slack DM channel ids start with "D") UNLESS the sender
# is the owner. Absolute block: no turn, no command, no status, no approval —
# the handler returns before any branch. Silent (no reply), matching how
# upstream ignores an unauthorized user. The owner keeps full DM access.
#
# Net effect: an allow-listed non-owner can use the bot ONLY inside the channels
# they were added to; they can no longer DM it privately.
#
# This is a SECURITY TIGHTENING (unlike Set K which loosens). Idempotent via the
# _kc_dm_owner_only marker. Anchor: the first executable lines of handle_message
# (`Stats().inc_message_received()` + `_t0 = time.monotonic()`), unique in 0.8.0.
# ============================================================================
set -uo pipefail

SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
if [ -z "$SITE" ]; then echo "Set M: installed kirocrew venv not found — skipping"; exit 0; fi
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
HD="$SITE/slack/handler.py"
[ -f "$HD" ] || { echo "Set M: $HD not found — layout changed; re-check anchors."; exit 1; }

python3 - "$HD" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()

if "_kc_dm_owner_only" in s:
    print("Set M (DM owner-only): already applied — no-op"); sys.exit(0)

ANCHOR = (
    "    Stats().inc_message_received()\n"
    "    _t0 = time.monotonic()\n"
)
GATE = ANCHOR + (
    "    # Set M (_kc_dm_owner_only): a Direct Message is owner-only. The Set K\n"
    "    # allow-list grants chat access globally, not per-channel, so an\n"
    "    # allow-listed non-owner could otherwise DM the bot outside any channel\n"
    "    # they were added to. Slack DM channel ids start with 'D'. Drop silently\n"
    "    # (no reply, matching how an unauthorized user is ignored) before any\n"
    "    # branch — turn, command, status, approval. The owner keeps DM access.\n"
    "    if channel.startswith(\"D\") and not is_owner(user_id):\n"
    "        logger.info(\n"
    "            \"Set M: dropped non-owner DM from %s in %s\", user_id, channel\n"
    "        )\n"
    "        sel().log_api_access(\n"
    "            caller=user_id,\n"
    "            operation=\"slack.dm_owner_only\",\n"
    "            outcome=\"denied\",\n"
    "            source=\"slack\",\n"
    "            resources=channel,\n"
    "            error=\"non-owner DM blocked (Set M)\",\n"
    "        )\n"
    "        return\n"
)
if s.count(ANCHOR) != 1:
    print("Set M: handle_message anchor not unique — CHECK ANCHORS"); sys.exit(1)
p.write_text(s.replace(ANCHOR, GATE, 1))
print("Set M [handler.py]: OK")
PY

# ---- compile ---------------------------------------------------------------
if [ -n "$VENV_PY" ]; then
  "$VENV_PY" -m py_compile "$HD" && echo "Set M: compile OK" || { echo "Set M: compile FAILED"; exit 1; }
else
  python3 -m py_compile "$HD" && echo "Set M: compile OK (fallback python3)"
fi

# ---- prove: the gate is present and shaped right ---------------------------
# Static proof (no live Slack): the inserted gate must (a) key off a DM channel
# prefix, (b) exempt the owner, (c) return early. We assert the exact clause is
# present and that it sits INSIDE handle_message before the first branch.
python3 - "$HD" <<'PY'
import sys, pathlib, re
s = pathlib.Path(sys.argv[1]).read_text()
clause = 'if channel.startswith("D") and not is_owner(user_id):'
assert clause in s, "Set M: gate clause missing"
# gate must appear AFTER 'async def handle_message(' and BEFORE the first
# 'is_allowed_user(' use inside the body (the first real branch gate).
i_def = s.index("async def handle_message(")
i_gate = s.index(clause, i_def)
i_first_allowed = s.index("is_allowed_user(", i_def)
assert i_def < i_gate < i_first_allowed, "Set M: gate not positioned before first branch"
# and it must return (absolute block), not merely log
tail = s[i_gate:i_gate+600]
assert "\n        return\n" in tail, "Set M: gate does not return early"
print("Set M: prove OK — DM gate present, owner-exempt, early-return, before first branch")
PY
