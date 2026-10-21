"""Tests for slack-channels-onboard's backend: pure planning + the background detector.

Modules are loaded by file path exactly the way the gateway loads app hooks, so a
broken sibling import fails here too. The detector is driven with fake Slack and
config functions; nothing touches a real gateway, config.json or Slack.
"""

from __future__ import annotations

import asyncio
import json
import importlib.util
import sys
from pathlib import Path

import pytest

_BACKEND = Path(__file__).resolve().parents[1] / "backend"


def _load(name: str):
    key = f"_test_slack_channels_onboard_{name}"
    spec = importlib.util.spec_from_file_location(key, _BACKEND / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[key] = mod
    spec.loader.exec_module(mod)
    return mod


core = _load("core")
hooks = _load("hooks")
# hooks resolved its siblings through _load.sibling(); patch THAT instance.
ops = hooks.gateway_ops


# ----------------------------------------------------------------- core


def test_slugify():
    assert core.slugify("#MVN SA") == "mvn-sa"
    assert core.slugify("  ") == "channel"
    assert core.slugify("a" * 80) == "a" * 48


def test_normalize_settings_rejects_bad_values():
    s = core.normalize_settings(
        {"mode": "yolo", "activation": "loud", "poll_secs": 5, "thread_follow": "yes"}
    )
    assert s["mode"] == "auto"
    assert s["activation"] == "mention"
    assert s["poll_secs"] == 60
    assert s["thread_follow"] is True
    assert core.normalize_settings({"poll_secs": 99999})["poll_secs"] == 3600


def test_pending_skips_dms_and_configured():
    cfg = {"slack": {"channels": {"C1": {"agent": "a"}}}}
    bot = [{"id": "C1", "name": "one"}, {"id": "C2", "name": "two"}, {"id": "D9", "name": ""}]
    assert [c["id"] for c in core.pending_channels(cfg, bot)] == ["C2"]


def test_plan_onboard_unique_name_and_dir(tmp_path):
    cfg = {"agents": {"team": {}}, "workspaces": {"team-2": {}}}
    s = core.normalize_settings({"workspace_root": str(tmp_path)})
    plan = core.plan_onboard(cfg, channel_id="C5", channel_name="team", settings=s)
    assert plan["name"] == "team-3"
    assert plan["workspace_dir"] == str(tmp_path / "team-3")
    assert plan["binding"] == {"activation": "mention", "agent": "team-3", "thread_follow": True}


def test_plan_onboard_refuses_dm_and_existing():
    s = core.normalize_settings({})
    with pytest.raises(ValueError):
        core.plan_onboard({}, channel_id="D1", channel_name="x", settings=s)
    with pytest.raises(ValueError):
        core.plan_onboard(
            {"slack": {"channels": {"C1": {}}}}, channel_id="C1", channel_name="x", settings=s
        )
    with pytest.raises(ValueError):
        core.plan_onboard(
            {}, channel_id="C1", channel_name="x", settings=s, workspace_dir="relative/dir"
        )


def test_channel_rows_join():
    cfg = {
        "slack": {
            "channels": {"C1": {"agent": "a", "activation": "always", "thread_follow": False}}
        },
        "agents": {"a": {"workspace": "ws-a", "memory_store": "m-a"}},
        "workspaces": {"ws-a": {"dir": "/srv/a"}},
    }
    rows = {r["id"]: r for r in core.channel_rows(cfg, [{"id": "C2", "name": "two"}])}
    assert rows["C1"]["configured"] and not rows["C1"]["bot_member"]
    assert rows["C1"]["workspace_dir"] == "/srv/a" and rows["C1"]["memory_store"] == "m-a"
    assert rows["C2"] == {"id": "C2", "name": "two", "bot_member": True, "configured": False}


def test_mutators():
    d: dict = {}
    core.set_workspace(d, "w", "/x")
    core.set_binding(d, "C1", activation="mention", agent="w", thread_follow=True)
    core.set_binding(d, "C1", activation=None, thread_follow=False)
    assert d["workspaces"]["w"]["dir"] == "/x"
    assert d["slack"]["channels"]["C1"] == {
        "activation": "mention",
        "agent": "w",
        "thread_follow": False,
    }


def test_validate_reconfigure(tmp_path):
    assert core.validate_reconfigure(activation="always") == []
    assert core.validate_reconfigure(workspace_dir=str(tmp_path)) == []
    assert core.validate_reconfigure() == ["nothing to change"]
    assert core.validate_reconfigure(workspace_dir=str(tmp_path / "missing"))
    assert core.validate_reconfigure(thread_follow="no")


# ------------------------------------------------------------- detector


class _Storage:
    def __init__(self, initial=None):
        self.d = dict(initial or {})

    def get(self, k):
        return self.d.get(k)

    def set(self, k, v):
        self.d[k] = v


class _Ctx:
    def __init__(self, settings=None):
        self.storage = _Storage({"settings": settings or {}})


@pytest.fixture
def fake_ops(monkeypatch):
    state = {"cfg": {}, "bot": [], "members": {}, "dms": [], "onboarded": [], "fail": set()}

    async def bot_channels():
        return state["bot"]

    async def channel_has_member(cid, uid):
        return uid in state["members"].get(cid, set())

    async def dm_owner(text):
        state["dms"].append(text)

    async def onboard(cid, cname, settings, **kw):
        if cid in state["fail"]:
            raise RuntimeError("boom")
        state["onboarded"].append(cid)
        state["cfg"].setdefault("slack", {}).setdefault("channels", {})[cid] = {}
        return {
            "name": cname,
            "workspace_dir": f"/w/{cname}",
            "memory_store": "m",
            "binding": {"activation": "mention", "thread_follow": True},
        }

    monkeypatch.setattr(ops, "bot_channels", bot_channels)
    monkeypatch.setattr(ops, "channel_has_member", channel_has_member)
    monkeypatch.setattr(ops, "dm_owner", dm_owner)
    monkeypatch.setattr(ops, "onboard", onboard)
    monkeypatch.setattr(ops, "config_dict", lambda: state["cfg"])
    monkeypatch.setattr(ops, "owner_id", lambda: "UOWNER")
    return state


def _scan(ctx):
    return asyncio.run(hooks.scan_once(ctx))


def test_auto_onboards_only_owner_channels(fake_ops):
    fake_ops["bot"] = [{"id": "C1", "name": "mine"}, {"id": "C2", "name": "theirs"}]
    fake_ops["members"] = {"C1": {"UOWNER"}, "C2": {"USOMEONE"}}
    assert _scan(_Ctx({"mode": "auto"})) == ["onboarded C1"]
    assert fake_ops["onboarded"] == ["C1"]
    assert len(fake_ops["dms"]) == 1 and "mine" in fake_ops["dms"][0]
    # second pass: C1 now configured, C2 still not owner's
    assert _scan(_Ctx({"mode": "auto"})) == []


def test_owner_guard_can_be_disabled(fake_ops):
    fake_ops["bot"] = [{"id": "C2", "name": "theirs"}]
    assert _scan(_Ctx({"mode": "auto", "require_owner_member": False})) == ["onboarded C2"]


def test_notify_mode_dms_once_and_creates_nothing(fake_ops):
    fake_ops["bot"] = [{"id": "C1", "name": "mine"}]
    fake_ops["members"] = {"C1": {"UOWNER"}}
    ctx = _Ctx({"mode": "notify"})
    assert _scan(ctx) == ["notified C1"]
    assert _scan(ctx) == []
    assert fake_ops["onboarded"] == [] and len(fake_ops["dms"]) == 1


def test_off_mode_does_nothing(fake_ops):
    fake_ops["bot"] = [{"id": "C1", "name": "mine"}]
    fake_ops["members"] = {"C1": {"UOWNER"}}
    assert _scan(_Ctx({"mode": "off"})) == []
    assert fake_ops["dms"] == [] and fake_ops["onboarded"] == []


def test_failures_retry_then_report_once(fake_ops):
    fake_ops["bot"] = [{"id": "C1", "name": "mine"}]
    fake_ops["members"] = {"C1": {"UOWNER"}}
    fake_ops["fail"] = {"C1"}
    ctx = _Ctx({"mode": "auto"})
    for _ in range(5):
        _scan(ctx)
    assert fake_ops["onboarded"] == []
    assert len(fake_ops["dms"]) == 1 and "Could not onboard" in fake_ops["dms"][0]



# ------------------------------------------------------- people (slice 4)


def test_member_entries_and_normalize():
    cfg = {"slack": {"allowed_users": [{"slack_id": "U1AA", "name": "A"}, "bad", {"name": "x"},
                                       {"slack_id": "U1AA"}, {"slack_id": "nope"}]}}
    assert core.member_entries(cfg) == [{"slack_id": "U1AA", "name": "A"}]
    got = core.normalize_members(["U2BB", {"slack_id": "UOWNER1"}, {"slack_id": "U2BB"}], "UOWNER1")
    assert got == [{"slack_id": "U2BB", "name": ""}]
    with pytest.raises(ValueError):
        core.normalize_members([{"slack_id": "u-lower"}])
    with pytest.raises(ValueError):
        core.normalize_members("U2BB")


def test_set_maintainers_requires_membership_and_valid_ids():
    roles = {"channels": {"C1": {"maintainers": ["U1AA"]}}}
    new = core.set_maintainers(roles, "C2", ["U2BB", "U2BB"], {"U1AA", "U2BB"})
    assert new["channels"] == {"C1": {"maintainers": ["U1AA"]}, "C2": {"maintainers": ["U2BB"]}}
    assert roles["channels"] == {"C1": {"maintainers": ["U1AA"]}}  # input not mutated
    with pytest.raises(ValueError, match="not a member"):
        core.set_maintainers(roles, "C1", ["U9ZZ"], {"U1AA"})
    with pytest.raises(ValueError):
        core.set_maintainers(roles, "D1", ["U1AA"], {"U1AA"})
    with pytest.raises(ValueError):
        core.set_maintainers(roles, "C1", ["../x"], {"U1AA"})
    assert core.set_maintainers(roles, "C1", [], {"U1AA"})["channels"] == {}


def test_normalize_and_prune_roles():
    raw = {"channels": {"C1": {"maintainers": ["U1AA", "bad"]}, "D9": {"maintainers": ["U1AA"]},
                        "C2": "x", "C3": {"maintainers": ["U3CC"]}}}
    assert core.normalize_roles(raw) == {"channels": {"C1": {"maintainers": ["U1AA"]},
                                                      "C3": {"maintainers": ["U3CC"]}}}
    assert core.normalize_roles("garbage") == {"channels": {}}
    assert core.prune_roles(raw, {"U1AA"}) == {"channels": {"C1": {"maintainers": ["U1AA"]}}}


def test_people_view_lists_only_configured_channels():
    cfg = {"slack": {"channels": {"C1": {"agent": "a"}},
                     "allowed_users": [{"slack_id": "U1AA", "name": "A"}]},
           "agents": {"a": {"workspace": "a"}}, "workspaces": {"a": {"dir": "/w/a"}}}
    view = core.people_view(cfg, {"channels": {"C1": {"maintainers": ["U1AA"]}}},
                            [{"id": "C1", "name": "one"}, {"id": "C2", "name": "two"}])
    assert view["members"] == [{"slack_id": "U1AA", "name": "A"}]
    assert view["channels"] == [{"id": "C1", "name": "one", "agent": "a",
                                 "workspace_dir": "/w/a", "maintainers": ["U1AA"], "commands": [], "open": False, "programs": []}]
    assert [c["id"] for c in view["command_catalog"]] == list(core.COMMAND_IDS)


def test_commands_survive_maintainer_edits_and_prune():
    roles = {"channels": {"C1": {"maintainers": ["U1AA"], "commands": ["lint", "bogus", "deploy"]}}}
    norm = core.normalize_roles(roles)
    assert norm["channels"]["C1"] == {"maintainers": ["U1AA"], "commands": ["lint", "deploy"]}
    new = core.set_maintainers(roles, "C1", ["U2BB"], {"U1AA", "U2BB"})
    assert new["channels"]["C1"]["commands"] == ["lint", "deploy"]
    # no maintainer left: the approval is kept for when one is added back
    assert core.set_maintainers(roles, "C1", [], {"U1AA"})["channels"]["C1"] == {"commands": ["lint", "deploy"]}
    assert core.prune_roles(roles, set())["channels"]["C1"] == {"commands": ["lint", "deploy"]}
    # catalog order, duplicates collapse
    assert core.set_commands(norm, "C1", ["deploy", "typecheck", "deploy"])["channels"]["C1"]["commands"] == [
        "typecheck", "deploy"]
    assert core.set_commands({"channels": {}}, "C1", [])["channels"] == {}
    with pytest.raises(ValueError, match="unknown command"):
        core.set_commands(norm, "C1", ["npm-install"])
    with pytest.raises(ValueError, match="invalid channel"):
        core.set_commands(norm, "D1", ["lint"])
    with pytest.raises(ValueError):
        core.set_commands(norm, "C1", "lint")


@pytest.fixture
def people_ops(monkeypatch, tmp_path):
    monkeypatch.setenv("KIROCREW_HOME", str(tmp_path))
    state = {"cfg": {"slack": {"channels": {"C1": {"agent": "a"}}, "allowed_users": []}},
             "hot": [], "audit": []}

    async def _write(mutate):
        state["cfg"] = mutate(state["cfg"])

    async def _names(ids):
        return {u: f"name-{u}" for u in ids}

    monkeypatch.setattr(ops, "_write", _write)
    monkeypatch.setattr(ops, "_names", _names)
    monkeypatch.setattr(ops, "config_dict", lambda: state["cfg"])
    monkeypatch.setattr(ops, "owner_id", lambda: "UOWNER1")
    monkeypatch.setattr(ops, "_hot_apply_members", lambda ids: state["hot"].append(set(ids)) or True)
    monkeypatch.setattr(ops, "_audit", lambda op, res: state["audit"].append(op))
    return state


def test_roles_path_matches_gateway_formula(people_ops, tmp_path):
    assert ops.roles_path() == tmp_path / "channel-roles.json"


def test_update_members_writes_config_hot_applies_and_audits(people_ops):
    out = asyncio.run(ops.update_members([{"slack_id": "U1AA", "name": "typed"}, {"slack_id": "UOWNER1"}]))
    assert out["hot_applied"] is True
    assert people_ops["cfg"]["slack"]["allowed_users"] == [{"slack_id": "U1AA", "name": "name-U1AA"}]
    assert people_ops["hot"] == [{"U1AA"}] and people_ops["audit"] == ["members_update"]


def test_maintainers_roundtrip_atomic_file_and_prune(people_ops):
    asyncio.run(ops.update_members(["U1AA", "U2BB"]))
    asyncio.run(ops.update_maintainers("C1", ["U1AA", "U2BB"]))
    path = ops.roles_path()
    assert json.loads(path.read_text()) == {"channels": {"C1": {"maintainers": ["U1AA", "U2BB"]}}}
    assert oct(path.stat().st_mode & 0o777) == "0o600"
    assert not [p for p in path.parent.iterdir() if p.name.startswith(".channel-roles.")]
    # removing a member prunes them from every channel's maintainers
    asyncio.run(ops.update_members(["U2BB"]))
    assert json.loads(path.read_text()) == {"channels": {"C1": {"maintainers": ["U2BB"]}}}
    with pytest.raises(ValueError, match="not a member"):
        asyncio.run(ops.update_maintainers("C1", ["U1AA"]))
    with pytest.raises(ValueError, match="not onboarded"):
        asyncio.run(ops.update_maintainers("C9", ["U2BB"]))


def test_commands_roundtrip_keeps_maintainers_and_audits(people_ops):
    asyncio.run(ops.update_members(["U1AA"]))
    asyncio.run(ops.update_maintainers("C1", ["U1AA"]))
    out = asyncio.run(ops.update_commands("C1", ["build", "lint"]))
    assert out == {"channel_id": "C1", "commands": ["lint", "build"]}
    path = ops.roles_path()
    assert json.loads(path.read_text()) == {"channels": {"C1": {"maintainers": ["U1AA"], "commands": ["lint", "build"]}}}
    asyncio.run(ops.update_maintainers("C1", ["U1AA"]))  # a maintainer save must not drop commands
    assert json.loads(path.read_text())["channels"]["C1"]["commands"] == ["lint", "build"]
    assert "commands_update" in people_ops["audit"]
    with pytest.raises(ValueError, match="not onboarded"):
        asyncio.run(ops.update_commands("C9", ["lint"]))


def test_corrupt_roles_file_is_never_overwritten(people_ops):
    path = ops.roles_path()
    path.write_text("{broken")
    with pytest.raises(Exception):
        asyncio.run(ops.update_members(["U1AA"]))
    assert path.read_text() == "{broken"
    assert people_ops["cfg"]["slack"]["allowed_users"] == []  # config untouched too



def test_sibling_reloads_changed_file(tmp_path):
    """An app update runs in the same gateway process: a changed sibling must be
    re-executed, not served from the sys.modules cache."""
    import shutil

    shutil.copy(_BACKEND / "_load.py", tmp_path / "_load.py")
    (tmp_path / "mod_x.py").write_text("VALUE = 1\n")
    spec = importlib.util.spec_from_file_location("_test_co_load_tmp", tmp_path / "_load.py")
    loader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loader)
    assert loader.sibling("mod_x").VALUE == 1
    assert loader.sibling("mod_x") is loader.sibling("mod_x")  # unchanged -> cached
    (tmp_path / "mod_x.py").write_text("VALUE = 22\n")  # size changes too
    assert loader.sibling("mod_x").VALUE == 22
    sys.modules.pop(loader._PREFIX + "mod_x", None)


