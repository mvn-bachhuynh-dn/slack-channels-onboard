#!/usr/bin/env bash
# ============================================================================
# Set M2 — Slack DM is OWNER-ONLY, enforced in events.py BEFORE routing.
#
# WHY M2 (Set M was dead code): with messaging.use_transport=True (the fork's
# default) every Slack message is routed slack/events.py -> transport_dispatch
# -> messaging/driver.py and NEVER reaches handler.handle_message, where Set M
# put its gate. Set M2 puts the same gate in events.py's message dispatcher,
# before the native/transport split, so it holds on BOTH paths and BOTH
# backends (kiro / claude).
#
# Gate: a DM channel (id starts with "D") from a non-owner, non-trusted-bot
# sender is dropped silently with a SEL audit row. Owner keeps DM access.
# Idempotent via the _kc_dm_owner_only_v2 marker. Anchor verified on 0.8.0.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set M2: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
EV="$SITE/slack/events.py"
[ -f "$EV" ] || { echo "Set M2: $EV not found — layout changed"; exit 1; }

python3 - "$EV" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
if "_kc_dm_owner_only_v2" in s:
    print("Set M2: already applied — no-op"); sys.exit(0)
ANCHOR = "    # ── Workspace routing cache for org-wide installs ──\n"
GATE = (
    "    # Set M2 (_kc_dm_owner_only_v2): a Direct Message is owner-only. Placed\n"
    "    # BEFORE the native/transport split so it holds on both paths (the old\n"
    "    # Set M gate in handler.handle_message is never reached when\n"
    "    # messaging.use_transport is on). Slack DM channel ids start with 'D'.\n"
    "    if channel.startswith(\"D\") and not from_trusted_bot and not is_owner(sender_id):\n"
    "        logger.info(\"Set M2: dropped non-owner DM from %s in %s\", sender_id, channel)\n"
    "        sel().log_api_access(\n"
    "            caller=sender_id,\n"
    "            operation=\"slack.dm_owner_only\",\n"
    "            outcome=\"denied\",\n"
    "            source=\"slack\",\n"
    "            resources=channel,\n"
    "            error=\"non-owner DM blocked (Set M2)\",\n"
    "        )\n"
    "        return\n"
    "\n"
) + ANCHOR
if s.count(ANCHOR) != 1:
    print("Set M2: anchor not unique — CHECK ANCHORS"); sys.exit(1)
p.write_text(s.replace(ANCHOR, GATE, 1))
print("Set M2 [events.py]: OK")
PY
rc=$?; [ $rc -eq 0 ] || exit $rc

PYBIN="${VENV_PY:-python3}"
"$PYBIN" -m py_compile "$EV" && echo "Set M2: compile OK" || { echo "Set M2: compile FAILED"; exit 1; }
# Import check: a broken import here takes the whole gateway down on restart.
# Exit status, not grep: under pipefail the old "| grep && fail || ok" printed OK on a failed import.
if _kc_out=$("$PYBIN" -c "import kiro_crew.slack.gateway, kiro_crew.slack.events" 2>&1); then
  echo "Set M2: import OK"
else
  echo "$_kc_out" | tail -3; echo "Set M2: IMPORT FAILED — do not restart"; exit 1
fi
