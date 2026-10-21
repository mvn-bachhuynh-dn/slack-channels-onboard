"""In-gateway operations for slack-channels-onboard.

This module runs INSIDE the Kiro Crew gateway (``backend.hooks``), so it can use
the gateway's own config writer, member-memory provisioning and Slack
credentials. Every write goes through the same locked paths the dashboard and
the owner's Slack channel modal use:

* config.json edits -> ``config.loader.update_config_locked`` under the dashboard
  config lock, followed by ``slack.handler._reload_orch_cfg`` (in-place reload,
  the same step the Slack channel modal takes);
* a new agent with private memory -> the ``POST /api/agents`` sequence
  (``provision_member_memory`` + ``persist_member_config`` with the
  unpublished-allocation rollback).

Kiro Crew internals are imported lazily inside each function: importing a
``kiro_crew.slack`` module at import time from another slack-adjacent module has
caused a circular import that took the gateway down before.

The Slack bot token is read from the gateway's credential store at call time,
sent only to slack.com over HTTPS, and never logged or returned.
"""

from __future__ import annotations

import asyncio
import importlib
import inspect
import json
import logging
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

import importlib.util as _ilu
from pathlib import Path as _P

_spec = _ilu.spec_from_file_location(
    "_kirocrew_app_slack_channels_onboard_loader", _P(__file__).with_name("_load.py")
)
_loader = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_loader)
core = _loader.sibling("core")

logger = logging.getLogger("kirocrew.app.slack-channels-onboard")

_SLACK_API = "https://slack.com/api/"


# ---------------------------------------------------------------- credentials


def _creds() -> dict:
    from kiro_crew.config.loader import KiroCrewConfig

    return KiroCrewConfig.load().load_credentials()


def owner_id() -> str:
    from kiro_crew.config.loader import CRED_OWNER_ID

    return _creds().get(CRED_OWNER_ID, "")


def _bot_token() -> str:
    from kiro_crew.config.loader import CRED_SLACK_BOT_TOKEN

    token = _creds().get(CRED_SLACK_BOT_TOKEN, "")
    if not token:
        raise RuntimeError("SLACK_BOT_TOKEN is not configured")
    return token


# ---------------------------------------------------------------------- slack


def _slack_call(method: str, params: dict[str, Any], *, post: bool = False) -> dict:
    token = _bot_token()
    headers = {"Authorization": f"Bearer {token}"}
    if post:
        data = json.dumps(params).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"
        req = urllib.request.Request(_SLACK_API + method, data=data, headers=headers)
    else:
        query = urllib.parse.urlencode(params)
        req = urllib.request.Request(f"{_SLACK_API}{method}?{query}", headers=headers)
    # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected -- the URL is always the fixed https://slack.com/api/ prefix plus a Slack method name chosen in this module; no caller input reaches the scheme or host, so file:// is unreachable  # noqa: E501
    with urllib.request.urlopen(req, timeout=20) as resp:  # noqa: S310 - fixed https host
        body = json.loads(resp.read().decode("utf-8"))
    if not body.get("ok"):
        raise RuntimeError(f"Slack {method} failed: {body.get('error', 'unknown')}")
    return body


def _paginate(method: str, params: dict[str, Any], key: str) -> list:
    out: list = []
    cursor = ""
    for _ in range(50):  # hard cap: 50 pages
        page = dict(params, cursor=cursor) if cursor else dict(params)
        body = _slack_call(method, page)
        out.extend(body.get(key, []))
        cursor = (body.get("response_metadata") or {}).get("next_cursor", "")
        if not cursor:
            break
    return out


def _bot_channels_sync() -> list[dict]:
    chans = _paginate(
        "users.conversations",
        {"types": "public_channel,private_channel", "exclude_archived": "true", "limit": 200},
        "channels",
    )
    return [{"id": c.get("id", ""), "name": c.get("name", "")} for c in chans if c.get("id")]


async def bot_channels() -> list[dict]:
    """Channels the bot is a member of (id + name)."""
    return await asyncio.to_thread(_bot_channels_sync)


async def channel_has_member(channel_id: str, user_id: str) -> bool:
    if not user_id:
        return False
    members = await asyncio.to_thread(
        _paginate, "conversations.members", {"channel": channel_id, "limit": 500}, "members"
    )
    return user_id in members


