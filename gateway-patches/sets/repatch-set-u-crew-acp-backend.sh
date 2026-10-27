#!/usr/bin/env bash
# ============================================================================
# Set U — per-crew ACP backend pin: agents.<name>.acp_backend (2026-10-21).
#
# Goal: a channel's agent runs on the harness pinned on ITS crew record
# (e.g. erp-dental on kas, monitor-team on claude) instead of the one
# install-wide agent.acp_backend.
#
# Upstream: issue kirodotdev/KiroCrew#21910, PR #16200 (backend half) and
# PR #11324 (dashboard selector) — both OPEN and conflicting with main when
# this was written. Same key and blank rule as those PRs, so the config this
# Set reads is the config upstream will read:
#   absent / null -> inherit (member-DM route, then agent.acp_backend)
#   ""            -> kiro-cli explicitly
#   "<id>"        -> that backend
# Once an installed release carries the field (KiroCrewAgentConfig already has
# `acp_backend`), this Set no-ops and can be retired.
#
# Deliberate divergences from PR #16200:
#   - REFUSE, never degrade. A pin that is not selectable (unknown id, denied
#     by policy) or whose harness is not installed refuses the session start
#     with a clear message posted in the thread, instead of silently running
#     the crew on kiro-cli (#21910 asks for this). Silent fallback would put a
#     maintainer channel on a harness whose tool names its rules were never
#     checked against.
#   - Member DM threads keep the member route (agent.member_acp_backend): the
#     member dispatch mount (context._member_backend_can_dispatch) is not
#     taught about the pin here, so pinning there could mount dispatch tools
#     on a harness that cannot carry them.
#   - Only the provider factory honours the pin. The cold-slot capability
#     probes (chat_runner /todos and /compact, chat_handlers slot caps,
#     session_control set_model) still read the gateway default for a session
#     that has no live process yet; a live session answers from its provider.
#
# A changed pin applies to NEW sessions/threads; a live thread keeps the
# harness it was started on.
#
# Edits (marker _kc_crew_acp_backend_v1, idempotent, anchor-checked):
#   - config/sections.py      KiroCrewAgentConfig.acp_backend (str | None)
#   - config/loader.py        parse it; KiroCrewConfig.crew_acp_backend();
#                             factory passes crew_backend into the gate
#   - members.py              select_provider_backend(crew_backend=) + refusal
#   - session.py              agents.*.acp_backend edit refreshes the factory
#   - session_allocation.py   a pinned crew never takes a warm-pool child
#   - messaging/dispatch.py   a refused pin is posted in the thread
# Rollback: restore the *.bak-setu-<stamp> files next to each edited file,
# clear __pycache__, restart the gateway.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set U: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python 2>/dev/null || command -v python3)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import pathlib, py_compile, re, shutil, sys

site = pathlib.Path(sys.argv[1])
stamp = sys.argv[2]
MARK = "_kc_crew_acp_backend_v1"

files = {
    "sections": site / "config/sections.py",
    "loader": site / "config/loader.py",
    "members": site / "members.py",
    "session": site / "session.py",
    "alloc": site / "session_allocation.py",
    "dispatch": site / "messaging/dispatch.py",
}
src = {k: p.read_text() for k, p in files.items()}

MARK2 = "_kc_crew_acp_backend_v2"
v1_done = MARK in src["members"]
if MARK2 in src["loader"]:
    print("Set U (crew acp_backend): already applied — no-op")
    sys.exit(0)

# Upstream shipped the field: its own gate owns the pin from here on.
cls = src["sections"].split("class KiroCrewAgentConfig:", 1)
if not v1_done and len(cls) == 2 and re.search(
    r"\n    acp_backend: ", cls[1].split("\n@dataclass", 1)[0]
):
    print("Set U (crew acp_backend): field shipped upstream in installed release — no-op")
    sys.exit(0)


def sub_once(key, old, new, label, stage=1):
    # Stage 1 (v1) edits are skipped on a site that already carries them, so
    # a v1-patched install upgrades in place to v2.
    if stage == 1 and v1_done:
        return
    n = src[key].count(old)
    if n != 1:
        print(f"Set U: anchor '{label}' found {n}x in {files[key].name} — CHECK ANCHORS")
        sys.exit(1)
    src[key] = src[key].replace(old, new, 1)


