"""Set T (_kc_workspace_confine_v1): per-channel OS confinement of the agent process.

Installed into the pipx venv as ``kiro_crew/_kc_confine.py`` by
``~/.kiro/crew/repatch-set-t-workspace-confine.sh``. Local patch, not upstream.

WHAT
    An agent process spawned for a Slack channel that has maintainers in
    ``~/.kiro/crew/channel-roles.json`` is started inside ``bwrap``:

    - the whole filesystem is READ-ONLY;
    - ``/home`` is replaced: ``$HOME`` is a per-workspace private home
      (``~/.local/state/kc-confine/<name>/home``) and only an allowlist of
      toolchain paths from the real home is mounted back, read-only (node/nvm,
      pipx, claude binary, .gitconfig ...). Secrets (~/.ssh, ~/.aws, ~/.config,
      ~/.zshrc, ~/.kiro, other workspaces, ...) simply do not exist inside;
    - the channel workspace is mounted READ-WRITE, plus the session scratch dir;
    - docker / lxd / dbus / snapd sockets, /run/user, /var/log, /etc/kirocrew
      are masked; private /tmp, PID and IPC namespaces (no /proc/<pid>/environ
      of the gateway, no killing host processes); no_new_privs (sudo dead).

    The process records ``host._kc_confined = (name, root)`` so the Slack tool
    gate can auto-approve a MAINTAINER's built-in tools in that session: the
    kernel, not a command parser, keeps them inside the workspace. Any spawn
    that is not verifiably confined keeps the old (strict) gate.

CLAUDE AUTH
    The confined claude gets its own ~/.claude (private home). Only the
    ``claudeAiOauth`` entry of the owner's ``~/.claude/.credentials.json`` is
    copied in (no MCP OAuth tokens). Sync runs at every launch and every 60 s:
    owner -> confined when the owner's token is newer; confined -> owner when the
    confined process refreshed (rotation would otherwise log the owner out), and
    ONLY after the new token is proven to belong to the same account
    (api/oauth/profile uuid == ~/.claude.json oauthAccount.accountUuid).
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import tempfile
import threading
import time
import urllib.request
from pathlib import Path
from typing import Any

logger = logging.getLogger("kiro_crew.kc_confine")

MARK = "_kc_workspace_confine_v1"
HOME = Path(os.path.expanduser("~"))
CREW = HOME / ".kiro" / "crew"
STATE = HOME / ".local" / "state" / "kc-confine"
BWRAP = shutil.which("bwrap") or "/usr/bin/bwrap"

# Real-home paths mounted back read-only (toolchains only; missing ones skipped).
HOME_ALLOW_RO = (
    ".local/bin",
    ".local/lib",
    ".local/share/claude",
    ".local/share/pipx",
    ".local/share/mise",
    ".local/share/pnpm",
    ".hermes/node",
    ".nvm",
    ".npm-packages",
    ".volta",
    ".toolbox/bin",
    ".yarn",
    ".config/yarn",
    ".tfenv",
    ".rvm",
    ".bun",
    ".cargo/bin",
    ".rustup",
    ".dotnet",
    "go/bin",
    ".gitconfig",
    ".kiro/crew/playwright-cli",
    ".cache/ms-playwright",
    # Kiro (kiro-cli / KAS) program files + the owner's agent specs/steering/skills.
    # NOT ~/.kiro/secrets.json, ~/.kiro/crew, ~/.kiro/sessions, data.sqlite3.
    ".local/share/kiro-cli/kas",
    ".local/share/kiro-cli/node",
    ".local/share/kiro-cli/bun",
    ".local/share/kiro-cli/run",
    ".local/share/kiro-cli/shell",
    ".local/share/kiro-cli/tui.js",
    ".kiro/agents",
    ".kiro/rendered-agents",
    ".kiro/settings",
    ".kiro/steering",
    ".kiro/skills",
    ".kiro/powers",
    ".kiro/extensions",
    ".kiro/hooks",
)
KIRO_DB = HOME / ".local" / "share" / "kiro-cli" / "data.sqlite3"
# Rows of the kiro-cli db copied into the private one: sign-in + profile only,
# never conversations/history (those hold every workspace's chats).
KIRO_STATE_KEYS = ("api.codewhisperer.profile", "auth.idc.region", "auth.idc.start-url",
                   "migration.kiro.completed", "migration.kiro.was_q_user", "profile.Migrated")
# Root-equivalent or cross-tenant endpoints, masked with /dev/null.
MASK_FILES = (
    "/run/docker.sock",
    "/run/containerd/containerd.sock",
    "/run/dbus/system_bus_socket",
    "/run/snapd.socket",
    "/run/snapd-snap.socket",
    "/var/snap/lxd/common/lxd/unix.socket",
)
MASK_DIRS = ("/var/log", "/run/log", "/etc/kirocrew", "/run/user", "/run/screen", "/mnt", "/media")
UNSET_ENV = (
    "SSH_AUTH_SOCK",
    "DBUS_SESSION_BUS_ADDRESS",
    "KIROCREW_STUB_SESSION_TOKEN",
    "KRB5CCNAME",
    "GH_TOKEN",
    "GITHUB_TOKEN",
)
# Roots too broad to ever be a "workspace".
_REFUSED_ROOTS = {"/", "/home", str(HOME), str(HOME / "Projects"), str(CREW), str(HOME / ".kiro")}


def _read_json(p: Path) -> Any:
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _inside(root: str, path: str) -> bool:
    return path == root or path.startswith(root.rstrip("/") + "/")


def channel_workspace(channel_id: str | None) -> tuple[str, str] | None:
    """(name, realpath root) when *channel_id* must run confined, else None."""
    if not channel_id:
        return None
    roles = _read_json(CREW / "channel-roles.json") or {}
    ent = (roles.get("channels") or {}).get(channel_id) or {}
    if ent.get("confine") is False:
        return None
    if not (ent.get("confine") is True or ent.get("maintainers")):
        return None
    cfg = _read_json(CREW / "config.json") or {}
    agent = ((cfg.get("slack") or {}).get("channels") or {}).get(channel_id, {}).get("agent")
    a = (cfg.get("agents") or {}).get(agent or "") or {}
    ws = a.get("workspace") or agent
    d = ((cfg.get("workspaces") or {}).get(ws or "") or {}).get("dir")
    if not d:
        return None
    root = os.path.realpath(os.path.expanduser(d))
    if root in _REFUSED_ROOTS or not os.path.isdir(root):
        logger.warning("Set T: refusing to confine channel %s to %r (too broad / missing)", channel_id, root)
        return None
    return str(ws), root


# ---------------------------------------------------------------- private home
def _atomic_write(p: Path, data: str, mode: int = 0o600) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(p.parent), prefix=p.name + ".kc.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, p)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def private_home(name: str) -> Path:
    safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in name) or "ws"
    h = STATE / safe / "home"
    (h / ".claude").mkdir(parents=True, exist_ok=True)
    os.chmod(STATE / safe, 0o700)
    settings = h / ".claude" / "settings.json"
    if not settings.exists():
        _atomic_write(settings, "{}\n")
    cj = h / ".claude.json"
    if not cj.exists():
        real = _read_json(HOME / ".claude.json") or {}
        seed = {k: real[k] for k in ("oauthAccount", "userID", "hasCompletedOnboarding",
                                     "lastOnboardingVersion", "installMethod") if k in real}
        seed.update({"autoUpdates": False, "numStartups": 1})
        _atomic_write(cj, json.dumps(seed, indent=2) + "\n")
    return h


_SYNC_LOCK = threading.Lock()


def _profile_uuid(token: str) -> str | None:
    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/profile",
        headers={"Authorization": "Bearer " + token, "anthropic-beta": "oauth-2025-04-20"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:  # noqa: S310 (fixed https URL)
            return (json.load(r).get("account") or {}).get("uuid")
    except Exception:  # noqa: BLE001
        return None


def sync_creds(home: Path) -> None:
    """Keep the confined claudeAiOauth and the owner's in step (see module doc)."""
    with _SYNC_LOCK:
        real_p = HOME / ".claude" / ".credentials.json"
        conf_p = home / ".claude" / ".credentials.json"
        real = _read_json(real_p) or {}
        conf = _read_json(conf_p) or {}
        r = real.get("claudeAiOauth") or {}
        c = conf.get("claudeAiOauth") or {}
        r_exp, c_exp = int(r.get("expiresAt") or 0), int(c.get("expiresAt") or 0)
        if c and c_exp > r_exp and c.get("accessToken") != r.get("accessToken"):
            want = ((_read_json(HOME / ".claude.json") or {}).get("oauthAccount") or {}).get("accountUuid")
            got = _profile_uuid(str(c.get("accessToken") or ""))
            if want and got == want:
                real["claudeAiOauth"] = c
                _atomic_write(real_p, json.dumps(real))
                logger.info("Set T: confined claude refreshed its token; synced back to owner")
            else:
                logger.warning("Set T: confined token newer but account unverified; NOT synced back")
            return
        if r and (r_exp > c_exp or not c):
            _atomic_write(conf_p, json.dumps({"claudeAiOauth": r}))