async def dm_owner(text: str) -> None:
    """Best-effort DM to the owner; failures are logged, never raised."""
    uid = owner_id()
    if not uid:
        return

    def _send() -> None:
        dm = _slack_call("conversations.open", {"users": uid}, post=True)
        channel = (dm.get("channel") or {}).get("id", "")
        if channel:
            _slack_call("chat.postMessage", {"channel": channel, "text": text}, post=True)

    try:
        await asyncio.to_thread(_send)
    except Exception as exc:  # noqa: BLE001 - a notification must not break onboarding
        logger.warning("slack-channels-onboard: owner DM failed: %s", exc)


# --------------------------------------------------------------------- config


def config_dict() -> dict:
    from kiro_crew.config.loader import config_path, read_config_text

    return json.loads(read_config_text(config_path()))


async def _write(mutate) -> None:
    """Locked read-modify-write of config.json, then reload the shared config."""
    from kiro_crew.config.loader import config_path, update_config_locked
    from kiro_crew.dashboard.chat_utils import run_config_write
    from kiro_crew.security.paths import is_sensitive_path

    path = config_path()
    if is_sensitive_path(str(path)):
        raise ValueError(f"refusing to write sensitive path {path}")
    await run_config_write(update_config_locked, path, mutate=mutate)
    _reload()


def _reload() -> None:
    from kiro_crew.slack.handler import _reload_orch_cfg

    _reload_orch_cfg()


def _check_workspace_dir(ws_dir: str, *, create: bool) -> str:
    from kiro_crew.security.paths import is_sensitive_path

    p = Path(ws_dir).expanduser()
    if not p.is_absolute():
        raise ValueError("workspace directory must be absolute")
    if is_sensitive_path(str(p)):
        raise ValueError(f"refusing a sensitive workspace directory: {p}")
    if create:
        p.mkdir(parents=True, exist_ok=True)
    elif not p.is_dir():
        raise ValueError(f"workspace directory does not exist: {p}")
    return str(p.resolve())


async def _create_agent(name: str, workspace: str, description: str, dedicated: bool) -> str:
    """Create agents.<name> (kiro_agent=kirocrew). Returns its memory store."""
    from kiro_crew.config.loader import KiroCrewAgentConfig, KiroCrewConfig
    from kiro_crew.dashboard.handlers.agents import _get_config_lock
    from kiro_crew.memory_stores import (
        MemberAlreadyExists,
        persist_member_config,
        provision_member_memory,
        retire_unpublished_allocation,
    )

    if not dedicated:
        entry = {
            "kiro_agent": "kirocrew",
            "workspace": workspace,
            "memory_store": "default",
            "description": description,
            "triggers": name,
            "source": "kirocrew",
        }

        def _add(data: dict) -> dict:
            agents = data.setdefault("agents", {})
            if name in agents:
                raise ValueError(f"agent {name} already exists")
            agents[name] = entry
            return data

        await _write(_add)
        return "default"

    # Same sequence as POST /api/agents: the gateway allocates the private member
    # memory and publishes agent + store together; an allocation that never
    # reached config.json is retired on the way out.
    async with _get_config_lock():
        cfg = KiroCrewConfig.load()
        if name in cfg.agents:
            raise ValueError(f"agent {name} already exists")
        agent = KiroCrewAgentConfig(
            kiro_agent="kirocrew",
            workspace=workspace,
            memory_store="default",
            description=description,
            triggers=name,
            source="kirocrew",
        )
        cfg.agents[name] = agent
        previous_store, previous_member = agent.memory_store, agent.member_id
        try:
            await asyncio.to_thread(provision_member_memory, cfg, name)
            await asyncio.to_thread(lambda: persist_member_config(cfg, name, create=True))
        except MemberAlreadyExists as exc:
            raise ValueError(f"agent {name} already exists") from exc
        except BaseException:
            allocated = cfg.agents[name].memory_store
            if allocated != previous_store:
                await asyncio.to_thread(
                    lambda: retire_unpublished_allocation(
                        cfg,
                        name,
                        allocated,
                        previous_store=previous_store,
                        previous_member_id=previous_member,
                    )
                )
            raise
        store = cfg.agents[name].memory_store
    _reload()
    return store


