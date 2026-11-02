#!/usr/bin/env bash
# ============================================================================
# Set Z — upload local images in a dashboard-mirrored Slack answer (2026-11-01).
#
# Problem (0.11.0): a message in a Slack thread linked to a dashboard session
# runs through the dashboard runner, and its answer is mirrored to the thread
# by dashboard/chat_turn/turn_spec_hooks.py as plain text (render_for_slack +
# post_message). The native Slack renderer cuts every local ![alt](/path.png)
# out of the reply and uploads it (extract_outbound_with_audit +
# upload_outbound_files_reporting); the mirror never does, so screenshots show
# up as raw "![...](/path/to/shot.png)" text. Whether a thread is linked decides
# which path runs, which is why images "sometimes" work.
#
# The mirror reads the PERSISTED reply rows, whose image refs history has
# already rewritten to the session's own copies under
# <data home>/sessions/<stem>.attachments/. The data home is a sensitive path,
# so the shared seal refuses those copies; they are admitted here only when
# they sit directly in THIS session's attachments dir (gateway-made copies of
# images this session's reply showed), are regular non-link files, at most
# 10 MiB, and sniff as a raster image. Every other ref goes through the same
# seal as the native path (session cwd + $KIROCREW_SCRATCH).
#
# Idempotent (marker _kc_mirror_images_v1); no-ops when the installed mirror
# already uploads files. Rollback: restore
# dashboard/chat_turn/turn_spec_hooks.py.bak-setz-<stamp> (0.10.0:
# dashboard/chat_runner.py.bak-setz-<stamp>), clear __pycache__,
# restart.
# ============================================================================
set -euo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set Z: venv not found — skipping"; exit 0; }
STAMP=$(date +%Y%m%d-%H%M%S)
python3 - "$SITE" "$STAMP" <<'PY'
import pathlib, py_compile, shutil, sys
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
# 0.11.0 moved the mirror into dashboard/chat_turn/turn_spec_hooks.py (a `turn`
# object in scope); on 0.10.0 it sits in dashboard/chat_runner.py._run_chat one
# indent level deeper, with session_key / _mirror_thread / client as locals.
p = site / "dashboard/chat_turn/turn_spec_hooks.py"
TURN = "turn"
IND = ""
if not p.exists() or "render_for_slack(_mirror_body)" not in p.read_text():
    p = site / "dashboard/chat_runner.py"
    # __import__, not `import types`: an import statement would make `types` a
    # local of the whole of _run_chat.
    TURN = '__import__("types").SimpleNamespace(session_key=session_key, _mirror_thread=_mirror_thread, client=client)'
    IND = "    "
s = p.read_text()
if "_kc_mirror_images_v1" in s:
    print("Set Z (mirror images): already applied — no-op"); sys.exit(0)
A = (
    IND + "            for _part in render_for_slack(_mirror_body):\n"
    + IND + "                await state.slack_client.post_message(_mirror_chan, _part, _mirror_thread)\n"
)
if s.count(A) != 1:
    i = s.find("render_for_slack(_mirror_body)")
    if i != -1 and "upload_outbound_files" in s[i:i + 1500]:
        print("Set Z (mirror images): fixed upstream in installed release — no-op"); sys.exit(0)
    print("Set Z: mirror post anchor not unique — CHECK ANCHORS"); sys.exit(1)