def test_clean_name_strips_zero_width():
    assert ops._clean_name("Jane D.\u200b [3] Team.\u200bCity") == "Jane D. [3] Team.City"
    assert ops._clean_name("  Jane\u200b\u200b  Doe ") == "Jane Doe"


def test_open_flag_survives_other_edits():
    roles = {"channels": {"C1": {"maintainers": ["U1AA"], "commands": ["lint"], "open": True},
                          "C2": {"open": "yes"}}}
    norm = core.normalize_roles(roles)
    assert norm["channels"] == {"C1": {"open": True, "maintainers": ["U1AA"], "commands": ["lint"]}}
    assert core.set_maintainers(roles, "C1", [], {"U1AA"})["channels"]["C1"] == {"open": True, "commands": ["lint"]}
    assert core.set_commands(roles, "C1", [])["channels"]["C1"] == {"open": True, "maintainers": ["U1AA"]}
    assert core.prune_roles(roles, set())["channels"]["C1"] == {"open": True, "commands": ["lint"]}
    assert core.set_open({"channels": {}}, "C9", True)["channels"] == {"C9": {"open": True}}
    assert core.set_open(norm, "C1", False)["channels"]["C1"] == {"maintainers": ["U1AA"], "commands": ["lint"]}
    for bad in ("yes", 1, None):
        with pytest.raises(ValueError):
            core.set_open(norm, "C1", bad)


