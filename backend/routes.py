"""HTTP routes for slack-channels-onboard, served at /api/apps/slack-channels-onboard/<path>.

Every route is OWNER-ONLY (``require_owner_dashboard_request``): this app reads
the bot's Slack memberships and writes config.json, so neither another dashboard
user nor an app token may drive it.
"""

from __future__ import annotations

import logging
from typing import Any

from aiohttp import web

import importlib.util as _ilu
from pathlib import Path as _P

_spec = _ilu.spec_from_file_location(
    "_kirocrew_app_slack_channels_onboard_loader", _P(__file__).with_name("_load.py")
)
_loader = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_loader)
core = _loader.sibling("core")
gateway_ops = _loader.sibling("gateway_ops")

logger = logging.getLogger("kirocrew.app.slack-channels-onboard")

SETTINGS_KEY = "settings"


def load_settings(ctx: Any) -> dict:
    raw = ctx.storage.get(SETTINGS_KEY) if getattr(ctx, "storage", None) else None
    return core.normalize_settings(raw)


async def _owner(request: web.Request, op: str) -> web.Response | None:
    from kiro_crew.dashboard.handlers._shared import require_owner_dashboard_request

    return await require_owner_dashboard_request(request, f"slack_channels_onboard.{op}")


async def _body(request: web.Request) -> dict:
    try:
        data = await request.json()
    except Exception:  # noqa: BLE001
        return {}
    return data if isinstance(data, dict) else {}


def _err(msg: str, status: int = 400) -> web.Response:
    return web.json_response({"error": msg}, status=status)


async def get_channels(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "list")
    if denied is not None:
        return denied
    try:
        bot = await gateway_ops.bot_channels()
        slack_error = ""
    except Exception as exc:  # noqa: BLE001 - still show the configured ones
        bot, slack_error = [], str(exc)
    cfg = gateway_ops.config_dict()
    return web.json_response(
        {
            "channels": core.channel_rows(cfg, bot),
            "agents": sorted((cfg.get("agents") or {}).keys()),
            "settings": load_settings(ctx),
            "slack_error": slack_error,
        }
    )