def _kiro_exp(rows: dict) -> str:
    try:
        return str(json.loads(rows.get("kirocli:odic:token") or "{}").get("expires_at") or "")
    except ValueError:
        return ""


def sync_kiro(home: Path) -> None:
    """Owner -> confined copy of kiro-cli's sign-in (auth_kv + profile rows).

    One-way only: whatever the confined process writes stays in its own db and
    never reaches the owner's (a maintainer could plant a token for ANOTHER
    account there, and the owner's chats would then go to that account).
    The copy is refreshed whenever the owner's token is newer.
    """
    import sqlite3

    if not KIRO_DB.exists():
        return
    with _SYNC_LOCK:
        dst = home / ".local" / "share" / "kiro-cli" / "data.sqlite3"
        dst.parent.mkdir(parents=True, exist_ok=True)
        src = sqlite3.connect(f"file:{KIRO_DB}?mode=ro", uri=True, timeout=5)
        try:
            auth = dict(src.execute("select key, value from auth_kv").fetchall())
            qs = ",".join("?" * len(KIRO_STATE_KEYS))
            state = src.execute(f"select key, value from state where key in ({qs})", KIRO_STATE_KEYS).fetchall()
            schema = [r[0] for r in src.execute(
                "select sql from sqlite_master where type='table' and sql is not null")]
        finally:
            src.close()
        d = sqlite3.connect(str(dst), timeout=5, uri=False)
        try:
            have = {r[0] for r in d.execute("select name from sqlite_master where type='table'")}
            if "auth_kv" not in have:
                for sql in schema:  # same schema, so kiro-cli skips its migrations
                    d.execute(sql)
            if "auth_kv" in have:
                cur = dict(d.execute("select key, value from auth_kv").fetchall())
                if _kiro_exp(cur) >= _kiro_exp(auth) and cur:
                    return
            d.execute("delete from auth_kv")
            d.executemany("insert into auth_kv(key, value) values(?, ?)", auth.items())
            d.executemany("insert or replace into state(key, value) values(?, ?)", state)
            # Bookkeeping tables, so kiro-cli does not re-run its migrations / re-extract KAS.
            for t in ("migrations", "pinned_bin_versions", "extracted_kas_versions"):
                try:
                    d.execute(f"attach database ? as owner", (f"file:{KIRO_DB}?mode=ro",))
                except sqlite3.OperationalError:
                    pass
                try:
                    d.execute(f"delete from main.{t}")
                    d.execute(f"insert into main.{t} select * from owner.{t}")
                except sqlite3.OperationalError:
                    logger.warning("Set T: could not copy kiro-cli table %s", t)
            try:
                d.execute("detach database owner")
            except sqlite3.OperationalError:
                pass
            d.commit()
        finally:
            d.close()
        os.chmod(dst, 0o600)