def test_open_roundtrip_and_audit(people_ops):
    out = asyncio.run(ops.update_open("C1", True))
    assert out == {"channel_id": "C1", "open": True}
    assert json.loads(ops.roles_path().read_text()) == {"channels": {"C1": {"open": True}}}
    assert "open_update" in people_ops["audit"]
    with pytest.raises(ValueError, match="not onboarded"):
        asyncio.run(ops.update_open("C9", True))


def test_programs_validated_and_kept_by_every_edit():
    roles = {"channels": {"C1": {"maintainers": ["U1AA"], "programs": ["sed", "bash", "BAD name"]}}}
    norm = core.normalize_roles(roles)
    assert norm["channels"]["C1"] == {"maintainers": ["U1AA"], "programs": ["sed"]}  # never-list + junk dropped
    assert core.set_commands(roles, "C1", ["fs"])["channels"]["C1"]["programs"] == ["sed"]
    assert core.set_maintainers(roles, "C1", [], {"U1AA"})["channels"]["C1"] == {"programs": ["sed"]}
    assert core.set_open(roles, "C1", True)["channels"]["C1"]["programs"] == ["sed"]
    assert core.prune_roles(roles, set())["channels"]["C1"] == {"programs": ["sed"]}
    assert core.set_programs(norm, "C1", ["jq", "sed"])["channels"]["C1"]["programs"] == ["jq", "sed"]
    assert "programs" not in core.set_programs(norm, "C1", [])["channels"]["C1"]
    for bad in (["bash"], ["python3"], ["curl"], ["proxy"], ["rtk-x"], ["../x"], "sed"):
        with pytest.raises(ValueError):
            core.set_programs(norm, "C1", bad)