def sub_alt(key, alts, label, stage=1):
    """sub_once over layout variants: the first (old, new) whose anchor is unique wins."""
    if stage == 1 and v1_done:
        return
    for old, new in alts:
        if src[key].count(old) == 1:
            src[key] = src[key].replace(old, new, 1)
            return
    print(f"Set U: anchor '{label}' found {[src[key].count(o) for o, _ in alts]}x in {files[key].name} — CHECK ANCHORS")
    sys.exit(1)


# 1) sections.py — the field, right after reasoning_effort on the crew record.
anchor = (
    '            "reasoning-capable models accept a level; on any other model the pin "\n'
    '            "is ignored, exactly as the global default is.",\n'
    "        ),\n"
    "    )\n"
)
sub_once(
    "sections",
    anchor,
    anchor
    + "    # _kc_crew_acp_backend_v1 (Set U)\n"
    + "    acp_backend: str | None = field(\n"
    + "        default=None,\n"
    + "        metadata=_meta(\n"
    + '            "Crew ACP backend",\n'
    + "            \"Backend for this crew's sessions. Null inherits the session default; \"\n"
    + '            "an empty string selects kiro-cli explicitly.",\n'
    + "        ),\n"
    + "    )\n",
    "KiroCrewAgentConfig.reasoning_effort",
)

# 2a) loader.py — parse. Kept raw (any string); selectability is the gate's call.
anchor = '                    reasoning_effort=coerce_effort(crew.get("reasoning_effort")),\n'
sub_once(
    "loader",
    anchor,
    anchor
    + "                    # _kc_crew_acp_backend_v1 (Set U): raw pin, null = inherit.\n"
    + "                    acp_backend=(\n"
    + '                        entry.get("acp_backend")\n'
    + '                        if isinstance(entry.get("acp_backend"), str)\n'
    + "                        else None\n"
    + "                    ),\n",
    "agents parse reasoning_effort",
)

# 2b) loader.py — lookup keyed on the same crew identity as the effort pin.
anchor = (
    '        """The ``config.agents`` record this session runs as, or ``None``."""\n'
    "        key = resolve_crew_identity(self, agent, crew_agent)\n"
    "        return self.agents.get(key) if key else None\n"
)
sub_once(
    "loader",
    anchor,
    anchor
    + "\n"
    + "    def crew_acp_backend(self, agent: str | None, crew_agent: str | None = None) -> str | None:\n"
    + '        """The ACP backend THIS CREW pins, or ``None`` (Set U).\n'
    + "\n"
    + "        ``\"\"`` is a real pin (kiro-cli), so callers test ``is not None``.\n"
    + '        """\n'
    + "        crew = self._crew_record(agent, crew_agent)\n"
    + '        return getattr(crew, "acp_backend", None) if crew is not None else None\n',
    "_crew_record",
)

# 2c) loader.py — the factory hands the crew's pin to the one selection gate.
#     0.10.0 added ``backend_override=`` (spawn_run(backend=...)) to the call.
_CREW_KW = (
    "                # A pooled child has no session key and must stay on the\n"
    "                # default backend; pinned crews bypass the pool instead.\n"
    "                crew_backend=(\n"
    "                    self.crew_acp_backend(agent, crew_agent) if session_key else None\n"
    "                ),\n"
    "                crew_name=crew_agent or \"\",\n"
)
_CALL = (
    "            _backend = select_provider_backend(\n"
    "                session_key,\n"
    "                self.agent.member_acp_backend,\n"
    "                self.agent.acp_backend,\n"
)
sub_alt(
    "loader",
    [
        (_CALL + "                backend_override=backend_override,\n            )\n",
         _CALL + "                backend_override=backend_override,\n" + _CREW_KW + "            )\n"),
        (_CALL + "            )\n", _CALL + _CREW_KW + "            )\n"),
    ],
    "factory select_provider_backend",
)

