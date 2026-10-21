"""Lifecycle hooks: the background detector (slice 2).

Every ``poll_secs`` the detector lists the channels the bot is in, finds those
with no ``slack.channels`` binding, and (when ``require_owner_member``) keeps
only the ones the owner is also a member of. Then, by ``mode``:

* ``auto``   -> onboard the channel and DM the owner what was created;
* ``notify`` -> DM the owner once per channel that it is waiting;
* ``off``    -> do nothing.

A channel that failed to onboard is retried on the next poll at most
``_MAX_ATTEMPTS`` times, then reported once and left for the page.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

import importlib.util as _ilu
from pathlib import Path as _P

_spec = _ilu.spec_from_file_location(
    "_kirocrew_app_slack_channels_onboard_loader", _P(__file__).with_name("_load.py")
)
_loader = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_loader)
core = _loader.sibling("core")
gateway_ops = _loader.sibling("gateway_ops")
load_settings = _loader.sibling("routes").load_settings

logger = logging.getLogger("kirocrew.app.slack-channels-onboard")

_STATE_KEY = "detector_state"
_MAX_ATTEMPTS = 3
_FIRST_DELAY_SECS = 30
_task: asyncio.Task | None = None


def _state(ctx: Any) -> dict:
    raw = ctx.storage.get(_STATE_KEY) if getattr(ctx, "storage", None) else None
    raw = raw if isinstance(raw, dict) else {}
    return {"notified": dict(raw.get("notified", {})), "attempts": dict(raw.get("attempts", {}))}


def _save(ctx: Any, state: dict) -> None:
    ctx.storage.set(_STATE_KEY, state)


async def scan_once(ctx: Any) -> list[str]:
    """One detector pass. Returns a short log of what it did."""
    settings = load_settings(ctx)
    if settings["mode"] == "off":
        return []
    pending = core.pending_channels(gateway_ops.config_dict(), await gateway_ops.bot_channels())
    if not pending:
        return []
    owner = gateway_ops.owner_id()
    state = _state(ctx)
    done: list[str] = []
    for ch in pending:
        cid, cname = ch["id"], ch.get("name", "")
        if settings["require_owner_member"] and not await gateway_ops.channel_has_member(
            cid, owner
        ):
            continue
        if settings["mode"] == "notify":
            if cid not in state["notified"]:
                await gateway_ops.dm_owner(
                    f":inbox_tray: The bot was added to #{cname} ({cid}) but it has no agent yet. "
                    "Open Dashboard → Slack Channels Onboard to create one."
                )
                state["notified"][cid] = True
                done.append(f"notified {cid}")
            continue
        attempts = int(state["attempts"].get(cid, 0))
        if attempts >= _MAX_ATTEMPTS:
            continue
        try:
            r = await gateway_ops.onboard(cid, cname, settings)
        except Exception as exc:  # noqa: BLE001
            state["attempts"][cid] = attempts + 1
            logger.warning("slack-channels-onboard: auto-onboard %s failed: %s", cid, exc)
            if attempts + 1 >= _MAX_ATTEMPTS:
                await gateway_ops.dm_owner(
                    f":warning: Could not onboard #{cname} ({cid}) automatically: {exc}. "
                    "Do it by hand in Dashboard → Slack Channels Onboard."
                )
            continue
        state["attempts"].pop(cid, None)
        done.append(f"onboarded {cid}")
        await gateway_ops.dm_owner(
            f":white_check_mark: Onboarded #{cname} → agent `{r['name']}`\n"
            f"• workspace: `{r['workspace_dir']}`\n"
            f"• memory: `{r['memory_store']}`\n"
            f"• activation: `{r['binding']['activation']}`, thread_follow: "
            f"`{r['binding']['thread_follow']}`\n"
            "Change it in Dashboard → Slack Channels Onboard (e.g. point the workspace at an existing repo)."
        )
    _save(ctx, state)
    return done


async def _loop(ctx: Any) -> None:
    await asyncio.sleep(_FIRST_DELAY_SECS)
    while True:
        try:
            for line in await scan_once(ctx):
                logger.info("slack-channels-onboard: %s", line)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 - keep the detector alive
            logger.warning("slack-channels-onboard: detector pass failed: %s", exc)
        await asyncio.sleep(load_settings(ctx)["poll_secs"])


async def on_startup(ctx: Any) -> None:
    global _task
    if _task is not None and not _task.done():
        return
    _task = asyncio.get_running_loop().create_task(_loop(ctx), name="slack-channels-onboard-detector")
    logger.info("slack-channels-onboard: detector started")


async def on_shutdown(ctx: Any) -> None:
    global _task
    task, _task = _task, None
    if task is not None and not task.done():
        task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Exception):  # noqa: BLE001
            pass
    logger.info("slack-channels-onboard: detector stopped")