def test_programs_roundtrip_and_audit(people_ops):
    asyncio.run(ops.update_open("C1", True))
    out = asyncio.run(ops.update_programs("C1", ["sed"]))
    assert out == {"channel_id": "C1", "programs": ["sed"]}
    assert json.loads(ops.roles_path().read_text()) == {"channels": {"C1": {"open": True, "programs": ["sed"]}}}
    assert "programs_update" in people_ops["audit"]


def test_ensure_claude_ask_merges_and_excludes(tmp_path):
    (tmp_path / ".git" / "info").mkdir(parents=True)
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "settings.json").write_text('{"permissions": {"ask": ["Bash(git push:*)"]}, "x": 1}')
    assert ops.ensure_claude_ask(str(tmp_path)) is True
    data = json.loads((tmp_path / ".claude" / "settings.json").read_text())
    assert data["x"] == 1 and data["permissions"]["ask"] == ["Bash", "Bash(git push:*)", "Glob", "Grep", "Read"]
    assert "/.claude/settings.json" in (tmp_path / ".git" / "info" / "exclude").read_text().split("\n")
    assert ops.ensure_claude_ask(str(tmp_path)) is True  # idempotent
    assert (tmp_path / ".git" / "info" / "exclude").read_text().count("/.claude/settings.json") == 1
    assert ops.ensure_claude_ask(str(tmp_path / "missing")) is False