# 3) members.py — the gate. Pin first (non-member sessions), refusal on a pin
#    that cannot run, then the unchanged member route / configured default.
anchor = (
    "def select_provider_backend(\n"
    "    session_key: str | None,\n"
    "    member_backend: str,\n"
    "    configured_default: str,\n"
    ") -> str:\n"
)
_SIG_10 = anchor.replace(
    "    configured_default: str,\n", "    configured_default: str,\n    backend_override: str | None = None,\n"
)
_SIG_NEW_TAIL = (
    "    crew_backend: str | None = None,\n"
    "    crew_name: str = \"\",\n"
    ") -> str:\n"
)
_KC_GATE = (
    "class CrewBackendRefused(RuntimeError):\n"
    '    """A crew\'s pinned ACP backend cannot run here (Set U, _kc_crew_acp_backend_v1).\n'
    "\n"
    "    Raised instead of degrading to kiro-cli: a crew pinned to one harness must\n"
    "    never quietly run on another. ``_kc_user_notice`` is the text the transport\n"
    "    posts in the thread (messaging/dispatch.py).\n"
    '    """\n'
    "\n"
    "    def __init__(self, notice: str) -> None:\n"
    "        super().__init__(notice)\n"
    "        self._kc_user_notice = notice\n"
    "\n"
    "\n"
    "def _kc_check_crew_backend(pin: str, crew_name: str) -> str:\n"
    '    """Return *pin* when it can run, else raise :class:`CrewBackendRefused`."""\n'
    "    from kiro_crew.acp_backends import selectable_backends\n"
    "\n"
    "    label = pin or \"kiro\"\n"
    "    setting = f\"agents.{crew_name}.acp_backend\" if crew_name else \"agents.<name>.acp_backend\"\n"
    "    if pin not in selectable_backends():\n"
    "        raise CrewBackendRefused(\n"
    "            f\"This channel's agent is pinned to the '{label}' backend ({setting}), \"\n"
    "            \"which this gateway does not allow. The message was not run. Ask the \"\n"
    "            \"owner to pick another backend for this agent.\"\n"
    "        )\n"
    "    try:\n"
    "        from kiro_crew.agent_sdk.backend_install import probe_backend\n"
    "\n"
    "        state = probe_backend(pin)\n"
    "    except Exception:\n"
    "        logger.debug(\"backend probe failed for %r; letting the spawn decide\", pin, exc_info=True)\n"
    "        return pin\n"
    "    if getattr(state, \"installed\", \"\") == \"missing\":\n"
    "        missing = \", \".join(getattr(state, \"missing_components\", ()) or ()) or label\n"
    "        raise CrewBackendRefused(\n"
    "            f\"This channel's agent is pinned to the '{label}' backend ({setting}), \"\n"
    "            f\"but it is not installed on the gateway host (missing: {missing}). \"\n"
    "            \"The message was not run. Ask the owner to install it or pick another \"\n"
    "            \"backend for this agent.\"\n"
    "        )\n"
    "    return pin\n"
    "\n"
    "\n"
)
sub_alt(
    "members",
    [
        (_SIG_10, _KC_GATE + _SIG_10[: -len(") -> str:\n")] + _SIG_NEW_TAIL),
        (anchor, _KC_GATE + anchor[: -len(") -> str:\n")] + _SIG_NEW_TAIL),
    ],
    "select_provider_backend signature",
)
# The crew pin ranks below an explicit spawn_run(backend=...) override (0.10.0)
# and above the member-DM route's neighbour, the configured default.
_PIN_ARM = (
    "    # Set U: the crew's own pin outranks the configured default, never the\n"
    "    # member-DM route (see the Set U header for why).\n"
    "    if crew_backend is not None and not is_member_session_key(session_key):\n"
    "        try:\n"
    "            backend = _kc_check_crew_backend(crew_backend, crew_name)\n"
    "        except CrewBackendRefused as exc:\n"
    "            logger.warning(\"session %s: crew backend pin refused: %s\", session_key, exc)\n"
    "            raise\n"
    "        logger.info(\n"
    "            \"session %s: routing to acp_backend=%r (agents.%s.acp_backend)\",\n"
    "            session_key,\n"
    "            backend,\n"
    "            crew_name or \"?\",\n"
    "        )\n"
    "        return backend\n"
)
_MEMBER_ARM = "    if is_member_session_key(session_key):\n        backend = resolve_selected_backend(member_backend)\n"
_OLD_BODY = (
    "    from kiro_crew.acp_backends import resolve_selected_backend\n"
    "\n"
    "    if is_member_session_key(session_key):\n"
)
sub_alt(
    "members",
    [
        (_OLD_BODY, "    from kiro_crew.acp_backends import resolve_selected_backend\n\n" + _PIN_ARM
         + "    if is_member_session_key(session_key):\n"),
        (_MEMBER_ARM, _PIN_ARM + _MEMBER_ARM),
    ],
    "select_provider_backend body",
)

