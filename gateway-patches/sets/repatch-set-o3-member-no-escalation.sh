#!/usr/bin/env bash
# ============================================================================
# Set O3 — close the member→owner ESCALATION paths that bypass Set O2.
#
# WHY (found in a live member test): O2 correctly denied
# Edit/Bash on the member's own transport turns, but the agent then offered an
# [OPTIONS:] card ("Đã cấp quyền, thêm dòng test lại"). The member clicked it;
# slack/interactions.dispatch only checks is_allowed_user, then re-dispatches
# the answer through handler.maybe_route_linked_thread(route_pinned) into the
# DASHBOARD slot (_run_chat, source=dashboard) — owner approvals, no O2 gate —
# and README.md was edited / git status ran.
#
# Three owner-only gates (allowlisted members keep plain-message, read-only use):
#   1. interactions.dispatch     — every Block Kit payload (buttons, OPTIONS,
#      approvals, message shortcuts, modals) is owner-only.
#   2. handler.maybe_route_linked_thread — a non-owner message never enters a
#      linked dashboard slot (falls through to the transport path where O2 holds).
#   3. events slash command      — /kirocrew is owner-only.
#   4. handler.maybe_handle_keyword_command — spawn/run/cron keywords owner-only
#      (they bypass every tool gate; marker _kc_member_no_keyword_cmd_v1).
# Idempotent via the _kc_member_no_escalation_v1 marker.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set O3: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_member_no_escalation_v1"
MARK_KW = "_kc_member_no_keyword_cmd_v1"

PATCHES = {
    "slack/interactions.py": [(
        '    """Route a Block Kit interactive payload to the correct handler."""\n',
        '    """Route a Block Kit interactive payload to the correct handler."""\n'
        f'    # Set O3 ({MARK}): interactive payloads are OWNER-ONLY. A member\n'
        '    # clicking an OPTIONS/approval button re-dispatched the turn into the\n'
        '    # dashboard slot with owner approvals, bypassing Set O2.\n'
        '    _kc_uid = (payload.get("user") or {}).get("id", "")\n'
        '    if not is_owner(_kc_uid):\n'
        '        logger.info("Set O3: dropped interactive payload from non-owner %s", _kc_uid or "unknown")\n'
        '        sel().log_api_access(\n'
        '            caller=_kc_uid or "unknown",\n'
        '            operation="slack.interactive_owner_only",\n'
        '            outcome="denied",\n'
        '            source="slack",\n'
        '            error="member read-only (Set O3)",\n'
        '        )\n'
        '        _kc_ch = (payload.get("channel") or {}).get("id", "")\n'
        '        if _kc_uid and _kc_ch and _orch and _orch.slack:\n'
        '            try:\n'
        '                await _orch.slack.post_ephemeral(_kc_ch, _kc_uid, "⛔ Chỉ owner mới dùng được các nút này.")\n'
        '            except Exception:\n'
        '                logger.debug("Set O3 ephemeral failed", exc_info=True)\n'
        '        return\n',
    )],
    "slack/handler.py": [(
        '        _linked_slot = _dashboard_state.get_linked_slot(reply_ts)\n'
        '    if not _linked_slot:\n'
        '        return False\n',
        '        _linked_slot = _dashboard_state.get_linked_slot(reply_ts)\n'
        '    if not _linked_slot:\n'
        '        return False\n'
        f'    # Set O3 ({MARK}): a linked dashboard slot runs with OWNER approvals\n'
        '    # (source=dashboard) and no Set O2 gate — never route a non-owner into it.\n'
        '    # Strangers fall through to the original deny below (return True).\n'
        '    if is_allowed_user(user_id) and not is_owner(user_id):\n'
        '        logger.info("Set O3: member %s not routed into linked slot", user_id)\n'
        '        return False\n',
    ), (
        '    # ── Subagent spawn: "spawn <task>" (before cron to avoid NL overlap) ──\n',
        f'    # Set O3 ({MARK_KW}): spawn/run/cron keywords start work with NO tool\n'
        '    # gate at all (a spawned subagent has full tools). Non-owner falls through\n'
        '    # to a normal LLM turn, where Set O2 denies spawn_run/cron_add.\n'
        '    if not is_owner(user_id):\n'
        '        return False\n'
        '    # ── Subagent spawn: "spawn <task>" (before cron to avoid NL overlap) ──\n',
    )],
    "slack/events.py": [(
        '    # Deny-by-default — only allowed users can invoke slash commands\n'
        '    if not is_allowed_user(caller_id):\n',
        f'    # Set O3 ({MARK}): slash commands are OWNER-ONLY (members read-only).\n'
        '    if not is_owner(caller_id):\n',
    )],
}

# 0.9.0+ moved maybe_route_linked_thread into slack/handler_runtime/inbound.py
# (composed onto handler: it runs on handler's globals, so is_owner/is_allowed_user/
# logger resolve there). Each edit goes to the first candidate file holding its anchor.
CANDIDATES = {"slack/handler.py": ["slack/handler.py", "slack/handler_runtime/inbound.py",
                                    "slack/handler_runtime/dispatch.py"]}
work = {}
for rel, edits in PATCHES.items():
    for old, new in edits:
        mark = MARK_KW if MARK_KW in new else MARK
        files = [site / c for c in CANDIDATES.get(rel, [rel]) if (site / c).exists()]
        done = next((f for f in files if mark in f.read_text() and new.split("\n")[-3] in f.read_text()), None)
        if done is not None:
            continue
        hits = [f for f in files if (work.get(f) if f in work else f.read_text()).count(old) == 1]
        if len(hits) != 1:
            print(f"Set O3: FAIL anchor for {rel} found in {len(hits)} candidate file(s) — layout changed, re-derive"); sys.exit(1)
        f = hits[0]
        work[f] = (work.get(f) if f in work else f.read_text()).replace(old, new)
if not work:
    print("Set O3: already applied — no-op")
for f, text in work.items():
    shutil.copy2(f, f.with_name(f.name + f".bak-seto3-{stamp}"))
    f.write_text(text)
    py_compile.compile(str(f), doraise=True)
    for pyc in (f.parent / "__pycache__").glob(f.stem + ".*.pyc"):
        pyc.unlink()
    print(f"Set O3: patched {f.relative_to(site)}")

# Sanity: the names the gates use must exist in each module.
import importlib
for mod in ("kiro_crew.slack.interactions", "kiro_crew.slack.handler", "kiro_crew.slack.events"):
    m = importlib.import_module(mod)
    assert hasattr(m, "is_owner"), f"{mod} lacks is_owner"
import kiro_crew.slack.interactions as I
assert hasattr(I, "sel") and hasattr(I, "logger"), "interactions lacks sel/logger"
print("Set O3: OK (imports + names verified)")
PY
