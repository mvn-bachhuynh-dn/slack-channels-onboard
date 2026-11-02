#!/usr/bin/env bash
# ============================================================================
# Set W — close a dashboard-run turn on its linked Slack thread (2026-10-29).
#
# Problem (0.10.0): a message posted in a Slack thread that is linked to a
# dashboard session is routed to the dashboard slot (inbound.py
# maybe_route_linked_thread) and runs through dashboard/chat_runner.py. That
# path mirrors the echo ("💬 _…_") and the answer to Slack, but at turn end it
# only tears down the plan stream -- and on an org-wide install the mirror's
# chat.startStream is rejected (missing_recipient_user_id), so there is no
# stream to tear down either. Nothing clears the assistant thread status and
# no "Finished in …" footer is posted, so the thread reads as still running
# where the native Slack path (renderer finish / finalize) closes it.
#
# Fix: in the turn-end finally of the dashboard runner, after the stream
# teardown, clear the thread status and post the same timing footer the native
# path posts. Same publication fence as the mirror's other Slack writes;
# best-effort, never raises.
#
# 0.11.0 moved the turn-end finally to dashboard/chat_turn/session_reset.py
# (_turn_release_session, one indent level shallower, on chat_runner's globals);
# the same edit is made there.
#
# Idempotent (marker _kc_mirror_turn_end_v1); no-ops when the installed runner
# already clears the mirror thread status. Rollback: restore
# dashboard/chat_runner.py.bak-setw-<stamp>, clear __pycache__, restart.
# ============================================================================
set -euo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set W: venv not found — skipping"; exit 0; }
STAMP=$(date +%Y%m%d-%H%M%S)
python3 - "$SITE" "$STAMP" <<'PY'
import pathlib, py_compile, shutil, sys
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
p = site / "dashboard/chat_runner.py"
_sr = site / "dashboard/chat_turn/session_reset.py"
if _sr.exists() and "stop_stream(_mirror_chan, _mirror_stream_ts)" in _sr.read_text():
    p = _sr  # 0.11.0 layout
s = p.read_text()
if "_kc_mirror_turn_end_v1" in s:
    print("Set W (mirror turn end): already applied — no-op"); sys.exit(0)
if "set_thread_status(_mirror_chan" in s:
    print("Set W (mirror turn end): fixed upstream in installed release — no-op"); sys.exit(0)
A = (
    "                try:\n"
    "                    await state.slack_client.stop_stream(_mirror_chan, _mirror_stream_ts)\n"
    "                except Exception:\n"
    "                    logger.debug(\"Stream cleanup failed\", exc_info=True)\n"
)
_ded = lambda t: "\n".join(l[4:] if l.startswith("    ") else l for l in t.split("\n"))
SPLIT = p.name == "session_reset.py"
if SPLIT:
    A = _ded(A)
if s.count(A) != 1:
    print("Set W: stream-teardown anchor not unique — CHECK ANCHORS"); sys.exit(1)
shutil.copy2(p, p.with_name(p.name + f".bak-setw-{stamp}"))
INS = (
    "            # Set W (_kc_mirror_turn_end_v1): close the turn on the linked Slack\n"
    "            # thread the way the native path does -- clear the thread status and\n"
    "            # post the timing footer -- or the thread reads as still running.\n"
    "            if _mirror_chan and _mirror_thread and state.slack_client:\n"
    "                try:\n"
    "                    await state.slack_client.set_thread_status(_mirror_chan, _mirror_thread, \"\")\n"
    "                    if not cross_surface_withheld(state, slot) and not slack_publication_withheld(\n"
    "                        state, slot, _mirror_chan, _mirror_thread\n"
    "                    ):\n"
    "                        from kiro_crew.slack.handler_runtime.finalize import build_timing_footer\n"
    "\n"
    "                        _kc_t0 = getattr(turn, \"_turn_t0\", 0.0) or 0.0\n"
    "                        _kc_blocks, _kc_text = build_timing_footer(\n"
    "                            (time.monotonic() - _kc_t0) if _kc_t0 else 0.0, None\n"
    "                        )\n"
    "                        await state.slack_client.post_blocks(\n"
    "                            _mirror_chan, _kc_blocks, _kc_text, thread_ts=_mirror_thread\n"
    "                        )\n"
    "                except Exception:\n"
    "                    logger.debug(\"Mirror turn-end close failed\", exc_info=True)\n"
)
if SPLIT:
    INS = _ded(INS).replace(
        "                    from kiro_crew.slack.handler_runtime.finalize import build_timing_footer\n",
        "                    import time\n\n"
        "                    from kiro_crew.slack.handler_runtime.finalize import build_timing_footer\n",
    )
s = s.replace(A, A + INS, 1)
p.write_text(s)
try:
    py_compile.compile(str(p), doraise=True)
except py_compile.PyCompileError:
    shutil.copy2(p.with_name(p.name + f".bak-setw-{stamp}"), p)
    print("Set W: compile FAILED — restored the backup"); raise
for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
    pyc.unlink()
print(f"Set W (mirror turn end): patched {p.relative_to(site)}")
PY
