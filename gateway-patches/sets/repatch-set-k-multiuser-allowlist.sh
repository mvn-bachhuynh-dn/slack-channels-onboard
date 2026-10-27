#!/usr/bin/env bash
# ============================================================================
# Set K — Slack multi-user allowlist (deny-by-default, owner always allowed).
#
# Upstream locks Slack to owner-only at runtime ("Multi-user access is disabled
# for security"). Steve re-enabled per-user allowlist access: only users in
# slack.allowed_users may chat (owner always allowed, empty list => owner-only).
# Full rationale + config format: ~/.kiro/steering/slack-multiuser-allowlist.md
#
# Two edits, both overwritten by every `kirocrew update`:
#   1) slack/handler.py :: is_allowed_user — owner-only -> allowlist set.
#   2) slack/gateway.py :: GatewayOrchestrator.__init__ — stop PRUNING
#      cfg.slack.allowed_users down to the owner; load the full set instead.
# transport.py::authorize already reads the set correctly; only the load matters.
#
# Idempotent: no-op once patched (markers present). Applied in place because the
# pipx venv (0.6.0) is the running gateway; the repo checkout may be a different
# version. Config format for slack.allowed_users MUST be a list of objects
# {"slack_id":"U…","name":"…"} — string entries are silently dropped by loader.
# ============================================================================
set -uo pipefail

SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
if [ -z "$SITE" ]; then
  echo "Set K: installed kirocrew venv not found — skipping"
  exit 0
fi
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
HD="$SITE/slack/handler.py"
# 0.9.0+: the predicate moved to slack/handler_runtime/access.py (composed onto handler).
if [ -f "$SITE/slack/handler_runtime/access.py" ] && grep -q "^def is_allowed_user" "$SITE/slack/handler_runtime/access.py"; then
  HD="$SITE/slack/handler_runtime/access.py"
fi
GW="$SITE/slack/gateway.py"
for f in "$HD" "$GW"; do
  [ -f "$f" ] || { echo "Set K: $f not found — Kiro Crew layout changed; re-check anchors."; exit 1; }
done

# ---- Edit 1: handler.py :: is_allowed_user -------------------------------
python3 - "$HD" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()

if "return user_id in _allowed_users or is_owner(user_id)" in s:
    print(f"Set K [{p.name}]: already applied — no-op"); sys.exit(0)

OLD = (
    'def is_allowed_user(user_id: str) -> bool:\n'
    '    """Check if user_id is the owner.\n'
    '\n'
    '    Multi-user access is disabled for security — only the owner\n'
    '    (KIROCREW_OWNER_ID) is authorized to interact via Slack.\n'
    '    """\n'
    '    if not user_id:\n'
    '        return False\n'
    '    return is_owner(user_id)\n'
)
NEW = (
    'def is_allowed_user(user_id: str) -> bool:\n'
    '    """Check if *user_id* may interact via Slack.\n'
    '\n'
    '    Deny-by-default: authorized when *user_id* is in the allow-list set\n'
    '    (``_allowed_users``), which the gateway populates with the owner plus\n'
    '    every ``slack.allowed_users`` entry. The owner is always included, so an\n'
    '    empty config allowlist still authorizes the owner. Falls back to an\n'
    '    owner-only check if the set was never populated.\n'
    '    """\n'
    '    if not user_id:\n'
    '        return False\n'
    '    if _allowed_users:\n'
    '        return user_id in _allowed_users or is_owner(user_id)\n'
    '    return is_owner(user_id)\n'
)
if s.count(OLD) != 1:
    print(f"Set K [{p.name}]: is_allowed_user anchor not unique — CHECK ANCHORS"); sys.exit(1)
p.write_text(s.replace(OLD, NEW, 1))
print(f"Set K [{p.name}]: OK")
PY
rc1=$?

# ---- Edit 2: gateway.py :: __init__ load full allowlist --------------------
python3 - "$GW" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()

if "u[\"slack_id\"] for u in cfg.slack.allowed_users if u.get(\"slack_id\")" in s:
    print("Set K [gateway.py]: already applied — no-op"); sys.exit(0)

OLD = (
    '        self._owner_id = creds.get(CRED_OWNER_ID, "")\n'
    '        # Multi-user access is disabled — only owner is authorized.\n'
    '        # Prune stale allowed_users entries from config and warn.\n'
    '        stale = {u["slack_id"] for u in cfg.slack.allowed_users} - (\n'
    '            {self._owner_id} if self._owner_id else set()\n'
    '        )\n'
    '        if stale:\n'
    '            logger.warning(\n'
    '                "Pruning %d stale allowlist entries (multi-user disabled): %s",\n'
    '                len(stale),\n'
    '                stale,\n'
    '            )\n'
    '        self._allowed_users: set[str] = {self._owner_id} if self._owner_id else set()\n'
)
NEW = (
    '        self._owner_id = creds.get(CRED_OWNER_ID, "")\n'
    '        # Multi-user access via allowlist (Set K): owner always allowed, plus\n'
    '        # every slack.allowed_users entry. Empty list => owner-only.\n'
    '        self._allowed_users: set[str] = {self._owner_id} if self._owner_id else set()\n'
    '        self._allowed_users |= {\n'
    '            u["slack_id"] for u in cfg.slack.allowed_users if u.get("slack_id")\n'
    '        }\n'
)
if s.count(OLD) != 1:
    print("Set K [gateway.py]: __init__ prune anchor not unique — CHECK ANCHORS"); sys.exit(1)
p.write_text(s.replace(OLD, NEW, 1))
print("Set K [gateway.py]: OK")
PY
rc2=$?

# ---- compile both ----------------------------------------------------------
if [ -n "$VENV_PY" ]; then
  "$VENV_PY" -m py_compile "$HD" "$GW" && echo "Set K: compile OK" || { echo "Set K: compile FAILED"; exit 1; }
else
  python3 -m py_compile "$HD" "$GW" && echo "Set K: compile OK (fallback python3)"
fi

# ---- prove: an allowlisted non-owner is authorized, a stranger is not ------
if [ -n "$VENV_PY" ]; then
  "$VENV_PY" - <<'PY'
from kiro_crew.slack import handler as h
h.set_allowed_users({"UOWNER", "UALLOWED"})
# monkeypatch is_owner to a known owner
# patch is_owner in the namespace is_allowed_user actually resolves it from
# (handler.py up to 0.8.0, handler_runtime/access.py composition from 0.9.0)
H = h.is_allowed_user.__globals__
_orig = H["is_owner"]
H["is_owner"] = lambda u: u == "UOWNER"
try:
    owner_ok    = h.is_allowed_user("UOWNER")     # owner
    allowed_ok  = h.is_allowed_user("UALLOWED")   # allowlisted non-owner
    stranger_no = not h.is_allowed_user("USTRANGER")
    empty_owner = None
    h.set_allowed_users(set())                    # empty => owner-only fallback
    empty_owner = h.is_allowed_user("UOWNER") and not h.is_allowed_user("UALLOWED")
finally:
    H["is_owner"] = _orig
print(f"Set K: owner={owner_ok} allowed={allowed_ok} stranger_denied={stranger_no} empty_owner_only={empty_owner}")
import sys; sys.exit(0 if (owner_ok and allowed_ok and stranger_no and empty_owner) else 1)
PY
fi