def test_remove_binding_keeps_agent_and_workspace():
    cfg = {"slack": {"channels": {"C1": {"agent": "a"}, "C2": {"agent": "b"}}},
           "agents": {"a": {"workspace": "a"}}, "workspaces": {"a": {"dir": "/w/a"}}}
    out = core.remove_binding(cfg, "C1")
    assert out["slack"]["channels"] == {"C2": {"agent": "b"}}
    assert out["agents"] == {"a": {"workspace": "a"}} and out["workspaces"] == {"a": {"dir": "/w/a"}}
    with pytest.raises(ValueError, match="not onboarded"):
        core.remove_binding(cfg, "C9")


def test_unbind_refuses_while_bot_is_in_the_channel(people_ops, monkeypatch):
    people_ops["cfg"]["slack"]["channels"]["C2"] = {"agent": "b"}

    async def _bot():
        return [{"id": "C1", "name": "one"}]

    monkeypatch.setattr(ops, "bot_channels", _bot)
    with pytest.raises(ValueError, match="still in this channel"):
        asyncio.run(ops.unbind("C1"))
    asyncio.run(ops.update_open("C2", True))
    out = asyncio.run(ops.unbind("C2"))
    assert out == {"channel_id": "C2", "ok": True}
    assert "C2" not in people_ops["cfg"]["slack"]["channels"]
    assert json.loads(ops.roles_path().read_text()) == {"channels": {}}
    assert "unbind" in people_ops["audit"]


