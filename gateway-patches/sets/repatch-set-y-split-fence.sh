#!/usr/bin/env bash
# ============================================================================
# Set Y — keep a code block whole when a long Slack answer is split (2026-10-31).
#
# Problem (0.10.0, still on main): slack/format.py split_message cuts a long
# answer into several posts on the last newline before the limit, with no
# notion of ``` fences. A cut inside a code block leaves part 1 with an
# opening fence and no close, and part 2 with a close and no open, so Slack
# renders neither as code: diffs and YAML show up as raw unformatted text.
# render_for_slack (every mirrored and channel answer) uses split_message for
# the final split.
#
# Fix: when a part ends inside an open fence, close the fence at the end of
# that part and reopen it (same opener line) at the start of the next one.
# Room for the added fences is reserved, so every part stays within the limit.
#
# Idempotent (marker _kc_split_fence_v1); no-ops when the installed
# split_message already handles fences. Rollback: restore
# slack/format.py.bak-sety-<stamp>, clear __pycache__, restart.
# ============================================================================
set -euo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set Y: venv not found — skipping"; exit 0; }
STAMP=$(date +%Y%m%d-%H%M%S)
python3 - "$SITE" "$STAMP" <<'PY'
import pathlib, py_compile, shutil, sys
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
p = site / "slack/format.py"
s = p.read_text()
if "_kc_split_fence_v1" in s:
    print("Set Y (split fence): already applied — no-op"); sys.exit(0)
i = s.find("def split_message(")
j = s.find("\ndef ", i + 1)
if i == -1 or j == -1:
    print("Set Y: split_message not found — CHECK ANCHORS"); sys.exit(1)
if "```" in s[i:j] or "fence" in s[i:j]:
    print("Set Y (split fence): fixed upstream in installed release — no-op"); sys.exit(0)
A = (
    "        remainder = text[cut:].lstrip(\"\\n\")\n"
    "        if remainder:\n"
    "            parts.append(text[:cut] + CONTINUATION)\n"
    "        else:\n"
    "            parts.append(text[:cut])\n"
    "        text = remainder\n"
)
if s[i:j].count(A) != 1:
    print("Set Y: split_message body anchor not unique — CHECK ANCHORS"); sys.exit(1)
B = (
    "        remainder = text[cut:].lstrip(\"\\n\")\n"
    "        head = text[:cut]\n"
    "        # Set Y (_kc_split_fence_v1): a cut inside a ``` block closes it here and\n"
    "        # reopens it on the next part, or neither part renders as code.\n"
    "        opener = _kc_open_fence(head)\n"
    "        if opener is not None and remainder and limit > len(CONTINUATION) + 2 * len(opener) + 8:\n"
    "            room = chunk_limit - len(\"\\n```\")\n"
    "            if len(head) > room:\n"
    "                cut = text.rfind(\"\\n\", 0, room)\n"
    "                if cut <= 0:\n"
    "                    cut = room\n"
    "                remainder = text[cut:].lstrip(\"\\n\")\n"
    "                head = text[:cut]\n"
    "                opener = _kc_open_fence(head)\n"
    "            if opener is not None and remainder:\n"
    "                head = head.rstrip(\"\\n\") + \"\\n```\"\n"
    "                remainder = opener + \"\\n\" + remainder\n"
    "        if remainder:\n"
    "            parts.append(head + CONTINUATION)\n"
    "        else:\n"
    "            parts.append(head)\n"
    "        text = remainder\n"
)
shutil.copy2(p, p.with_name(p.name + f".bak-sety-{stamp}"))
body = s[i:j].replace(A, B, 1)
helper = '''

def _kc_open_fence(text: str) -> str | None:
    """Set Y (_kc_split_fence_v1): the opener line of a ``` block *text* leaves open."""
    opener = None
    for line in text.split("\\n"):
        stripped = line.strip()
        if stripped.startswith("```"):
            if opener is None:
                opener = stripped if stripped.count("```") == 1 else None
            else:
                opener = None
    return opener
'''
s = s[:i] + body + helper + s[j:]
p.write_text(s)
py_compile.compile(str(p), doraise=True)
for pyc in (p.parent / "__pycache__").glob("format.*.pyc"):
    pyc.unlink()
print("Set Y (split fence): patched slack/format.py")
PY
