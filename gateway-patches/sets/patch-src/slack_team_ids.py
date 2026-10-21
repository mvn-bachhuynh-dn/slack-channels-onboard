"""Slack channel -> workspace (team) id, for an agent child's environment.

An agent spawned for a Slack conversation carries ``KIROCREW_CHANNEL_ID``; a hook
that opens the conversation (``slack://channel?team=<TEAM>&id=<CHANNEL>``) also
needs the workspace the channel lives in, so the spawn adds
``KIROCREW_SLACK_TEAM_ID`` beside it.

Two sources, in this order:

1. the channel's HOME workspace, recorded by ``RealSlackClient.record_channel_team``
   from ``conversations.info``'s ``context_team_id`` -- the same canonical answer
   the outbound ``team_id`` routing uses. An inbound event's ``team`` field is NOT
   a source: it names the AUTHOR's workspace, which on a Slack Connect shared
   channel is not the workspace the channel lives in;
2. the bot's own workspace from the startup ``auth.test``
   (``slack.enterprise.validate_enterprise``): ``team_id``, else the org-level
   ``enterprise_id`` on an Enterprise Grid org install. Used only for an id that
   is spelled like a Slack conversation id, so a Discord or Telegram channel id
   never inherits a Slack workspace.

The value is a public workspace identifier, not a credential. Lives in
``slack/`` but imports nothing Slack-specific, so the ACP spawn path can read it
without pulling the Slack client in.
"""

from __future__ import annotations

import re
from typing import MutableMapping

#: The child-environment variable carrying the workspace id.
SLACK_TEAM_ID_ENV = "KIROCREW_SLACK_TEAM_ID"

# Slack conversation ids: C (public), G (private / legacy group), D (DM).
_CHANNEL_ID_RE = re.compile(r"^[CGD][A-Z0-9]{2,}$")
# Workspace ``T…`` or Enterprise Grid org ``E…``.
_TEAM_ID_RE = re.compile(r"^[TE][A-Z0-9]{2,}$")
# A bound on the per-process cache: one entry per conversation the bot answered.
_MAX_CHANNELS = 20_000

_channel_team: dict[str, str] = {}
_default_team = ""


def record_channel_team(channel: str, team_id: str) -> None:
    """Remember *channel*'s home workspace. Malformed ids are ignored."""
    if not (isinstance(channel, str) and _CHANNEL_ID_RE.match(channel)):
        return
    if not (isinstance(team_id, str) and _TEAM_ID_RE.match(team_id)):
        return
    if channel not in _channel_team and len(_channel_team) >= _MAX_CHANNELS:
        _channel_team.clear()
    _channel_team[channel] = team_id


def set_default_team(team_id: str) -> None:
    """Set (or, with ``""``, clear) the bot's own workspace from ``auth.test``."""
    global _default_team
    _default_team = team_id if isinstance(team_id, str) and _TEAM_ID_RE.match(team_id) else ""


def slack_team_id_for(channel_id: str | None) -> str:
    """The workspace id for a Slack *channel_id*, or ``""`` when unknown / not Slack."""
    if not (isinstance(channel_id, str) and _CHANNEL_ID_RE.match(channel_id)):
        return ""
    return _channel_team.get(channel_id) or _default_team


def apply_slack_team_env(env: MutableMapping[str, str], channel_id: str | None) -> None:
    """Set ``KIROCREW_SLACK_TEAM_ID`` for *channel_id*, or remove it when unknown.

    Removing matters as much as setting: the child env starts from the gateway's
    own, so a stale value there must never name a workspace for a session that
    has none.
    """
    team = slack_team_id_for(channel_id)
    if team:
        env[SLACK_TEAM_ID_ENV] = team
    else:
        env.pop(SLACK_TEAM_ID_ENV, None)


def _reset_for_tests() -> None:
    global _default_team
    _channel_team.clear()
    _default_team = ""
