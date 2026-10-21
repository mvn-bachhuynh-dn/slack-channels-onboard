#!/usr/bin/env bash
# ============================================================================
# Set O — member read-only (owner full, non-owner read-only).
#
# PROBLEM: Set K's allow-list is binary — a user is either allowed (full tool
# access, including write/execute) or blocked. There is no "allowed to chat but
# read-only" tier. So adding a teammate to slack.allowed_users so they can use
# the bot in a channel ALSO lets them make the bot write files and run commands
# in that channel's workspace (e.g. a real repo). Worse, the interactive
# approval buttons (handle_interaction) gate on is_allowed_user, NOT is_owner —
# the docstring says "rejects non-owner clicks" but the code lets any
# allow-listed member click Approve/Trust on a write tool.
#
# FIX (two layers, defense in depth):
#   L1 handle_message — for a NON-OWNER sender, reject any tool that is not in
#      the reviewed read-only safe set (HEARTBEAT_SAFE_TOOLS: built-in Read/
#      Grep/Glob/WorkspaceSearch + side-effect-free kirocrew-core reads such as
#      local_knowledge_search). Write/execute/send/spawn/cron are rejected
#      before any approve path, with a SEL audit event. The owner is unaffected.
#   L2 handle_interaction — change the Approve/Trust button gate from
#      is_allowed_user to is_owner, so even if a prompt leaks, only the owner
#      can approve a tool or widen a session to Trust. reject_tool stays open to
#      any allow-listed user (rejecting is not an escalation).
#
# Net: a member added to the allow-list can only READ via the bot (and the
# curated MCP reads); they cannot make it write, execute, send, spawn, or trust.
# The owner keeps full control.
#
# Classification reuses gateway._is_heartbeat_safe_tool (strict exact-name match
# after title normalization) — the same read-only authority heartbeat trusts —
# so "read-only" is not redefined here. name_grant still guards PATH-shadowing
# for anything that does reach the owner's interactive path.
#
# Idempotent via the _kc_member_readonly marker. Anchors verified on 0.8.0.
# ============================================================================
set -uo pipefail

SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
if [ -z "$SITE" ]; then echo "Set O: installed kirocrew venv not found — skipping"; exit 0; fi
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
HD="$SITE/slack/handler.py"
[ -f "$HD" ] || { echo "Set O: $HD not found — layout changed; re-check anchors."; exit 1; }

python3 - "$HD" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()

if "_kc_member_readonly" in s:
    print("Set O (member read-only): already applied — no-op"); sys.exit(0)

# ---- Layer 1: handle_message — reject non-owner non-read tools ------------
ANCHOR_L1 = (
    "                # auto_approve_subagent_spawn \u2192 auto-approve spawn_run tool calls\n"
    "                if _should_auto_approve_spawn(context_builder, event):\n"
)
GATE_L1 = (
    "                # Set O (_kc_member_readonly): a NON-OWNER sender is read-only.\n"
    "                # Reject any tool not in the reviewed read-only safe set before\n"
    "                # any auto-approve or interactive path. The owner is unaffected.\n"
    "                # Lazy import of _is_heartbeat_safe_tool: a module-level import\n"
    "                # of slack.gateway here is a CIRCULAR import (gateway -> dashboard\n"
    "                # -> chat_runner -> slack.handler), which fails gateway startup.\n"
    "                if not is_owner(user_id):\n"
    "                    from kiro_crew.slack.gateway import (  # Set O lazy (avoid circular)\n"
    "                        _is_heartbeat_safe_tool as _kc_safe_tool,\n"
    "                    )\n"
    "                else:\n"
    "                    _kc_safe_tool = None\n"
    "                if _kc_safe_tool is not None and not _kc_safe_tool(event.title or \"\"):\n"
    "                    await _reject_orphaned_tool(client, event.request_id)\n"
    "                    sel().log_tool_invocation(\n"
    "                        session_key=session_key,\n"
    "                        source=\"slack\",\n"
    "                        tool_name=event.title,\n"
    "                        tool_kind=event.tool_kind,\n"
    "                        outcome=\"denied\",\n"
    "                        request_id=event.request_id,\n"
    "                        metadata={\"reason\": \"member_readonly (Set O)\", \"user_id\": user_id},\n"
    "                    )\n"
    "                    continue\n"
) + ANCHOR_L1
if s.count(ANCHOR_L1) != 1:
    print("Set O [L1]: handle_message anchor not unique — CHECK ANCHORS"); sys.exit(1)