# 4) session.py — a pin edit rebuilds the factory (it captured the old config).
anchor = (
    "        if change.touched(*self._FACTORY_CONFIG_PATHS):\n"
    "            await self.refresh_defaults(cfg=change.new)\n"
)
sub_once(
    "session",
    anchor,
    "        if change.touched(*self._FACTORY_CONFIG_PATHS) or any(\n"
    "            # _kc_crew_acp_backend_v1 (Set U): per-crew factory input.\n"
    "            p.endswith(\".acp_backend\") or p == \"agents\" or p.count(\".\") == 1\n"
    "            for p in change.under(\"agents\")\n"
    "        ):\n"
    "            await self.refresh_defaults(cfg=change.new)\n",
    "apply_config_change factory paths",
)

# 5) session_allocation.py — a pooled child runs the default backend, so a
#    pinned crew always cold-starts through the factory (where the pin applies).
anchor = "        elif await self._crew_pins_effort(agent, extra_factory_kwargs.get(\"crew_agent\")):\n"
sub_once(
    "alloc",
    anchor,
    "        elif await self._kc_crew_pins_backend(agent, extra_factory_kwargs.get(\"crew_agent\")):\n"
    "            # _kc_crew_acp_backend_v1 (Set U)\n"
    "            pool_decision = \"bypass_backend\"\n"
    + anchor,
    "warm pool crew effort arm",
)
anchor = "    async def _crew_pins_effort(self, agent: str | None, crew_agent: object) -> bool:\n"
sub_once(
    "alloc",
    anchor,
    "    async def _kc_crew_pins_backend(self, agent: str | None, crew_agent: object) -> bool:\n"
    '        """True when the crew pins its own ACP backend (Set U).\n'
    "\n"
    "        Failure answers True: a wrong False hands a pinned crew a pooled child on\n"
    "        the default backend; a wrong True only costs a cold start.\n"
    '        """\n'
    "        try:\n"
    "            config = await asyncio.to_thread(self._deps.load_config)\n"
    "            crew = crew_agent if isinstance(crew_agent, str) else None\n"
    "            return config.crew_acp_backend(agent, crew) is not None\n"
    "        except Exception:\n"
    "            self._deps.logger.warning(\n"
    "                \"Could not read the crew backend pin for agent=%r; cold-starting\",\n"
    "                agent,\n"
    "                exc_info=True,\n"
    "            )\n"
    "            return True\n"
    "\n" + anchor,
    "_crew_pins_effort def",
)

# 6) messaging/dispatch.py — say WHY in the thread instead of a bare error.
anchor = (
    "        except Exception as exc:\n"
    '            logger.exception("%s transport_dispatch: error handling message", channel)\n'
    "            verdict = Verdict.FAILED\n"
)
sub_once(
    "dispatch",
    anchor,
    anchor
    + "            # _kc_crew_acp_backend_v1 (Set U): a refused crew backend pin is\n"
    + "            # an answer for the user, posted where the reply would have gone.\n"
    + "            _kc_notice, _kc_e, _kc_seen = \"\", exc, 0\n"
    + "            while _kc_e is not None and _kc_seen < 8 and not _kc_notice:\n"
    + "                _kc_notice = getattr(_kc_e, \"_kc_user_notice\", \"\") or \"\"\n"
    + "                _kc_e = _kc_e.__cause__ or _kc_e.__context__\n"
    + "                _kc_seen += 1\n"
    + "            if _kc_notice:\n"
    + "                try:\n"
    + "                    await renderer.on_text_chunk(_kc_notice)\n"
    + "                    await renderer.on_done()\n"
    + "                except Exception:\n"
    + "                    logger.warning(\"%s: crew backend notice not posted\", channel, exc_info=True)\n",
    "dispatch generic except",
)