_SYNC_STARTED = False


def _sync_loop() -> None:
    while True:
        time.sleep(60)
        try:
            for d in STATE.glob("*/home"):
                sync_creds(d)
                sync_kiro(d)
        except Exception:  # noqa: BLE001
            logger.warning("Set T: credential sync failed", exc_info=True)


def _ensure_sync_thread() -> None:
    global _SYNC_STARTED
    if not _SYNC_STARTED:
        _SYNC_STARTED = True
        threading.Thread(target=_sync_loop, name="kc-confine-creds", daemon=True).start()


# ---------------------------------------------------------------- bwrap argv
def bwrap_argv(argv: list[str], root: str, home: Path, work_dir: str,
               writable: tuple[str, ...] = ()) -> list[str]:
    a = [BWRAP, "--die-with-parent", "--unshare-pid", "--unshare-ipc", "--unshare-uts",
         "--unshare-cgroup-try", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
         "--tmpfs", "/tmp", "--tmpfs", "/var/tmp"]
    for d in MASK_DIRS:
        if os.path.isdir(d):
            a += ["--tmpfs", d]
    for f in MASK_FILES:
        if os.path.exists(f):
            a += ["--ro-bind", "/dev/null", f]
    a += ["--tmpfs", "/home"]
    if os.path.isdir("/home/linuxbrew"):
        a += ["--ro-bind", "/home/linuxbrew", "/home/linuxbrew"]
    a += ["--bind", str(home), str(HOME)]
    for rel in HOME_ALLOW_RO:
        p = HOME / rel
        if p.exists():
            a += ["--ro-bind", str(p), str(p)]
    for w in writable:
        if w and os.path.isdir(w):
            a += ["--bind", w, w]
    a += ["--bind", root, root, "--chdir", work_dir,
          "--setenv", "HOME", str(HOME), "--setenv", "XDG_RUNTIME_DIR", "/tmp",
          "--setenv", "DISABLE_AUTOUPDATER", "1", "--setenv", "KC_CONFINED_ROOT", root]
    for k in UNSET_ENV:
        a += ["--unsetenv", k]
    return [*a, "--", *argv]