def test_unbind_refuses_when_slack_cannot_be_read(people_ops, monkeypatch):
    async def _boom():
        raise RuntimeError("slack down")

    monkeypatch.setattr(ops, "bot_channels", _boom)
    with pytest.raises(ValueError, match="cannot verify"):
        asyncio.run(ops.unbind("C1"))


# ------------------------------------------------- agent backend (slice 5)


def test_channel_rows_carry_the_agent_backend_pin():
    cfg = {"slack": {"channels": {"C1": {"agent": "a"}, "C2": {"agent": "b"}, "C3": {"agent": "k"}}},
           "agents": {"a": {"acp_backend": "kas"}, "b": {"acp_backend": None}, "k": {"acp_backend": ""}}}
    rows = {r["id"]: r for r in core.channel_rows(cfg, [])}
    assert rows["C1"]["acp_backend"] == "kas"
    assert rows["C2"]["acp_backend"] is None  # null inherits
    assert rows["C3"]["acp_backend"] == ""  # "" pins kiro-cli, not inherit


def test_set_agent_backend_pins_and_unpins():
    cfg = {"agents": {"a": {"model": "m"}}}
    core.set_agent_backend(cfg, "a", "")
    assert cfg["agents"]["a"] == {"model": "m", "acp_backend": ""}
    core.set_agent_backend(cfg, "a", None)
    assert cfg["agents"]["a"] == {"model": "m"}
    with pytest.raises(ValueError, match="does not exist"):
        core.set_agent_backend(cfg, "zz", "kas")


