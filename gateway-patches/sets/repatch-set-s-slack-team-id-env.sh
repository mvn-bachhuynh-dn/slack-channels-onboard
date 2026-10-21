#!/usr/bin/env bash
# ============================================================================
# Set S — KIROCREW_SLACK_TEAM_ID in the agent child env (2026-10-20).
#
# Upstream PR: kirodotdev/KiroCrew#22380 (fork branch feat/slack-team-id-env).
# An agent spawned for a Slack conversation gets, beside KIROCREW_CHANNEL_ID,
# the workspace (T…, or E… on an Enterprise Grid org install) the channel lives
# in, so a hook (MuDo) can open slack://channel?team=<TEAM>&id=<CHANNEL>.
#
# Source, in order: the channel's HOME workspace (conversations.info
# context_team_id, recorded by RealSlackClient.record_channel_team) → the bot's
# auth.test team_id / enterprise_id. Only for Slack-shaped channel ids. Never the
# inbound event's `team` (author's workspace; wrong on Slack Connect).
#
# Edits (each anchor-checked, idempotent by marker _kc_slack_team_env_v1):
#   - slack/team_ids.py          (new module, copied from patch-src/slack_team_ids.py)
#   - slack/client.py            record_channel_team also feeds team_ids
#   - slack/enterprise.py        validate_enterprise clears/sets the fallback
#   - acp/client.py OR acp/client_start.py   set/pop the env after KIROCREW_CHANNEL_ID
#   - providers/mirrors/identity.py          control-plane element carries it too
# Self-retires (prints "fixed upstream", exit 0) when the installed release
# already ships slack/team_ids.py with apply_slack_team_env wired into the spawn.
# ============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set S: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" "$HERE/patch-src/slack_team_ids.py" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp, src = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
MARK = "_kc_slack_team_env_v1"

mod = site / "slack/team_ids.py"
spawn_files = [site / "acp/client_start.py", site / "acp/client.py"]
if mod.exists() and MARK not in mod.read_text() and any(
    f.exists() and "apply_slack_team_env(env, self._channel_id)" in f.read_text() for f in spawn_files
):
    print("Set S: fixed upstream (slack/team_ids.py + spawn wiring shipped) — no-op")
    sys.exit(0)

changed = []


def edit(path, old_options, new_fn, label):
    s = path.read_text()
    if MARK in s:
        return
    for old in old_options:
        if s.count(old) == 1:
            s2 = s.replace(old, new_fn(old))
            shutil.copy2(path, path.with_name(path.name + f".bak-sets-{stamp}"))
            path.write_text(s2)
            changed.append(path)
            return
    print(f"Set S: FAIL anchor not found for {label} in {path.relative_to(site)} — re-derive"); sys.exit(1)


# 1. module
text = src.read_text()
text = text.replace('"""Slack channel -> workspace (team) id', f'"""Slack channel -> workspace (team) id  [Set S {MARK}]', 1)
if not mod.exists() or MARK not in mod.read_text():
    mod.write_text(text)
    changed.append(mod)

# 2. spawn env (0.8.0: acp/client.py at 8 spaces; 0.9.0: acp/client.py inside a
#    nested function at 12; main: acp/client_start.py). Indentation-agnostic.
import re
CHAN_RE = re.compile(
    r'^(?P<i>[ ]+)if self\._channel_id:\n(?P=i)    env\["KIROCREW_CHANNEL_ID"\] = self\._channel_id\n'
    r'(?P=i)else:\n(?P=i)    env\.pop\("KIROCREW_CHANNEL_ID", None\)\n', re.M)
spawn = None
for f in spawn_files:
    if f.exists() and len(CHAN_RE.findall(f.read_text())) == 1:
        spawn = f
        break
if spawn is None:
    print("Set S: FAIL — no unique KIROCREW_CHANNEL_ID spawn block found"); sys.exit(1)