def maybe_confine(host: Any, argv: list[str], writable: tuple[str, ...] = ()) -> list[str]:
    """Called from acp/launch.py right after the Crew sandbox wrap (off-loop)."""
    host._kc_confined = None
    try:
        hit = channel_workspace(getattr(host, "_channel_id", None))
        if not hit:
            return argv
        name, root = hit
        work_dir = os.path.realpath(str(getattr(host, "_work_dir", "") or ""))
        if not _inside(root, work_dir):
            logger.warning("Set T: channel %s session cwd %s is outside %s — NOT confined (strict gate stays)",
                           getattr(host, "_channel_id", ""), work_dir, root)
            return argv
        if not os.access(BWRAP, os.X_OK):
            logger.warning("Set T: bwrap missing — NOT confined (strict gate stays)")
            return argv
        home = private_home(name)
        sync_creds(home)
        try:
            sync_kiro(home)
        except Exception:  # noqa: BLE001 — claude sessions do not need it
            logger.warning("Set T: kiro-cli sign-in copy failed", exc_info=True)
        _ensure_sync_thread()
        out = bwrap_argv(argv, root, home, work_dir, writable)
        host._kc_confined = (name, root)
        logger.info("Set T: agent for channel %s confined to %s", getattr(host, "_channel_id", ""), root)
        return out
    except Exception:  # noqa: BLE001 — never break a spawn; unconfined keeps the strict gate
        logger.warning("Set T: confinement setup failed — NOT confined", exc_info=True)
        host._kc_confined = None
        return argv


def session_confined(client: Any, channel: str) -> tuple[str, str] | None:
    """The (name, root) the session's LIVE process was confined to, if it matches *channel*."""
    inner = getattr(client, "_client", None)
    # claude: AcpProvider._client is the AcpClient (the launch host).
    # kiro-cli / KAS: AcpProvider._client is an AcpSessionProvider whose _runtime
    # (AcpRuntime) is the launch host; _kc_runtime is the copy Set T pinned.
    for obj in (client, inner, getattr(inner, "_runtime", None), getattr(client, "_kc_runtime", None)):
        conf = getattr(obj, "_kc_confined", None) if obj is not None else None
        if conf:
            hit = channel_workspace(channel)
            return conf if hit and hit[1] == conf[1] else None
    return None


def is_mcp_event(event: Any) -> bool:
    name = (getattr(event, "tool_name", "") or "")
    title = (getattr(event, "title", "") or "")
    return bool(getattr(event, "mcp_server_name", "")) or name.startswith("mcp__") or title.startswith("mcp__")