# ------------------------------------------------------------------ use cases


async def onboard(
    channel_id: str,
    channel_name: str,
    settings: dict,
    *,
    name: str | None = None,
    workspace_dir: str | None = None,
) -> dict:
    """Provision workspace + agent (+ private memory) + binding for a channel."""
    plan = core.plan_onboard(
        config_dict(),
        channel_id=channel_id,
        channel_name=channel_name,
        settings=settings,
        name=name,
        workspace_dir=workspace_dir,
    )
    ws_dir = _check_workspace_dir(plan["workspace_dir"], create=True)
    await _write(lambda d: core.set_workspace(d, plan["workspace"], ws_dir))
    store = await _create_agent(
        plan["name"],
        plan["workspace"],
        f"{plan['name']} project agent (auto-onboarded from Slack #{channel_name or channel_id})",
        plan["dedicated_memory"],
    )
    # The binding is written LAST: until it exists the channel keeps its old
    # (default-agent) routing, so a failure above never leaves a channel bound
    # to a half-created agent.
    await _write(lambda d: core.set_binding(d, channel_id, **plan["binding"]))
    logger.info(
        "slack-channels-onboard: onboarded %s as agent %s (ws=%s, store=%s)",
        channel_id,
        plan["name"],
        ws_dir,
        store,
    )
    return dict(plan, workspace_dir=ws_dir, memory_store=store, channel_id=channel_id)


async def reconfigure(
    channel_id: str,
    *,
    workspace_dir: str | None = None,
    activation: str | None = None,
    thread_follow: bool | None = None,
) -> dict:
    errors = core.validate_reconfigure(activation, thread_follow, workspace_dir)
    if errors:
        raise ValueError("; ".join(errors))
    cfg = config_dict()
    binding = (cfg.get("slack", {}).get("channels", {}) or {}).get(channel_id)
    if binding is None:
        raise ValueError(f"channel {channel_id} is not onboarded")
    if workspace_dir is not None:
        agent = (cfg.get("agents", {}) or {}).get(binding.get("agent", ""))
        if not agent:
            raise ValueError("channel is not bound to an agent; cannot change its workspace")
        ws_key = agent.get("workspace") or binding["agent"]
        ws_dir = _check_workspace_dir(workspace_dir, create=False)
        await _write(lambda d: core.set_workspace(d, ws_key, ws_dir))
    if activation is not None or thread_follow is not None:
        await _write(
            lambda d: core.set_binding(
                d, channel_id, activation=activation, thread_follow=thread_follow
            )
        )
    return {"channel_id": channel_id, "ok": True}


async def unbind(channel_id: str) -> dict:
    """Remove the binding of a channel the bot is no longer in.

    Refused while the bot is still a member (that channel would silently stop
    answering); the channel's roles entry is pruned with it. Agent, workspace
    and memory are kept.
    """
    if not (isinstance(channel_id, str) and core._CHANNEL_ID_RE.match(channel_id)):
        raise ValueError(f"invalid channel id: {channel_id!r}")
    try:
        bot = await bot_channels()
    except Exception as exc:  # noqa: BLE001 - cannot prove the bot left: refuse
        raise ValueError(f"cannot verify the bot left the channel: {exc}") from exc
    if any(c.get("id") == channel_id for c in bot):
        raise ValueError("the bot is still in this channel; remove it from the channel first")
    await _write(lambda d: core.remove_binding(d, channel_id))
    async with _ROLES_LOCK:
        roles = read_roles()
        if channel_id in roles["channels"]:
            roles["channels"].pop(channel_id)
            await asyncio.to_thread(_write_roles_sync, roles)
    _audit("unbind", f"channel={channel_id}")
    logger.info("slack-channels-onboard: unbound %s", channel_id)
    return {"channel_id": channel_id, "ok": True}



# ------------------------------------------------------- people (slice 4)

_ROLES_LOCK = asyncio.Lock()
_NAME_CACHE: dict[str, str] = {}
_NAME_CACHE_MAX = 500


def roles_path() -> Path:
    """``<data home>/channel-roles.json`` — the SAME formula the gateway's
    maintainer gate (Set P, ``transport_dispatch._kc_roles_path``) reads."""
    import os

    home = os.environ.get("KIROCREW_HOME") or str(Path.home() / ".kiro" / "crew")
    return Path(home) / "channel-roles.json"