B = (
    "            # Set Z (_kc_mirror_images_v1): upload local images like the native\n"
    "            # renderer does, instead of posting their markup as text.\n"
    "            _kc_files: list = []\n"
    "            try:\n"
    "                _mirror_body, _kc_files = await _kc_mirror_images(turn, _mirror_body)\n"
    "            except Exception:\n"
    "                logger.debug(\"Mirror image extraction failed\", exc_info=True)\n"
    "            if _mirror_body.strip():\n"
    "                for _part in render_for_slack(_mirror_body):\n"
    "                    await state.slack_client.post_message(_mirror_chan, _part, _mirror_thread)\n"
    "            if _kc_files:\n"
    "                from kiro_crew.slack.files import upload_outbound_files_reporting\n"
    "\n"
    "                await upload_outbound_files_reporting(\n"
    "                    state.slack_client, _mirror_chan, _mirror_thread, _kc_files\n"
    "                )\n"
).replace("_kc_mirror_images(turn,", "_kc_mirror_images(" + TURN + ",")
B = "".join(IND + l if l.strip() else l for l in B.splitlines(True))
shutil.copy2(p, p.with_name(p.name + f".bak-setz-{stamp}"))
s = s.replace(A, B, 1)
s = s.rstrip("\n") + '''


_KC_MIRROR_IMAGE_MAX = 10 * 1024 * 1024


def _kc_read_session_copy(path: "pathlib.Path", own_dirs: set) -> "tuple[bytes, str] | None":
    """Set Z: bytes and mime of a gateway-made copy in this session's attachments dir."""
    import os
    import stat

    from kiro_crew.messaging.attachments import sniff_raster_mime

    if str(path.parent) not in own_dirs:
        return None
    try:
        fd = os.open(str(path), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > _KC_MIRROR_IMAGE_MAX:
            return None
        chunks, left = [], st.st_size + 1
        while left > 0:
            chunk = os.read(fd, min(left, 1 << 20))
            if not chunk:
                break
            chunks.append(chunk)
            left -= len(chunk)
        data = b"".join(chunks)
    finally:
        os.close(fd)
    if len(data) > _KC_MIRROR_IMAGE_MAX:
        return None
    mime = sniff_raster_mime(data[:64])
    return (data, mime) if mime else None


def _kc_mirror_image_scan(text: str, own_dirs: set) -> "tuple[str, list]":
    """Set Z: cut this session's own attachment copies out of *text* (blocking)."""
    import pathlib

    from kiro_crew.messaging.outbound_files import OutboundFile, iter_local_refs, local_destination

    files: list = []
    out, pos = [], 0
    for ref in iter_local_refs(text):
        dest = local_destination(ref.dest)
        if dest is None:
            continue
        got = _kc_read_session_copy(pathlib.Path(dest), own_dirs)
        if got is None:
            continue
        files.append(OutboundFile(path=str(dest), data=got[0], alt=ref.alt, mime=got[1]))
        out.append(text[pos : ref.start])
        pos = ref.end
    out.append(text[pos:])
    return "".join(out), files


async def _kc_mirror_images(turn: Any, text: str) -> "tuple[str, list]":
    """Set Z (_kc_mirror_images_v1): split a mirrored answer into text + images.

    The session's own attachment copies are admitted here; every other local
    ref goes through the shared Slack seal with the session's cwd and scratch.
    """
    import os
    import pathlib

    from kiro_crew.slack.files import extract_outbound_with_audit

    if "![" not in text:
        return text, []
    home = os.environ.get("KIROCREW_HOME") or str(pathlib.Path.home() / ".kiro" / "crew")
    sessions = pathlib.Path(home) / "sessions"
    key = str(getattr(turn, "session_key", "") or "")
    own_dirs = set()
    if key:
        own_dirs.add(str(sessions / (key.replace(":", "_") + ".attachments")))
    thread = str(getattr(turn, "_mirror_thread", "") or "")
    if thread:
        own_dirs.add(str(sessions / ("slack_" + thread + ".attachments")))
    text, files = await asyncio.to_thread(_kc_mirror_image_scan, text, own_dirs)
    client = getattr(turn, "client", None)
    cwd = getattr(client, "cwd", "") or ""
    if isinstance(cwd, str) and os.path.isabs(cwd):
        body, more, _notes = await extract_outbound_with_audit(
            text,
            within_root=cwd,
            scratch_root=str(getattr(client, "work_scratch_dir", None) or ""),
            audit_caller=key or "dashboard-mirror",
        )
        text, files = body, files + list(more)
    return text.strip(), files
'''
p.write_text(s)
try:
    py_compile.compile(str(p), doraise=True)
except py_compile.PyCompileError:
    shutil.copy2(p.with_name(p.name + f".bak-setz-{stamp}"), p)
    print("Set Z: compile FAILED — restored the backup"); raise
for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
    pyc.unlink()
print(f"Set Z (mirror images): patched {p.relative_to(site)}")
PY