# ---------------------------------------------------------------- OPTIONS clicks
async def maintainer_options_as_message(orch: Any, payload: dict) -> bool:
    """A maintainer's OPTIONS click in a confined channel == typing the choice.

    Set O3 drops every interactive payload from a non-owner, because the stock
    OPTIONS handlers re-dispatch the turn with APPROVAL_INTERACTIVE and can route
    it into a dashboard slot (owner approvals, unconfined). Here the click is
    instead turned into an ordinary Slack message from that user in the thread and
    fed through the SAME entry a typed message takes (events._route_message): every
    admission, allowlist and maintainer gate runs, and the turn lands in the
    channel's confined session. Only plain OPTIONS controls (``options_choice_N``,
    ``options_submit``) qualify — never ``action::`` buttons, approvals, stop,
    dashboard-link or allowlist controls. Returns True when handled.
    """
    from kiro_crew.slack.format import (
        OPTIONS_ACTION_PREFIX,
        OPTIONS_SUBMIT_ACTION,
        build_options_selected_blocks,
        replace_options_blocks,
    )

    if payload.get("type") != "block_actions" or not orch or not getattr(orch, "slack", None):
        return False
    actions = payload.get("actions") or []
    if len(actions) != 1:
        return False
    action = actions[0]
    aid = str(action.get("action_id") or "")
    is_choice = aid.startswith(OPTIONS_ACTION_PREFIX) and "_done_" not in aid
    if not (is_choice or aid == OPTIONS_SUBMIT_ACTION):
        return False
    uid = (payload.get("user") or {}).get("id", "")
    channel = (payload.get("channel") or {}).get("id", "")
    msg = payload.get("message") or {}
    msg_ts = (payload.get("container") or {}).get("message_ts") or msg.get("ts", "")
    thread_ts = msg.get("thread_ts") or msg_ts
    if not (uid and channel and msg_ts):
        return False
    from kiro_crew.slack.transport_dispatch import _kc_is_channel_maintainer

    if not _kc_is_channel_maintainer(uid, channel) or not channel_workspace(channel):
        return False
    ds = getattr(orch, "dashboard_state", None)
    if ds is not None and getattr(ds, "get_linked_slot", None) and ds.get_linked_slot(thread_ts):
        return False  # a dashboard-owned thread stays owner-only
    blocks = msg.get("blocks") or []
    all_choices: list[str] = []
    for b in blocks:
        for el in (b.get("elements") or []) if b.get("type") == "actions" else []:
            eid = str(el.get("action_id") or "")
            if eid.startswith(OPTIONS_ACTION_PREFIX):
                all_choices.append(str(el.get("value") or ""))
            elif el.get("options"):
                all_choices = [str(o.get("value") or "") for o in el["options"]]
    if is_choice:
        choice = str(action.get("value") or (action.get("selected_option") or {}).get("value") or "")
        if choice.startswith("action::"):
            return False
        try:
            idx: Any = int(aid[len(OPTIONS_ACTION_PREFIX):])
        except ValueError:
            idx = all_choices.index(choice) if choice in all_choices else 0
        picked = [choice]
    else:
        picked = []
        for bv in ((payload.get("state") or {}).get("values") or {}).values():
            for st in bv.values():
                picked += [str(o.get("value") or "") for o in st.get("selected_options") or []]
        idx = [i for i, c in enumerate(all_choices) if c in set(picked)]
    picked = [p for p in picked if p]
    if not picked:
        return False
    from kiro_crew.security import redact_credentials, redact_exfiltration_urls

    text = ", ".join(redact_credentials(redact_exfiltration_urls(p)[0])[0] for p in picked)
    # Spend the control so nobody can click it again, then echo the answer.
    from kiro_crew.slack.outbound import claim_options_answer, settle_options_answer

    if not claim_options_answer(channel, msg_ts):
        return True  # already answered: swallow the duplicate
    try:
        new_blocks = replace_options_blocks(blocks, build_options_selected_blocks(all_choices, idx))
        await orch.slack.update_message(channel, msg_ts, text=text, blocks=new_blocks)
        settle_options_answer(channel, msg_ts)
    except Exception:  # noqa: BLE001
        logger.debug("Set T: could not mark OPTIONS control answered", exc_info=True)
    new_ts = await orch.slack.post_message(channel, f"<@{uid}>: {text}", thread_ts)
    if not new_ts:
        return True
    from kiro_crew.slack.events import SeenCache, _route_message

    event = {"type": "message", "user": uid, "channel": channel, "text": text,
             "thread_ts": thread_ts, "ts": new_ts, "team": (payload.get("team") or {}).get("id", "")}
    logger.info("Set T: maintainer %s OPTIONS click in %s routed as a typed message", uid, channel)
    await _route_message(orch, event, SeenCache(), is_mention=True)
    return True