def read_roles() -> dict:
    """The roles document; missing file -> empty. Unreadable/invalid JSON RAISES,
    so a corrupt file is never silently overwritten with an empty one."""
    path = roles_path()
    if not path.exists():
        return {"channels": {}}
    return core.normalize_roles(json.loads(path.read_text(encoding="utf-8")))


def _write_roles_sync(roles: dict) -> None:
    import contextlib
    import os
    import tempfile

    path = roles_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".channel-roles.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(core.normalize_roles(roles), fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)  # atomic: the gate never reads a half-written file
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def _audit(operation: str, resources: str) -> None:
    try:
        from kiro_crew.sel import sel

        sel().log_api_access(
            caller=owner_id() or "owner",
            operation=f"slack_channels_onboard.{operation}",
            outcome="allowed",
            source="dashboard",
            resources=resources,
        )
    except Exception:  # noqa: BLE001 - auditing must not break the write
        logger.warning("slack-channels-onboard: SEL audit failed for %s", operation, exc_info=True)


def _hot_apply_members(member_ids: set[str]) -> bool:
    """Push the new allowlist into the running gateway (no restart).

    Same two steps as the gateway's own allowlist-select handler
    (``slack.interactions``): the orchestrator's set (which the Slack transport
    is built from) and ``slack.handler.set_allowed_users`` (``is_allowed_user``).
    Returns False when no running Slack gateway was found (a restart applies it).
    """
    try:
        from kiro_crew.slack import interactions
        from kiro_crew.slack.handler import set_allowed_users

        orch = getattr(interactions, "_orch", None)
        if orch is None or not hasattr(orch, "_allowed_users"):
            return False
        owner = owner_id()
        new = set(member_ids) | ({owner} if owner else set())
        orch._allowed_users = new
        set_allowed_users(new)
        return True
    except Exception:  # noqa: BLE001
        logger.warning("slack-channels-onboard: allowlist hot-apply failed", exc_info=True)
        return False


def _clean_name(raw: str) -> str:
    """Drop zero-width / format characters Slack keeps in display names
    ("Jane D.\u200b Team.\u200bCity") and collapse whitespace."""
    import unicodedata

    kept = "".join(ch for ch in str(raw) if unicodedata.category(ch) != "Cf")
    return " ".join(kept.split())[:120]


def _user_name_sync(uid: str) -> dict:
    body = _slack_call("users.info", {"user": uid})
    u = body.get("user") or {}
    raw = u.get("real_name") or (u.get("profile") or {}).get("real_name") or u.get("name", "")
    return {
        "slack_id": uid,
        "name": _clean_name(raw),
        "is_bot": bool(u.get("is_bot")),
        "deleted": bool(u.get("deleted")),
    }


async def resolve_user(uid: str) -> dict:
    """Look a user up on Slack (needs ``users:read``). Raises ValueError for an
    id that is not a real, active human user."""
    if not core.valid_user_id(uid):
        raise ValueError(f"invalid Slack user id: {uid!r}")
    try:
        info = await asyncio.to_thread(_user_name_sync, uid)
    except RuntimeError as exc:
        raise ValueError(str(exc)) from exc
    if info["is_bot"] or info["deleted"]:
        raise ValueError(f"{uid} is a bot or a deactivated account")
    if len(_NAME_CACHE) < _NAME_CACHE_MAX:
        _NAME_CACHE[uid] = info["name"]
    return info


async def _names(ids: list[str]) -> dict[str, str]:
    out = {}
    for uid in ids:
        if uid in _NAME_CACHE:
            out[uid] = _NAME_CACHE[uid]
            continue
        try:
            out[uid] = (await resolve_user(uid))["name"]
        except Exception:  # noqa: BLE001 - a name is cosmetic
            out[uid] = ""
    return out


