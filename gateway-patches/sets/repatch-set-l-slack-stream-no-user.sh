#!/usr/bin/env bash
# Set L — skip Slack chat.startStream when there is no recipient user.
#
# Upstream: kirodotdev/KiroCrew issue #14625 + PR #14626 (OPEN). Until an
# upstream fix ships in the installed release, this re-applies the fix in place
# on the pipx venv after each `kirocrew update`. Idempotent via the
# _kc_skip_stream marker; also no-ops if upstream lands an equivalent
# `if not user_id: return None` guard in start_stream (detected below).
#
# Problem (observed on 0.7.1): Slack's chat.startStream REQUIRES
# recipient_user_id. Automated turns with no originating Slack user —
# subagent runs and cron jobs that stream into a channel — call start_stream
# with user_id="" . Slack rejects every one with
#   {'ok': False, 'error': 'missing_recipient_user_id'}
# and slack/client.py::start_stream catches it, logs a FULL traceback at
# WARNING (exc_info=True), returns None, and demotes to the non-streaming
# chat.update surface. The reply still lands (the demote path is complete), but
# each such turn spams a multi-line traceback — 66 in two days on this host,
# all from cron:/Subagent contexts, none from a real user session.
#
# Fix: when user_id is empty, return None immediately at the top of
# start_stream instead of issuing an API call that is guaranteed to 400. The
# outcome is identical (None -> caller demotes to chat.update), minus the
# doomed round-trip and the traceback. A real user turn always carries a
# user_id, so streaming for interactive chat is unaffected.
set -euo pipefail

SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
if [ -z "$SITE" ]; then
  echo "Set L: installed kirocrew venv not found — skipping"
  exit 0
fi

python3 - "$SITE" <<'PY'
import sys, pathlib
site = pathlib.Path(sys.argv[1])
c = site / "slack/client.py"
src = c.read_text()

if "_kc_skip_stream" in src:
    print("Set L (slack stream no-user): already applied — no-op")
    sys.exit(0)

# If upstream (#14626) lands its own recipient-user guard in start_stream, this
# Set is redundant and its pre-fix anchor may differ. Detect an equivalent
# early-return guard near the start_stream docstring and no-op cleanly rather
# than fail post-update.sh.
import re as _re
_ss = src.find("Start a streaming message via chat.startStream")
if _ss != -1 and _re.search(r"if not user_id:\s*\n\s*return None", src[_ss : _ss + 1200]):
    print("Set L (slack stream no-user): fixed upstream in installed release — no-op")
    sys.exit(0)

anchor = (
    '        """Start a streaming message via chat.startStream with task plan mode."""\n'
    "        try:\n"
)
add = (
    '        """Start a streaming message via chat.startStream with task plan mode."""\n'
    "        # _kc_skip_stream: chat.startStream REQUIRES recipient_user_id. A turn\n"
    "        # with no originating Slack user (subagent / cron streaming into a\n"
    "        # channel) would 400 with missing_recipient_user_id, so skip the doomed\n"
    "        # call and let the caller demote to chat.update — same outcome, no\n"
    "        # traceback. A real user turn always carries a user_id.\n"
    "        if not user_id:\n"
    "            return None\n"
    "        try:\n"
)
if src.count(anchor) != 1:
    print("Set L: start_stream anchor not unique — CHECK ANCHORS")
    sys.exit(1)
src = src.replace(anchor, add, 1)
c.write_text(src)
print("Set L (slack stream no-user):", "OK" if "_kc_skip_stream" in c.read_text() else "CHECK ANCHORS")
PY

VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python 2>/dev/null || true)
if [ -n "$VENV_PY" ]; then
  "$VENV_PY" -m py_compile "$SITE/slack/client.py" && echo "Set L compile OK"
else
  python3 -m py_compile "$SITE/slack/client.py" && echo "Set L compile OK (fallback python3)"
fi
