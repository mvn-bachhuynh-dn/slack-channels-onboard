#!/usr/bin/env bash
# Apply the gateway patch sets this app's optional features rely on.
#
# Usage:
#   bash gateway-patches/apply.sh            # apply every set, in order
#   bash gateway-patches/apply.sh --list     # show the sets and exit
#   KC_SITE_OVERRIDE=/path/to/site-packages/kiro_crew bash gateway-patches/apply.sh
#
# Each set is idempotent (a marker makes a re-run a no-op), checks its anchors
# before writing (a mismatch stops with "CHECK ANCHORS" and writes nothing for
# that set), and keeps a *.bak-set<x>-<stamp> copy of every file it edits.
# Sets build on each other's anchors, so they run in this fixed order and the
# run stops at the first failure. Restart the gateway afterwards.
#
# Read gateway-patches/README.md first: these change who may use the bot on
# Slack and what the agent may do for them.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# Order matters: later sets anchor on text earlier sets wrote.
SETS=(
  k   # multi-user allowlist (members)
  l   # no Slack stream for a turn without a recipient user
  m   # DMs are owner-only
  o   # members are read-only
  m2  # DM owner-only, enforced in events
  o2  # member read-only on the transport path
  o3  # members cannot escalate through buttons, linked slots or slash commands
  p   # per-channel maintainer role
  p2  # maintainer approved commands
  p3  # maintainer file operations
  q   # open channels; non-owner reads scoped to the channel workspace
  q2  # Claude backend asks for reads
  r   # a maintainer's missing permission is asked of the owner in Slack
  r2  # rtk wrappers normalised; Claude asks for Bash too
  r3  # one approval per prompt for maintainers
  s   # KIROCREW_SLACK_TEAM_ID in the agent's environment
  t   # OS confinement (bwrap) for maintainer channels
  u   # per-agent ACP backend pin (agents.<name>.acp_backend)
)

if [ "${1:-}" = "--list" ]; then
  for s in "${SETS[@]}"; do ls "$HERE"/sets/repatch-set-"$s"-*.sh | xargs -n1 basename; done
  exit 0
fi

for s in "${SETS[@]}"; do
  script=$(ls "$HERE"/sets/repatch-set-"$s"-*.sh 2>/dev/null | head -1)
  [ -n "$script" ] || { echo "!! set $s: script missing"; exit 1; }
  echo ">>> $(basename "$script")"
  out=$(bash "$script" 2>&1); rc=$?
  printf '%s\n' "$out" | grep -vE "superseded default|deprecated field|^Config:"
  if [ $rc -ne 0 ] || printf '%s' "$out" | grep -q "CHECK ANCHORS"; then
    echo "!! set $s failed; later sets were not applied. Restore the .bak-set* files to undo the earlier ones."
    exit 1
  fi
done
echo
echo "All sets applied. Restart the gateway (e.g. 'kirocrew restart' or your service manager)."