async def people() -> dict:
    cfg = config_dict()
    try:
        bot = await bot_channels()
    except Exception:  # noqa: BLE001
        bot = []
    roles_error = ""
    try:
        roles = read_roles()
    except Exception as exc:  # noqa: BLE001
        roles, roles_error = {"channels": {}}, f"{roles_path()}: {exc}"
    view = core.people_view(cfg, roles, bot)
    owner = owner_id()
    ids = [m["slack_id"] for m in view["members"]] + ([owner] if owner else [])
    names = await _names(ids)
    for m in view["members"]:
        # The Slack profile name wins; the stored name is only a fallback for an
        # id Slack cannot resolve (it was typed by hand, e.g. "Jane").
        m["display"] = names.get(m["slack_id"]) or m["name"]
    view["owner"] = {"slack_id": owner, "display": names.get(owner, "")}
    view["roles_path"] = str(roles_path())
    view["roles_error"] = roles_error
    view["capabilities"] = access_capabilities()
    return view


# ------------------------------------------------- agent backend (slice 5)


def _backend_field_supported() -> bool:
    """Whether the running gateway reads ``agents.<name>.acp_backend``.

    True on a gateway patched with Set U and on an upstream release that ships
    the field; False on a stock 0.9.0, where writing the key would be silently
    dropped on the next config save.
    """
    try:
        from kiro_crew.config.sections import KiroCrewAgentConfig

        return "acp_backend" in getattr(KiroCrewAgentConfig, "__dataclass_fields__", {})
    except Exception:  # noqa: BLE001
        return False


def _backend_refuses() -> bool:
    """Whether an unusable pin refuses the session (Set U) rather than degrading
    to kiro-cli (upstream PR #16200's behaviour)."""
    try:
        from kiro_crew import members

        return hasattr(members, "CrewBackendRefused")
    except Exception:  # noqa: BLE001
        return False


def _backend_options_sync() -> list[dict]:
    """Backends the gateway allows, each with its machine-local install state."""
    from kiro_crew.acp_backends import selectable_backends

    installed: dict[str, str] = {}
    try:
        from kiro_crew.agent_sdk.backend_install import probe_backends

        installed = {s.backend: s.installed for s in probe_backends()}
    except Exception:  # noqa: BLE001 - no probe: show every backend as unknown
        logger.warning("slack-channels-onboard: backend install probe failed", exc_info=True)
    return [
        {"id": b, "label": b or "kiro", "installed": installed.get(b, "unknown")}
        for b in sorted(selectable_backends(), key=lambda b: (b != "", b))
    ]


async def backend_support() -> dict:
    """What the page needs for the Agent backend column."""
    if not _backend_field_supported():
        return {"supported": False, "options": [], "default": "", "refuses": False}
    cfg = config_dict()
    default = ((cfg.get("agent", {}) or {}).get("acp_backend")) or ""
    try:
        options = await asyncio.to_thread(_backend_options_sync)
    except Exception:  # noqa: BLE001
        logger.warning("slack-channels-onboard: listing backends failed", exc_info=True)
        return {"supported": False, "options": [], "default": default, "refuses": False}
    return {"supported": True, "options": options, "default": default, "refuses": _backend_refuses()}


async def update_backend(channel_id: str, backend: Any) -> dict:
    """Pin (or un-pin, ``None``) the backend of the agent bound to *channel_id*.

    The pin lives on the AGENT, so every channel bound to the same agent moves
    with it; the response names them. Only a backend the gateway allows AND that
    is installed can be pinned: the gateway refuses a session on any other.
    """
    if not _backend_field_supported():
        raise ValueError("this gateway does not support a per-agent backend yet")
    if backend is not None and not isinstance(backend, str):
        raise ValueError("backend must be a string or null")
    cfg = config_dict()
    binding = ((cfg.get("slack", {}) or {}).get("channels", {}) or {}).get(channel_id)
    if binding is None:
        raise ValueError(f"channel {channel_id} is not onboarded")
    agent_name = binding.get("agent", "")
    if not agent_name or agent_name not in (cfg.get("agents", {}) or {}):
        raise ValueError("channel is not bound to an agent; cannot pin its backend")
    if backend is not None:
        options = {o["id"]: o for o in await asyncio.to_thread(_backend_options_sync)}
        if backend not in options:
            raise ValueError(f"backend {backend!r} is not allowed by this gateway")
        if options[backend]["installed"] == "missing":
            raise ValueError(f"backend {options[backend]['label']!r} is not installed on the gateway host")
    await _write(lambda d: core.set_agent_backend(d, agent_name, backend))
    shared = core.channels_for_agent(cfg, agent_name)
    shown = "inherit" if backend is None else (backend or "kiro")
    _audit("backend_update", f"agent={agent_name} backend={shown} channels={','.join(shared)}")
    logger.info("slack-channels-onboard: agent %s acp_backend=%s", agent_name, shown)
    return {"channel_id": channel_id, "agent": agent_name, "acp_backend": backend, "channels": shared}