s = s.replace(ANCHOR_L1, GATE_L1, 1)

# ---- (no module-level gateway import) -------------------------------------
# _is_heartbeat_safe_tool is imported LAZILY inside the L1 gate above, only when
# the sender is a non-owner. A module-level `from kiro_crew.slack.gateway import
# _is_heartbeat_safe_tool` is circular (gateway -> dashboard -> chat_runner ->
# slack.handler) and crashes gateway startup with ImportError. Do NOT add one.

# ---- Layer 2: handle_interaction — Approve/Trust require is_owner ----------
# The primary gate rejects non-allowed users; tighten the APPROVE/TRUST actions
# to owner-only. We insert an owner check right after the existing allow-list
# gate inside handle_interaction, keyed on the action id so reject_tool stays
# open to any allow-listed user.
ANCHOR_L2 = (
    "    # Deny-by-default: reject unless positively confirmed as allowed\n"
    "    if not user_id or not is_allowed_user(user_id):\n"
)
GATE_L2_EXTRA = (
    "    # Set O (_kc_member_readonly): Approve and Trust are owner-only. A\n"
    "    # non-owner allow-listed member may reject a tool but never approve one\n"
    "    # or widen a session to Trust (which would grant write/execute).\n"
    "    if action_id in (_ACTION_APPROVE, _ACTION_TRUST) and not is_owner(user_id):\n"
    "        logger.warning(\n"
    "            \"Set O: non-owner %s may not %s\", user_id, action_id\n"
    "        )\n"
    "        sel().log_api_access(\n"
    "            caller=user_id,\n"
    "            operation=\"slack.interactive.approval\",\n"
    "            outcome=\"denied\",\n"
    "            source=\"slack\",\n"
    "            resources=action_id,\n"
    "            error=\"non-owner approve/trust blocked (Set O)\",\n"
    "        )\n"
    "        return None\n"
)
# Find the END of the existing allow-list gate's block (its 'return None\n'),
# and insert the owner gate right after it so both run before any action logic.
idx = s.find(ANCHOR_L2)
if idx == -1 or s.count(ANCHOR_L2) != 1:
    print("Set O [L2]: handle_interaction allow-list anchor not unique — CHECK ANCHORS"); sys.exit(1)
# The allow-list gate closes with the first '        return None\n' after it.
close = s.find("        return None\n", idx)
if close == -1:
    print("Set O [L2]: could not find end of allow-list gate — CHECK ANCHORS"); sys.exit(1)
insert_at = close + len("        return None\n")
s = s[:insert_at] + "\n" + GATE_L2_EXTRA + s[insert_at:]

p.write_text(s)
print("Set O: OK (L1 handle_message + L2 handle_interaction + import)")
PY

if [ -n "$VENV_PY" ]; then
  "$VENV_PY" -m py_compile "$HD" && echo "Set O: compile OK" || { echo "Set O: compile FAILED"; exit 1; }
else
  python3 -m py_compile "$HD" && echo "Set O: compile OK (fallback python3)"
fi

# ---- prove (static): both layers present and shaped right ------------------
python3 - "$HD" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
assert "_kc_member_readonly" in s, "marker missing"
assert "_is_heartbeat_safe_tool as _kc_safe_tool" in s, "L1 lazy import missing"
assert '_kc_safe_tool is not None and not _kc_safe_tool(event.title or "")' in s, "L1 gate missing"
# must NOT have a module-level gateway import (circular)
assert "from kiro_crew.slack.gateway import _is_heartbeat_safe_tool  # Set O\n" not in s, \
    "module-level gateway import present — circular import risk"
assert "if action_id in (_ACTION_APPROVE, _ACTION_TRUST) and not is_owner(user_id):" in s, "L2 gate missing"
# L1 must sit before the first auto-approve in handle_message
i_hm = s.index("async def handle_message(")
i_l1 = s.index("Set O (_kc_member_readonly): a NON-OWNER sender", i_hm)
i_auto = s.index("if approval_mode == APPROVAL_AUTO:", i_hm)
assert i_hm < i_l1 < i_auto, "L1 not before auto-approve"
print("Set O: prove OK — L1 lazy-import gate before auto-approve, L2 owner-gate, no circular import")
PY
