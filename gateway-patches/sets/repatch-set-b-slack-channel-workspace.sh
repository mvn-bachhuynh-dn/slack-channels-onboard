#!/usr/bin/env bash
# ============================================================================
# Set B — route a Slack channel's agent ALIAS to its kiro agent + workspace.
#
# slack.channels.<id>.agent names a Kiro Crew agent record (agents.<name>), which
# carries a kiro_agent (the kiro-cli mode) and a workspace. On the Slack CHAT
# path (slack/transport_dispatch.py and the native turn in slack/handler.py)
# 0.9.0 passes that alias straight to sessions.get_or_create as the kiro agent
# and gives no cwd, so the session asks kiro-cli for a mode named after the
# alias and runs in a per-session scratch directory instead of the agent's
# workspace. The dashboard, cron (since #13422) and spawn paths already resolve
# the alias through resolve_agent_bindings; the Slack chat path does not.
#
# Fix: a helper _agent_workspace_binding(alias) -> (kiro_agent, cwd) resolved
# from the live config, and both get_or_create call sites pass the kiro agent
# and cwd=<workspace dir>. A name that is not an alias passes through unchanged.
#
# Upstream: kirodotdev/KiroCrew#22763, fixed by #22858 (merged after 0.9.0); the
# script no-ops on a release that carries resolve_channel_crew.
#
# Idempotent (markers: _agent_workspace_binding, _dispatch_agent). Anchors are
# checked; a mismatch prints CHECK ANCHORS and exits 1. Rollback: restore the
# *.bak-setb-<stamp> files, clear __pycache__, restart.
# ============================================================================
set -euo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set B: venv not found — skipping"; exit 0; }
STAMP=$(date +%Y%m%d-%H%M%S)

python3 - "$SITE" "$STAMP" <<'PY'
import re, shutil, sys, pathlib
site = pathlib.Path(sys.argv[1])
stamp = sys.argv[2]
# Upstream fixed this in kirodotdev/KiroCrew#22858 (merged after 0.9.0): the
# chat paths resolve the channel's crew through slack/channel_crew.py. On a
# release that carries it this Set is redundant and its anchors may be gone.
if "resolve_channel_crew" in (site / "slack/transport_dispatch.py").read_text():
    print("Set B (slack channel workspace): fixed upstream (#22858) in installed release — no-op")
    sys.exit(0)
for _f in ("slack/transport_dispatch.py", "slack/handler.py"):
    _p = site / _f
    _b = _p.with_name(_p.name + f".bak-setb-{stamp}")
    if "_dispatch_agent = _kiro_agent or _agent" not in _p.read_text():
        shutil.copy2(_p, _b)

# ── Set B: Slack channel → agent workspace (patch 4) ──
_TD_HELPER = '''def _agent_workspace_binding(gateway, agent):
    """Resolve a KiroCrew agent alias to (kiro_agent, cwd); (None, None) on miss."""
    if not gateway or not agent:
        return None, None
    try:
        from kiro_crew.config.loader import default_project_dir, resolve_agent_bindings
        cfg = getattr(gateway, "_cfg", None)
        if cfg is None:
            return None, None
        bindings = resolve_agent_bindings(cfg, agent)
        kiro_agent = bindings.kiro_agent or None
        agent_cfg = (getattr(cfg, "agents", None) or {}).get(agent)
        ws_name = getattr(agent_cfg, "workspace", None)
        cwd = default_project_dir(ws_name) or None if ws_name else None
        return kiro_agent, cwd
    except Exception:
        return None, None


'''
# Set B: route the channel's agent ALIAS to its kiro agent + workspace cwd at the
# get_or_create call. Anchor is a regex so a release that adds kwargs to the call
# (0.9.0 added start_priority=...) still matches; verified below (fail loudly).
_GOC_RE = re.compile(
    r"(?P<i>[ ]+)client, is_new, resumed = await sessions\.get_or_create\(\n"
    r"(?P=i)    session_key, agent=_agent, channel_id=channel(?P<rest>[^\n]*)\n(?P=i)\)"
)


def _route(text, binding_call):
    def rep(m):
        i = m.group("i")
        return (
            f"{i}_kiro_agent, _cwd = {binding_call}\n"
            f"{i}_dispatch_agent = _kiro_agent or _agent\n"
            f"{i}client, is_new, resumed = await sessions.get_or_create(\n"
            f"{i}    session_key, agent=_dispatch_agent, channel_id=channel, cwd=_cwd{m.group('rest')}\n"
            f"{i})"
        )
    return _GOC_RE.subn(rep, text)


td = site / "slack/transport_dispatch.py"
t = td.read_text()
if "_agent_workspace_binding" not in t:
    t = t.replace(
        '_DEFAULT_KIROCREW_AGENT = "kirocrew"\n\n\n',
        '_DEFAULT_KIROCREW_AGENT = "kirocrew"\n\n\n' + _TD_HELPER,
        1,
    )
if "_dispatch_agent = _kiro_agent or _agent" not in t:
    t, _n = _route(t, "_agent_workspace_binding(gateway, _agent)")
td.write_text(t)

_H_HELPER = _TD_HELPER.replace(
    "def _agent_workspace_binding(gateway, agent):",
    "def _agent_workspace_binding(agent):",
).replace("    if not gateway or not agent:", "    if not agent:").replace(
    '        cfg = getattr(gateway, "_cfg", None)', "        cfg = get_orch_cfg()"
)
hd = site / "slack/handler.py"
h = hd.read_text()
if "def _agent_workspace_binding(agent)" not in h:
    # Module level in handler.py itself: from 0.9.0 the native turn runs as a
    # handler_runtime owner composed onto handler's globals, so the helper must
    # live in handler's namespace (get_orch_cfg is a handler name in every layout).
    h = h.rstrip("\n") + "\n\n\n# Set B: channel agent alias -> (kiro agent, workspace cwd).\n" + _H_HELPER.rstrip("\n") + "\n"
if "_dispatch_agent = _kiro_agent or _agent" not in h:
    h, _n = _route(h, "_agent_workspace_binding(_agent)")
hd.write_text(h)
ok_b = all("_dispatch_agent = _kiro_agent or _agent" in f.read_text() for f in (td, hd))
print("Set B (slack channel workspace):", "OK" if ok_b else "CHECK ANCHORS")
sys.exit(0 if ok_b else 1)
PY

PYBIN=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || command -v python3)
"$PYBIN" -m py_compile "$SITE/slack/transport_dispatch.py" "$SITE/slack/handler.py" && echo "Set B compile OK"