def access_capabilities() -> dict:
    """Which per-user access controls the RUNNING gateway actually enforces.

    Stock Kiro Crew is owner-only on Slack: ``slack.allowed_users`` and
    ``channel-roles.json`` are inert there. The member / maintainer / open-channel
    / workspace-confinement gates exist only on a gateway carrying the matching
    patches, so each one is detected by the function it adds, never assumed. The
    UI shows the People section read-only (with this explanation) when the
    gateway cannot enforce it, instead of pretending a role means something.
    """
    def has(mod: str, *names: str) -> bool:
        try:
            m = importlib.import_module(mod)
        except Exception:  # noqa: BLE001
            return False
        return all(hasattr(m, n) for n in names)

    try:
        from kiro_crew.slack.handler_runtime import access as _acc  # type: ignore

        src = inspect.getsource(_acc.is_allowed_user)
        multi_user = "user_id in _allowed_users" in src
    except Exception:  # noqa: BLE001
        multi_user = False
    td = "kiro_crew.slack.transport_dispatch"
    caps = {
        "members": multi_user and has(td, "_kc_member_tool_allowed"),
        "maintainers": has(td, "_kc_is_channel_maintainer", "_kc_maintainer_tool_allowed"),
        "commands": has(td, "_kc_maintainer_cmd_approved"),
        "programs": has(td, "_kc_ask_owner_register"),
        "open_channel": has(td, "_kc_member_shell_ok"),
        "confinement": has("kiro_crew._kc_confine", "maybe_confine", "session_confined"),
    }
    caps["any"] = caps["members"]
    return caps


async def update_members(raw: Any) -> dict:
    """Replace the member allowlist, prune maintainers who left, hot-apply."""
    owner = owner_id()
    members = core.normalize_members(raw, owner)
    # Store the current Slack profile name so config.json stays readable; keep
    # the given name only when Slack cannot resolve the id.
    names = await _names([m["slack_id"] for m in members])
    for m in members:
        m["name"] = names.get(m["slack_id"]) or m["name"]
    member_ids = {m["slack_id"] for m in members}
    async with _ROLES_LOCK:
        roles = read_roles()  # raises on a corrupt file BEFORE anything is written
        await _write(lambda d: core.set_members(d, members))
        pruned = core.prune_roles(roles, member_ids)
        if pruned != roles:
            await asyncio.to_thread(_write_roles_sync, pruned)
    applied = _hot_apply_members(member_ids)
    _audit("members_update", f"members={len(members)} hot_applied={applied}")
    logger.info("slack-channels-onboard: allowlist now %d member(s), hot_applied=%s", len(members), applied)
    return {"members": members, "hot_applied": applied}


async def update_maintainers(channel_id: str, ids: Any) -> dict:
    cfg = config_dict()
    if channel_id not in ((cfg.get("slack", {}) or {}).get("channels", {}) or {}):
        raise ValueError(f"channel {channel_id} is not onboarded")
    member_ids = {m["slack_id"] for m in core.member_entries(cfg)}
    async with _ROLES_LOCK:
        new = core.set_maintainers(read_roles(), channel_id, ids, member_ids)
        await asyncio.to_thread(_write_roles_sync, new)
    got = (new["channels"].get(channel_id) or {}).get("maintainers", [])
    if got:
        await asyncio.to_thread(_ensure_ask_for_channel, channel_id)
    _audit("maintainers_update", f"channel={channel_id} maintainers={len(got)}")
    logger.info("slack-channels-onboard: %s maintainers=%d", channel_id, len(got))
    return {"channel_id": channel_id, "maintainers": got}


