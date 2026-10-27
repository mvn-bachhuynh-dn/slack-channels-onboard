#!/usr/bin/env bash
# ============================================================================
# Set O2 — member read-only on the TRANSPORT path (the path messages really take).
#
# WHY O2 (Set O was dead code): messaging.use_transport=True routes every Slack
# turn through transport_dispatch -> messaging/driver.TurnDriver, never through
# handler.handle_message's tool loop where Set O L1 lived. TurnDriver already
# runs a `tool_gate(event)` BEFORE its auto/trust/YOLO ladder, and a "deny" from
# it is un-overridable. Set O2 wraps transport_dispatch's _tool_gate: when the
# turn's sender is NOT the owner, any tool outside the read-only allow set is
# denied. Owner turns are unchanged. The original PreToolUse gate (sensitive
# paths, governance ceiling, deny-list) still runs for allowed member tools.
#
# Member allow set (identity from adapter-authored fields, never the
# model-authored title):
#   * ACP tool_kind in {read, search, think} and not is_shell
#     (claude-agent-acp: Read/Grep/Glob/LS -> read/search; Edit/Write -> edit;
#      Bash -> execute; WebFetch -> fetch — the latter three are denied)
#   * a trusted MCP identity whose tool_name is in gateway.HEARTBEAT_SAFE_TOOLS
#     (local_knowledge_search, cron_list, spawn_list/status, artifact_* ...)
# Everything else (edit, delete, move, execute, fetch, other, send_message,
# spawn_run, cron_add, ...) is denied for a non-owner.
#
# Imports of slack.handler/slack.gateway are LAZY (inside the function): a
# module-level import of slack.gateway from a slack module is circular and took
# the gateway down once (2026-10-16). Idempotent via _kc_member_readonly_v2.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set O2: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
TD="$SITE/slack/transport_dispatch.py"
[ -f "$TD" ] || { echo "Set O2: $TD not found — layout changed"; exit 1; }

python3 - "$TD" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
if "_kc_member_readonly_v2" in s:
    print("Set O2: already applied — no-op"); sys.exit(0)

ANCHOR = (
    "        def _tool_gate(event: Any) -> str:\n"
    "            if context_builder is None:\n"
    "                return \"\"\n"
)
NEW = (
    "        def _tool_gate(event: Any) -> str:\n"
    "            # Set O2 (_kc_member_readonly_v2): a non-owner sender is read-only.\n"
    "            from kiro_crew.slack.handler import is_owner as _kc_is_owner\n"
    "\n"
    "            if not _kc_is_owner(user_id) and not _kc_member_tool_allowed(event):\n"
    "                sel().log_api_access(\n"
    "                    caller=user_id,\n"
    "                    operation=\"slack.member_readonly\",\n"
    "                    outcome=\"denied\",\n"
    "                    source=\"slack\",\n"
    "                    resources=(\n"
    "                        f\"kind={getattr(event, 'tool_kind', '')} \"\n"
    "                        f\"tool={getattr(event, 'tool_name', '')}\"\n"
    "                    ),\n"
    "                    error=\"non-owner write/execute blocked (Set O2)\",\n"
    "                )\n"
    "                return \"deny\"\n"
    "            if context_builder is None:\n"
    "                return \"\"\n"
)
if s.count(ANCHOR) != 1:
    print("Set O2: _tool_gate anchor not unique — CHECK ANCHORS"); sys.exit(1)
s = s.replace(ANCHOR, NEW, 1)

if "from kiro_crew.sel import sel\n" not in s:
    print("Set O2: sel() not imported in transport_dispatch — CHECK"); sys.exit(1)

s = s.rstrip("\n") + "\n\n\n" + (
    "# Set O2 (_kc_member_readonly_v2): read-only allow set for a non-owner sender.\n"
    "_KC_MEMBER_READ_KINDS = frozenset({\"read\", \"search\", \"think\"})\n"
    "\n"
    "\n"
    "def _kc_member_tool_allowed(event: Any) -> bool:\n"
    "    \"\"\"True when a NON-owner may run this tool (read-only allow set).\n"
    "\n"
    "    Keys on adapter-authored identity (``tool_kind``, ``is_shell``,\n"
    "    ``tool_name`` + ``mcp_identity_trusted``), never on the model-authored\n"
    "    ``title``. Deny by default.\n"
    "    \"\"\"\n"
    "    if getattr(event, \"is_shell\", False):\n"
    "        return False\n"
    "    if (getattr(event, \"tool_kind\", \"\") or \"\").lower() in _KC_MEMBER_READ_KINDS:\n"
    "        return True\n"
    "    name = getattr(event, \"tool_name\", \"\") or \"\"\n"
    "    if name and (\n"
    "        getattr(event, \"mcp_identity_trusted\", False)\n"
    "        or getattr(event, \"tool_identity_trusted\", False)\n"
    "    ):\n"
    "        try:\n"
    "            from kiro_crew.slack.gateway import HEARTBEAT_SAFE_TOOLS as _kc_safe\n"
    "        except ImportError:  # 0.10.0+: identity-based (@server/tool) check upstream\n"
    "            from kiro_crew.slack.gateway_runtime.tool_policy import _is_heartbeat_safe_tool as _kc_hb\n"
    "\n"
    "            return _kc_hb(event)\n"
    "        return name in _kc_safe\n"
    "    return False\n"
)
p.write_text(s)
print("Set O2 [transport_dispatch.py]: OK")
PY
rc=$?; [ $rc -eq 0 ] || exit $rc

PYBIN="${VENV_PY:-python3}"
"$PYBIN" -m py_compile "$TD" && echo "Set O2: compile OK" || { echo "Set O2: compile FAILED"; exit 1; }
# Exit status, not grep: under pipefail the old "| grep && fail || ok" printed OK on a failed import.
if _kc_out=$("$PYBIN" -c "import kiro_crew.slack.gateway, kiro_crew.slack.transport_dispatch" 2>&1); then
  echo "Set O2: import OK"
else
  echo "$_kc_out" | tail -3; echo "Set O2: IMPORT FAILED — do not restart"; exit 1
fi