@pytest.fixture
def backend_ops(people_ops, monkeypatch):
    people_ops["cfg"]["agents"] = {"a": {}}
    people_ops["cfg"]["slack"]["channels"]["C2"] = {"agent": "a"}
    monkeypatch.setattr(ops, "_backend_field_supported", lambda: True)
    monkeypatch.setattr(ops, "_backend_options_sync", lambda: [
        {"id": "", "label": "kiro", "installed": "installed"},
        {"id": "kas", "label": "kas", "installed": "installed"},
        {"id": "codex", "label": "codex", "installed": "missing"},
    ])
    return people_ops


def test_update_backend_pins_the_shared_agent_and_audits(backend_ops):
    out = asyncio.run(ops.update_backend("C1", "kas"))
    assert out == {"channel_id": "C1", "agent": "a", "acp_backend": "kas", "channels": ["C1", "C2"]}
    assert backend_ops["cfg"]["agents"]["a"]["acp_backend"] == "kas"
    assert "backend_update" in backend_ops["audit"]
    asyncio.run(ops.update_backend("C1", None))
    assert "acp_backend" not in backend_ops["cfg"]["agents"]["a"]


def test_update_backend_refuses_unusable_values(backend_ops, monkeypatch):
    for bad, msg in (("codex", "not installed"), ("bogus", "not allowed"), (3, "string or null")):
        with pytest.raises(ValueError, match=msg):
            asyncio.run(ops.update_backend("C1", bad))
    with pytest.raises(ValueError, match="not onboarded"):
        asyncio.run(ops.update_backend("C9", "kas"))
    monkeypatch.setattr(ops, "_backend_field_supported", lambda: False)
    with pytest.raises(ValueError, match="does not support"):
        asyncio.run(ops.update_backend("C1", "kas"))
    assert "acp_backend" not in backend_ops["cfg"]["agents"]["a"]


def test_backend_support_hides_the_column_on_a_stock_gateway(monkeypatch):
    monkeypatch.setattr(ops, "_backend_field_supported", lambda: False)
    assert asyncio.run(ops.backend_support()) == {"supported": False, "options": [], "default": "", "refuses": False}
