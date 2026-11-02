#!/usr/bin/env bash
# ============================================================================
# Set X — resolve an agent RECORD name to its template for member essentials
# (2026-10-31).
#
# Problem (0.10.0, still on main; upstream issue kirodotdev/KiroCrew#25187):
# the Slack transport path hands context_builder.build_message the agent
# record name (agent="my-crew"), and build_message passes it on as
# execution_template. In a thread linked to a dashboard session of a crewmate
# the essentials are built, and documents_for_member("my-crew") raises
# MemberEssentialContextError("Essential template 'my-crew': not found")
# because the record's template is its kiro_agent ("kirocrew") and no
# ~/.kiro/agents/my-crew.json exists. Every message in the thread then fails
# with "Something went wrong (transport path)". Each auto-onboarded channel
# (record name != kiro_agent) can hit it.
#
# Fix: in context.py, when the name has no spec file of its own and is an
# `agents` record with a kiro_agent, use that kiro_agent as execution_template.
# A name that has its own spec file is left alone, so the per-record
# workaround files (~/.kiro/agents/<record>.json) keep working until removed.
#
# 0.11.0 moved build_message's body to context_assembly/turn_message.py (the
# call site at 12-space indent); the same edit and helper go there.
#
# Idempotent (marker _kc_exec_template_v1); no-ops when the installed
# build_message no longer passes `agent or "kirocrew"` (upstream changed it).
# Rollback: restore context.py.bak-setx-<stamp>, clear __pycache__, restart.
# ============================================================================
set -euo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set X: venv not found — skipping"; exit 0; }
STAMP=$(date +%Y%m%d-%H%M%S)
python3 - "$SITE" "$STAMP" <<'PY'
import pathlib, py_compile, shutil, sys
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
# 0.11.0 moved the call site into context_assembly/turn_message.py.
p = site / "context.py"
A = '                execution_template=agent or "kirocrew",\n'
_tm = site / "context_assembly/turn_message.py"
if _tm.exists() and ("_kc_exec_template_v1" in _tm.read_text()
                     or 'execution_template=agent or "kirocrew",' in _tm.read_text()):
    p, A = _tm, A[4:]
s = p.read_text()
if "_kc_exec_template_v1" in s:
    print("Set X (essential template): already applied — no-op"); sys.exit(0)
if s.count(A) == 0:
    print("Set X (essential template): call site changed upstream — no-op (check #25187)"); sys.exit(0)
if s.count(A) != 1:
    print("Set X: execution_template anchor not unique — CHECK ANCHORS"); sys.exit(1)
shutil.copy2(p, p.with_name(p.name + f".bak-setx-{stamp}"))
s = s.replace(A, A.replace('agent or "kirocrew"', "_kc_exec_template(agent)"), 1)
s = s.rstrip("\n") + '''


def _kc_exec_template(agent: str | None) -> str:
    """Set X (_kc_exec_template_v1): map an agent record name to its template.

    The Slack path passes the record name; essentials need a template name.
    A name with its own spec file is kept as is.
    """
    name = agent or "kirocrew"
    try:
        from kiro_crew.member_essential_context import resolve_template_path

        if resolve_template_path(name):
            return name
    except Exception:
        pass
    try:
        from kiro_crew.config import KiroCrewConfig

        record = (getattr(KiroCrewConfig.load(), "agents", None) or {}).get(name)
        kiro_agent = getattr(record, "kiro_agent", None)
        if isinstance(kiro_agent, str) and kiro_agent:
            return kiro_agent
    except Exception:
        pass
    return name
'''
p.write_text(s)
py_compile.compile(str(p), doraise=True)
for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
    pyc.unlink()
print(f"Set X (essential template): patched {p.relative_to(site)}")
PY