st = spawn.read_text()
if MARK not in st:
    m = CHAN_RE.search(st)
    ind = m.group("i")
    ins = (
        f"{ind}# Set S ({MARK}): the channel's Slack workspace beside it (slack/team_ids.py).\n"
        f"{ind}from kiro_crew.slack.team_ids import apply_slack_team_env as _kc_apply_team\n\n"
        f"{ind}_kc_apply_team(env, self._channel_id)\n"
    )
    shutil.copy2(spawn, spawn.with_name(spawn.name + f".bak-sets-{stamp}"))
    spawn.write_text(st[: m.end()] + ins + st[m.end():])
    changed.append(spawn)

# 3. client record_channel_team
edit(site / "slack/client.py", ["            self._channel_team = cache\n        cache[channel] = team_id\n"], lambda o: o + (
    f"        # Set S ({MARK}): the agent child env reads the same canonical answer.\n"
    "        from kiro_crew.slack.team_ids import record_channel_team as _kc_record_team\n\n"
    "        _kc_record_team(channel, team_id)\n"
), "record_channel_team")

# 4. enterprise fallback
ent = site / "slack/enterprise.py"
edit(ent, [
    '    _validated_self_bot_id = ""\n    _validated_self_user_id = ""\n',
    '    _validated_self_bot_id = ""\n    _configured_ids = set()\n',
], lambda o: o + (
    f"    from kiro_crew.slack.team_ids import set_default_team as _kc_set_team  # Set S ({MARK})\n\n"
    "    _kc_set_team(\"\")\n"
), "enterprise clear")
s = ent.read_text()
old = "    _validated_team_id = team_id\n    _validated_enterprise_id = enterprise_id\n"
if "_kc_set_team(str(team_id" not in s:
    if s.count(old) != 1:
        print("Set S: FAIL enterprise success anchor"); sys.exit(1)
    ent.write_text(s.replace(old, old + "    _kc_set_team(str(team_id or enterprise_id or \"\"))  # Set S\n"))

# 5. mirrors control-plane element
ident = site / "providers/mirrors/identity.py"
if ident.exists():
    edit(ident, ['    if channel_id:\n        env["KIROCREW_CHANNEL_ID"] = channel_id\n'], lambda o: o + (
        f"        from kiro_crew.slack.team_ids import SLACK_TEAM_ID_ENV, slack_team_id_for  # Set S ({MARK})\n\n"
        "        _kc_team = slack_team_id_for(channel_id)\n"
        "        if _kc_team:\n"
        "            env[SLACK_TEAM_ID_ENV] = _kc_team\n"
    ), "mirrors identity")

for p in {*changed, ent}:
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()
print("Set S: patched " + ", ".join(sorted(str(p.relative_to(site)) for p in changed)) if changed else "Set S: already applied — no-op")

# prove (real code)
import importlib, os
T = importlib.import_module("kiro_crew.slack.team_ids")
T._reset_for_tests()
env = {T.SLACK_TEAM_ID_ENV: "T0STALE11"}
T.apply_slack_team_env(env, "C0ABC123"); assert T.SLACK_TEAM_ID_ENV not in env
T.record_channel_team("C0ABC123", "T0HOME42"); T.apply_slack_team_env(env, "C0ABC123"); assert env[T.SLACK_TEAM_ID_ENV] == "T0HOME42"
T._reset_for_tests(); T.set_default_team("E0ORG777"); assert T.slack_team_id_for("C0X1") == "E0ORG777"
assert T.slack_team_id_for("123456789012345678") == ""
T._reset_for_tests()
C = importlib.import_module("kiro_crew.slack.client")
c = C.RealSlackClient.__new__(C.RealSlackClient); c.record_channel_team("C0ABC123", "T0HOME42")
assert T.slack_team_id_for("C0ABC123") == "T0HOME42"
T._reset_for_tests()
assert "_kc_apply_team(env, self._channel_id)" in spawn.read_text()
print("Set S: OK (prove passed)")
PY
