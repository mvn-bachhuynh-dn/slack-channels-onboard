#!/usr/bin/env bash
# ============================================================================
# Set T — per-channel OS confinement for maintainer channels (2026-10-20).
#
# Goal: a channel MAINTAINER (channel-roles.json "maintainers") can do anything
# inside the channel's workspace without the owner approving each command, and
# can never reach another workspace or the owner's secrets.
#
# How: every agent process spawned for such a channel runs under bwrap
# (kiro_crew/_kc_confine.py, source: patch-src/kc_confine.py): read-only root
# FS, /home replaced by a private per-workspace home + read-only toolchain
# allowlist, workspace + scratch read-write, docker/lxd/dbus/snapd sockets and
# /run/user, /var/log masked, private /tmp + PID/IPC namespaces, no_new_privs.
# The Slack tool gate then auto-approves a maintainer's built-in tools in that
# session ONLY when the live process is verifiably confined to that channel's
# workspace (host._kc_confined). Unconfined → the old strict gate (O2/P/R…).
# MCP tools for maintainers always go through the old gate.
#
# Per-channel switch in channel-roles.json: "confine": false disables it for a
# channel that has maintainers; "confine": true forces it without maintainers.
#
# Edits (marker _kc_workspace_confine_v1, idempotent, anchor-checked):
#   - kiro_crew/_kc_confine.py           (new module, copied every run)
#   - acp/launch.py                      wrap argv after the Crew sandbox wrap
#   - slack/transport_dispatch.py        maintainer fast-path in _tool_gate
#   - providers/acp.py                   pin channel on the kiro-cli/KAS AcpRuntime before spawn
#   - slack/interactions.py              maintainer OPTIONS click (confined channel) = typed message
# Rollback: restore the *.bak-sett-<stamp> files next to each edited file,
# delete _kc_confine.py, clear pyc, restart.
# ============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set T: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)
command -v bwrap >/dev/null || echo "Set T: WARNING bwrap not installed — confinement inert (strict gate stays)"

"$VENV_PY" - "$SITE" "$STAMP" "$HERE/patch-src/kc_confine.py" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp, src = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
MARK = "_kc_workspace_confine_v1"
changed = []

mod = site / "_kc_confine.py"
if not mod.exists() or mod.read_text() != src.read_text():
    shutil.copy2(src, mod); changed.append(mod)


def edit(path, old, new, label):
    s = path.read_text()
    if MARK in s:
        return
    if s.count(old) != 1:
        print(f"Set T: FAIL anchor for {label} in {path.relative_to(site)} (count={s.count(old)}) — re-derive"); sys.exit(1)
    shutil.copy2(path, path.with_name(path.name + f".bak-sett-{stamp}"))
    path.write_text(s.replace(old, new))
    changed.append(path)


LA = """        is_kiro_cli=delegate_internal_sandbox,
        _prepare=tools.wrap_argv,
    )
"""
edit(site / "acp/launch.py", LA, LA + """    # Set T (_kc_workspace_confine_v1): a maintainer channel's agent runs under bwrap,
    # confined to that channel's workspace (kiro_crew/_kc_confine.py). Never raises.
    from kiro_crew import _kc_confine as _kc_cf

    argv = await host._to_thread_guarding_sandbox(_kc_cf.maybe_confine, host, argv, scratch_window)
""", "launch wrap")

TA = """            from kiro_crew.slack.handler import is_owner as _kc_is_owner

            _kc_ask = False  # Set R (_kc_maintainer_ask_owner_v1)
"""
edit(site / "slack/transport_dispatch.py", TA, TA + """            # Set T (_kc_workspace_confine_v1): a maintainer whose session process is OS-confined
            # to this channel's workspace gets every BUILT-IN tool without asking; the kernel keeps
            # it inside the workspace. MCP tools and unconfined sessions fall through to the old gate.
            from kiro_crew import _kc_confine as _kc_cf

            if (
                not _kc_is_owner(user_id)
                and _kc_is_channel_maintainer(user_id, channel)
                and not _kc_cf.is_mcp_event(event)
                and _kc_cf.session_confined(client, channel)
            ):
                if context_builder is not None:
                    _kc_hr = context_builder.hooks.on_tool_call(
                        getattr(event, "title", "") or "",
                        session_key=session_key,
                        agent=_agent or "",
                        **hook_gate_kwargs(event),
                    )
                    if _kc_hr.action == TOOL_DENY:
                        return "deny"
                return "auto_approve"
""", "tool gate")

