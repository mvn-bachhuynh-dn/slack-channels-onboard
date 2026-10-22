#!/usr/bin/env bash
# ============================================================================
# Set Q2 — make the Claude backend ASK for Read/Grep/Glob (2026-10-20).
#
# Why: Set Q (B) scopes non-owner reads in Crew's PreToolUse gate, but Claude
# Code auto-allows read-only tools inside the session cwd WITHOUT sending
# session/request_permission — so on agent.acp_backend=claude those reads never
# reach the gate (verified: a Read inside cwd ran with no permission request;
# with permissions.ask ["Read"] the same call is routed to the permission path).
#
# Fix: the settings.local.json seed Crew writes per claude session
# (acp/client.py, next to permissions.defaultMode / deny) also carries
#   "ask": ["Glob", "Grep", "Read"]
# Every read then goes through Crew's gate: the owner's reads are still
# auto-approved by the hook (reads are TOOL_AUTO_APPROVE), non-owner reads are
# scoped by Set Q. Cost: one permission round-trip per read.
#
# Caveat: Crew does NOT seed a settings.local.json it did not write (it logs
# "already exists; leaving it as the authoritative project settings"). Such a
# file keeps the auto-allow. This script only REPORTS those paths; fix them by
# hand (rename the file so Crew seeds it, or add the ask rule yourself).
#
# Idempotent via marker _kc_claude_ask_reads_v1.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set Q2: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_claude_ask_reads_v1"
p = site / "acp/client.py"
s = p.read_text()
if MARK in s:
    print("Set Q2: already applied — no-op")
else:
    OLD = "        if perms:\n            data[\"permissions\"] = perms\n"
    NEW = (
        f"        # Set Q2 ({MARK}): read-only tools must reach Crew's gate (Set Q scopes non-owner reads).\n"
        "        perms[\"ask\"] = sorted(set(perms.get(\"ask\") or []) | {\"Read\", \"Grep\", \"Glob\"})\n"
        + OLD
    )
    if s.count(OLD) != 1:
        print(f"Set Q2: FAIL anchor count={s.count(OLD)} — re-derive"); sys.exit(1)
    s = s.replace(OLD, NEW)
    shutil.copy2(p, p.with_name(p.name + f".bak-setq2-{stamp}"))
    p.write_text(s)
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()
    print("Set Q2: patched acp/client.py")
import importlib, inspect
C = importlib.import_module("kiro_crew.acp.client")
assert MARK in inspect.getsource(C)
print("Set Q2: OK")
PY
echo "Set Q2: settings.local.json files Crew refused to seed (keep auto-allowing reads) in the last 2 days:"
journalctl -u kirocrew --since "-2d" --no-pager 2>/dev/null \
  | grep -oE "/[^ ]+/\.claude/settings\.local\.json already exists" | sed 's/ already exists//' | sort -u \
  | while read -r f; do
      [ -f "$f" ] || continue
      if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); a=set((d.get('permissions') or {}).get('ask') or []); sys.exit(0 if {'Read','Grep','Glob'}<=a else 1)" "$f" 2>/dev/null; then
        echo "   ok   $f (has the ask rule)"
      else
        echo "   WARN $f — no ask rule; rename it so Crew seeds it, or add permissions.ask"
      fi
    done || true  # advisory only: no gateway journal (fresh host, CI) is not a failure