# ---- v2 (_kc_crew_acp_backend_v2) -----------------------------------------
# A Slack CHANNEL turn hands the factory the bound kiro mode as ``agent``
# (e.g. "kirocrew") and no ``crew_agent``, so resolve_crew_identity answers ""
# and v1 never saw the pin. Recover the crew from the channel's own binding
# (slack.channels.<id>.agent) when the identity is empty, in the factory AND
# in the warm-pool bypass.
sub_once(
    "loader",
    "    def crew_acp_backend(self, agent: str | None, crew_agent: str | None = None) -> str | None:\n"
    '        """The ACP backend THIS CREW pins, or ``None`` (Set U).\n'
    "\n"
    "        ``\"\"`` is a real pin (kiro-cli), so callers test ``is not None``.\n"
    '        """\n'
    "        crew = self._crew_record(agent, crew_agent)\n",
    "    def _kc_session_crew(\n"
    "        self, agent: str | None, crew_agent: str | None = None, channel_id: str | None = None\n"
    "    ) -> \"tuple[str, KiroCrewAgentConfig | None]\":\n"
    '        """(name, record) of the crew a session runs as (Set U, _kc_crew_acp_backend_v2).\n'
    "\n"
    "        A Slack channel turn passes the bound KIRO mode as ``agent`` and no\n"
    "        ``crew_agent``, so the identity resolves empty; the channel's binding\n"
    "        (``slack.channels.<id>.agent``) names the crew instead.\n"
    '        """\n'
    "        name = resolve_crew_identity(self, agent, crew_agent)\n"
    "        if not name and channel_id:\n"
    "            binding = (getattr(self, \"slack_channels\", None) or {}).get(channel_id)\n"
    "            bound = getattr(binding, \"agent\", \"\") if binding is not None else \"\"\n"
    "            if bound and bound in self.agents:\n"
    "                name = bound\n"
    "        return name, (self.agents.get(name) if name else None)\n"
    "\n"
    "    def crew_acp_backend(\n"
    "        self, agent: str | None, crew_agent: str | None = None, channel_id: str | None = None\n"
    "    ) -> str | None:\n"
    '        """The ACP backend THIS CREW pins, or ``None`` (Set U).\n'
    "\n"
    "        ``\"\"`` is a real pin (kiro-cli), so callers test ``is not None``.\n"
    '        """\n'
    "        crew = self._kc_session_crew(agent, crew_agent, channel_id)[1]\n",
    "crew_acp_backend v2",
    stage=2,
)
sub_once(
    "loader",
    "                    self.crew_acp_backend(agent, crew_agent) if session_key else None\n"
    "                ),\n"
    "                crew_name=crew_agent or \"\",\n",
    "                    self.crew_acp_backend(agent, crew_agent, channel_id) if session_key else None\n"
    "                ),\n"
    "                crew_name=self._kc_session_crew(agent, crew_agent, channel_id)[0],\n",
    "factory crew pin v2",
    stage=2,
)
sub_once(
    "alloc",
    "        elif await self._kc_crew_pins_backend(agent, extra_factory_kwargs.get(\"crew_agent\")):\n",
    "        elif await self._kc_crew_pins_backend(\n"
    "            agent, extra_factory_kwargs.get(\"crew_agent\"), channel_id\n"
    "        ):\n",
    "pool arm v2",
    stage=2,
)
sub_once(
    "alloc",
    "    async def _kc_crew_pins_backend(self, agent: str | None, crew_agent: object) -> bool:\n",
    "    async def _kc_crew_pins_backend(\n"
    "        self, agent: str | None, crew_agent: object, channel_id: str | None = None\n"
    "    ) -> bool:\n",
    "pool helper signature v2",
    stage=2,
)
sub_once(
    "alloc",
    "            return config.crew_acp_backend(agent, crew) is not None\n",
    "            return config.crew_acp_backend(agent, crew, channel_id) is not None\n",
    "pool helper body v2",
    stage=2,
)

for key, path in files.items():
    shutil.copy2(path, path.with_name(path.name + f".bak-setu-{stamp}"))
    path.write_text(src[key])
ok = True
for path in files.values():
    try:
        py_compile.compile(str(path), doraise=True)
    except py_compile.PyCompileError as exc:
        ok = False
        print(f"Set U: compile FAILED {path}: {exc}")
if not ok:
    for key, path in files.items():
        shutil.copy2(path.with_name(path.name + f".bak-setu-{stamp}"), path)
    print("Set U: rolled back")
    sys.exit(1)
print("Set U (crew acp_backend, v2): OK")
PY