IA = """    if not is_owner(_kc_uid):
        logger.info("Set O3: dropped interactive payload from non-owner %s", _kc_uid or "unknown")
"""
edit(site / "slack/interactions.py", IA, """    # Set T (_kc_workspace_confine_v1): a maintainer's OPTIONS click in a confined channel
    # becomes a typed message in the thread (kiro_crew/_kc_confine.py); everything else stays O3.
    if not is_owner(_kc_uid):
        from kiro_crew import _kc_confine as _kc_cf

        try:
            if await _kc_cf.maintainer_options_as_message(_orch, payload):
                return
        except Exception:
            logger.warning("Set T: maintainer OPTIONS reroute failed", exc_info=True)
""" + IA, "O3 options reroute")

# kiro-cli / KAS: the shared AcpRuntime is the launch host and knows no channel;
# pin it before each of its two spawns so maybe_confine can resolve the workspace.
PA = site / "providers/acp.py"
ps = PA.read_text()
if MARK not in ps:
    A1 = """        _t_spawn = time.monotonic()
        try:
            await runtime.spawn(
"""
    A2 = """                    try:
                        await runtime.spawn(
"""
    if ps.count(A1) != 1 or ps.count(A2) != 1:
        print("Set T: FAIL anchor for kiro runtime spawn in providers/acp.py — re-derive"); sys.exit(1)
    shutil.copy2(PA, PA.with_name(PA.name + f".bak-sett-{stamp}"))
    PIN = "{i}runtime._channel_id = getattr(self._client, \"_channel_id\", None)  # Set T (_kc_workspace_confine_v1)\n{i}self._kc_runtime = runtime\n"
    ps = ps.replace(A1, "        _t_spawn = time.monotonic()\n" + PIN.format(i="        ") + "        try:\n            await runtime.spawn(\n")
    ps = ps.replace(A2, PIN.format(i="                    ") + A2)
    PA.write_text(ps); changed.append(PA)

for f in changed:
    if f.suffix == ".py":
        py_compile.compile(str(f), doraise=True)
    for pyc in (f.parent / "__pycache__").glob(f.stem + ".*.pyc"):
        pyc.unlink()
print("Set T: " + (("patched " + ", ".join(str(c.relative_to(site)) for c in changed)) if changed else "already applied — no-op"))
PY
rc=$?; [ $rc -eq 0 ] || exit $rc

# Prove: module imports in the venv, channel resolution works, and an escape probe fails.
"$VENV_PY" - <<'PY' || { echo "Set T: PROVE FAILED"; exit 1; }
import os, subprocess, json, pathlib
from kiro_crew import _kc_confine as k
_rp = k.CREW / "channel-roles.json"
# No roles file yet (no maintainer configured) is a normal install: nothing to prove.
roles = json.loads(_rp.read_text()).get("channels", {}) if _rp.exists() else {}
chans = [c for c in roles if k.channel_workspace(c)]
if not chans or not os.access(k.BWRAP, os.X_OK):
    print("Set T: prove skipped (no confined channel or no bwrap)"); raise SystemExit(0)
name, root = k.channel_workspace(chans[0])
home = k.private_home(name)
probe = (f"test -e {k.HOME}/.kiro/crew/.env && echo LEAK_ENV; test -e {k.HOME}/.ssh && echo LEAK_SSH; "
         f"ls {k.HOME}/Projects; touch {k.HOME}/.local/bin/.kc && echo LEAK_W; "
         f"docker ps >/dev/null 2>&1 && echo LEAK_DOCKER; sudo -n true 2>/dev/null && echo LEAK_SUDO; "
         f"touch {root}/.kc_t && rm {root}/.kc_t && echo WS_OK")
out = subprocess.run(k.bwrap_argv(["/bin/sh", "-c", probe], root, home, root),
                     capture_output=True, text=True, timeout=60).stdout
bad = [l for l in out.split() if l.startswith("LEAK")]
assert "WS_OK" in out and not bad, out
print(f"Set T: prove OK — {chans[0]} confined to {root}; secrets/other workspaces/docker/sudo unreachable")
PY
