#!/usr/bin/env bash
# ============================================================================
# Set V — release the stream redactor's held tail BEFORE a tool card (2026-10-28).
#
# Problem (0.10.0, still on main): messaging/driver.py feeds every text chunk
# through StreamRedactor, which holds back the trailing run of the stream in
# case it is the first half of a credential. At EVENT_TOOL_CALL the driver
# dispatches the tool card WITHOUT flushing that hold, so the held characters
# are released only with the first text AFTER the tool, on the far side of the
# card. In Slack that reads "…mã hóa đơ" [card] "n.Trang Ringi…": a word torn
# in two and glued to the next sentence. The Slack renderer already flushes its
# own buffers final at a tool boundary for exactly this reason; the driver's
# redactor sits upstream of it and was missed.
#
# Upstream: issue kirodotdev/KiroCrew#21597, closed by #21758 (on main, not in
# 0.10.0), which only inserts a paragraph break after the held tail -- the
# tail still lands after the card. This Set flushes it before the card.
#
# Fix: await flush_redactor() at the top of the EVENT_TOOL_CALL branch. The
# flush still runs the redactor over the held text, so a credential held whole
# is redacted; only a key the tool call itself cuts in two would pass, and a
# model does not emit a tool call mid-token.
#
# Idempotent (marker _kc_tool_flush_v1); no-ops when the installed driver
# already flushes the redactor in the tool-call branch. Rollback: restore
# messaging/driver.py.bak-setv-<stamp>, clear __pycache__, restart.
# ============================================================================
set -euo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set V: venv not found — skipping"; exit 0; }
STAMP=$(date +%Y%m%d-%H%M%S)
python3 - "$SITE" "$STAMP" <<'PY'
import pathlib, py_compile, shutil, sys
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
p = site / "messaging/driver.py"
s = p.read_text()
if "_kc_tool_flush_v1" in s:
    print("Set V (tool-boundary flush): already applied — no-op"); sys.exit(0)
A = "            elif kind == EVENT_TOOL_CALL:\n                productive = True\n"
i = s.find("            elif kind == EVENT_TOOL_CALL:\n")
j = s.find("\n            elif kind == ", i + 1)
if i != -1 and j != -1 and "await flush_redactor()" in s[i:j]:
    print("Set V (tool-boundary flush): fixed upstream in installed release — no-op"); sys.exit(0)
if s.count(A) != 1:
    print("Set V: tool-call anchor not unique — CHECK ANCHORS"); sys.exit(1)
shutil.copy2(p, p.with_name(p.name + f".bak-setv-{stamp}"))
s = s.replace(A, A + (
    "                # Set V (_kc_tool_flush_v1): release the redactor's held tail before\n"
    "                # the tool card, or it lands after the card and tears the last word\n"
    "                # (\"đơ\" [card] \"n.Next\"). The flush still redacts what it releases.\n"
    "                await flush_redactor()\n"
), 1)
p.write_text(s)
py_compile.compile(str(p), doraise=True)
for pyc in (p.parent / "__pycache__").glob("driver.*.pyc"):
    pyc.unlink()
print("Set V (tool-boundary flush): patched messaging/driver.py")
PY