async def update_commands(channel_id: str, cmds: Any) -> dict:
    """Replace the approved maintainer commands of one onboarded channel."""
    cfg = config_dict()
    if channel_id not in ((cfg.get("slack", {}) or {}).get("channels", {}) or {}):
        raise ValueError(f"channel {channel_id} is not onboarded")
    async with _ROLES_LOCK:
        new = core.set_commands(read_roles(), channel_id, cmds)
        await asyncio.to_thread(_write_roles_sync, new)
    got = (new["channels"].get(channel_id) or {}).get("commands", [])
    _audit("commands_update", f"channel={channel_id} commands={','.join(got) or '-'}")
    logger.info("slack-channels-onboard: %s commands=%s", channel_id, got)
    return {"channel_id": channel_id, "commands": got}


async def update_open(channel_id: str, is_open: Any) -> dict:
    """Open/close one onboarded channel to every human member of it (read-only)."""
    cfg = config_dict()
    if channel_id not in ((cfg.get("slack", {}) or {}).get("channels", {}) or {}):
        raise ValueError(f"channel {channel_id} is not onboarded")
    async with _ROLES_LOCK:
        new = core.set_open(read_roles(), channel_id, is_open)
        await asyncio.to_thread(_write_roles_sync, new)
    got = (new["channels"].get(channel_id) or {}).get("open") is True
    if got:
        await asyncio.to_thread(_ensure_ask_for_channel, channel_id)
    _audit("open_update", f"channel={channel_id} open={got}")
    logger.info("slack-channels-onboard: %s open=%s", channel_id, got)
    return {"channel_id": channel_id, "open": got}


async def update_programs(channel_id: str, progs: Any) -> dict:
    """Replace the owner-approved extra programs of one onboarded channel."""
    cfg = config_dict()
    if channel_id not in ((cfg.get("slack", {}) or {}).get("channels", {}) or {}):
        raise ValueError(f"channel {channel_id} is not onboarded")
    async with _ROLES_LOCK:
        new = core.set_programs(read_roles(), channel_id, progs)
        await asyncio.to_thread(_write_roles_sync, new)
    got = (new["channels"].get(channel_id) or {}).get("programs", [])
    _audit("programs_update", f"channel={channel_id} programs={','.join(got) or '-'}")
    return {"channel_id": channel_id, "programs": got}


# Claude Code auto-allows Read/Grep/Glob inside the session cwd WITHOUT asking,
# so those reads never reach the gateway's non-owner gate (Set Q). Crew's
# per-session settings.local.json seed carries the ask rule (local Set Q2), but
# a second session in the same workspace gets no seed. A project-level
# .claude/settings.json covers every session there. Kept out of git with
# .git/info/exclude (local only, never committed).
_ASK_RULES = ("Bash", "Glob", "Grep", "Read")  # Bash: Claude Code auto-runs "read-only" Bash too


def ensure_claude_ask(ws_dir: str) -> bool:
    import contextlib
    import os
    import tempfile

    if not ws_dir:
        return False
    root = Path(ws_dir).expanduser()
    if not root.is_dir():
        return False
    path = root / ".claude" / "settings.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        if not isinstance(data, dict):
            return False
        perms = data.setdefault("permissions", {})
        if not isinstance(perms, dict):
            return False
        have = [a for a in perms.get("ask") or [] if isinstance(a, str)]
        if not set(_ASK_RULES) <= set(have):
            perms["ask"] = sorted(set(have) | set(_ASK_RULES))
            path.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix=".settings.", dir=str(path.parent))
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as fh:
                    json.dump(data, fh, indent=2)
                    fh.write("\n")
                os.replace(tmp, path)
            except BaseException:
                with contextlib.suppress(OSError):
                    os.unlink(tmp)
                raise
        exclude = root / ".git" / "info" / "exclude"
        if exclude.parent.is_dir():
            cur = exclude.read_text(encoding="utf-8") if exclude.exists() else ""
            if "/.claude/settings.json" not in cur.split("\n"):
                with exclude.open("a", encoding="utf-8") as fh:
                    fh.write(("" if cur.endswith("\n") or not cur else "\n") + "/.claude/settings.json\n")
        return True
    except Exception:  # noqa: BLE001 - best effort, reported by the caller
        logger.warning("slack-channels-onboard: could not write %s", path, exc_info=True)
        return False


def _ensure_ask_for_channel(channel_id: str) -> None:
    for row in core.channel_rows(config_dict(), []):
        if row["id"] == channel_id and row.get("workspace_dir"):
            ensure_claude_ask(row["workspace_dir"])