async def post_onboard(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "onboard")
    if denied is not None:
        return denied
    body = await _body(request)
    channel_id = str(body.get("channel_id", "")).strip()
    if not channel_id:
        return _err("channel_id is required")
    settings = dict(load_settings(ctx))
    for key in ("activation", "thread_follow", "dedicated_memory"):
        if key in body:
            settings[key] = body[key]
    settings = core.normalize_settings(settings)
    try:
        result = await gateway_ops.onboard(
            channel_id,
            str(body.get("channel_name", "")),
            settings,
            name=body.get("name") or None,
            workspace_dir=body.get("workspace_dir") or None,
        )
    except ValueError as exc:
        return _err(str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: onboard failed")
        return _err(f"onboard failed: {exc}", 500)
    return web.json_response(result)


async def post_reconfigure(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "reconfigure")
    if denied is not None:
        return denied
    body = await _body(request)
    channel_id = str(body.get("channel_id", "")).strip()
    if not channel_id:
        return _err("channel_id is required")
    try:
        result = await gateway_ops.reconfigure(
            channel_id,
            workspace_dir=body.get("workspace_dir"),
            activation=body.get("activation"),
            thread_follow=body.get("thread_follow"),
        )
    except ValueError as exc:
        return _err(str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: reconfigure failed")
        return _err(f"reconfigure failed: {exc}", 500)
    return web.json_response(result)


async def get_settings(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "settings")
    if denied is not None:
        return denied
    return web.json_response(load_settings(ctx))


async def put_settings(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "settings")
    if denied is not None:
        return denied
    merged = core.normalize_settings({**load_settings(ctx), **(await _body(request))})
    ctx.storage.set(SETTINGS_KEY, merged)
    return web.json_response(merged)


# ------------------------------------------------------- people (slice 4)
# Members (slack.allowed_users) and per-channel maintainers (channel-roles.json).
# These grant access to the bot, so they are owner-only like everything else here
# and every write is SEL-audited by gateway_ops.


async def get_people(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "people")
    if denied is not None:
        return denied
    try:
        return web.json_response(await gateway_ops.people())
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: people failed")
        return _err(f"people failed: {exc}", 500)


async def post_resolve_user(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "resolve_user")
    if denied is not None:
        return denied
    uid = str((await _body(request)).get("slack_id", "")).strip()
    try:
        return web.json_response(await gateway_ops.resolve_user(uid))
    except ValueError as exc:
        return _err(str(exc))


def _unsupported(cap: str) -> web.Response | None:
    """409 when the running gateway cannot enforce *cap* (stock Kiro Crew is
    owner-only on Slack, so writing the role would only look like it did something)."""
    if gateway_ops.access_capabilities().get(cap):
        return None
    return _err(
        f"this Kiro Crew gateway does not enforce '{cap}' (stock Slack access is owner-only); "
        "see the app README, section 'People'",
        409,
    )


async def put_members(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "members")
    if denied is not None:
        return denied
    unsupported = _unsupported("members")
    if unsupported is not None:
        return unsupported
    body = await _body(request)
    try:
        return web.json_response(await gateway_ops.update_members(body.get("members")))
    except ValueError as exc:
        return _err(str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: members update failed")
        return _err(f"members update failed: {exc}", 500)


async def put_maintainers(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "maintainers")
    if denied is not None:
        return denied
    unsupported = _unsupported("maintainers")
    if unsupported is not None:
        return unsupported
    body = await _body(request)
    try:
        return web.json_response(
            await gateway_ops.update_maintainers(
                str(body.get("channel_id", "")).strip(), body.get("maintainers")
            )
        )
    except ValueError as exc:
        return _err(str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: maintainers update failed")
        return _err(f"maintainers update failed: {exc}", 500)


async def put_commands(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "commands")
    if denied is not None:
        return denied
    unsupported = _unsupported("commands")
    if unsupported is not None:
        return unsupported
    body = await _body(request)
    try:
        return web.json_response(
            await gateway_ops.update_commands(
                str(body.get("channel_id", "")).strip(), body.get("commands")
            )
        )
    except ValueError as exc:
        return _err(str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: commands update failed")
        return _err(f"commands update failed: {exc}", 500)


async def put_open(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "open")
    if denied is not None:
        return denied
    unsupported = _unsupported("open_channel")
    if unsupported is not None:
        return unsupported
    body = await _body(request)
    try:
        return web.json_response(
            await gateway_ops.update_open(str(body.get("channel_id", "")).strip(), body.get("open"))
        )
    except ValueError as exc:
        return _err(str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: open update failed")
        return _err(f"open update failed: {exc}", 500)


async def put_programs(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "programs")
    if denied is not None:
        return denied
    unsupported = _unsupported("programs")
    if unsupported is not None:
        return unsupported
    body = await _body(request)
    try:
        return web.json_response(
            await gateway_ops.update_programs(str(body.get("channel_id", "")).strip(), body.get("programs"))
        )
    except ValueError as exc:
        return _err(str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: programs update failed")
        return _err(f"programs update failed: {exc}", 500)


async def post_unbind(request: web.Request, ctx: Any) -> web.Response:
    denied = await _owner(request, "unbind")
    if denied is not None:
        return denied
    body = await _body(request)
    try:
        return web.json_response(await gateway_ops.unbind(str(body.get("channel_id", "")).strip()))
    except ValueError as exc:
        return _err(str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("slack-channels-onboard: unbind failed")
        return _err(f"unbind failed: {exc}", 500)


def register_routes(ctx: Any) -> list:
    from kiro_crew.apps.route_registry import AppRoute

    return [
        AppRoute(method="GET", path="/people", handler=get_people),
        AppRoute(method="POST", path="/resolve-user", handler=post_resolve_user),
        AppRoute(method="PUT", path="/members", handler=put_members),
        AppRoute(method="PUT", path="/maintainers", handler=put_maintainers),
        AppRoute(method="PUT", path="/commands", handler=put_commands),
        AppRoute(method="PUT", path="/open", handler=put_open),
        AppRoute(method="PUT", path="/programs", handler=put_programs),
        AppRoute(method="GET", path="/channels", handler=get_channels),
        AppRoute(method="POST", path="/onboard", handler=post_onboard),
        AppRoute(method="POST", path="/reconfigure", handler=post_reconfigure),
        AppRoute(method="POST", path="/unbind", handler=post_unbind),
        AppRoute(method="GET", path="/settings", handler=get_settings),
        AppRoute(method="PUT", path="/settings", handler=put_settings),
    ]
