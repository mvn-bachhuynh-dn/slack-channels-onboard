#!/usr/bin/env bash
# ============================================================================
# Set P2 — per-channel APPROVED COMMANDS for maintainers (approved 2026-10-20).
#
# Extends Set P. The owner approves command ids per channel in
# $KIROCREW_HOME/channel-roles.json:
#   {"channels": {"C0XXXXXXXXX": {"maintainers": ["U0..."],
#                                  "commands": ["typecheck", "lint", ...]}}}
# A maintainer shell call whose WHOLE command line matches approved ids runs
# WITHOUT a prompt ("auto_approve"), still behind the deny-list/keystone hook.
# Anything else falls back to Set P / O2 (deny).
#
# Command ids (exact token shapes; see _kc_cmd_segment_id):
#   typecheck      npx tsc --noEmit [-p|--project <file in ws>]
#   lint           npm run lint
#   build          npm run build | npm run build:frontend
#                  (refused while any CSS in the ws has @plugin/@config —
#                   Tailwind would execute maintainer-written JS at build)
#   deploy         npm run deploy | npm run deploy:api | npx wrangler deploy [--dry-run]
#   git-write      git add <paths in ws|-A|-u> | git commit -m <msg> [-a] [-s]
#                  | git checkout -b <br> | git switch [-c] <br>
#                  | git push [-u] origin <br>   (br != main/master/HEAD, no :/+)
#   gh-pr          gh pr create [title/body/base/head/draft/fill/label/...]
#                  | gh pr view|list|checks|diff|status [...]  (no --repo/--web/-F)
#   wrangler-tail  npx wrangler tail [...]  (no --config)
# Grammar: optional `rtk` prefix, `cd <dir in ws> &&`, `&&` chaining, and a
# trailing `2>&1` / `| tail|head [-n] N`. Quotes are honoured; any other shell
# metacharacter, env assignment, glob, $, backtick or newline => no match.
# npx needs the binary in a local node_modules/.bin (else npx would fetch).
# Never approvable: npm install/ci, db:*:remote, wrangler d1, anything else.
#
# Because approved commands EXECUTE workspace files, P2 also locks maintainer
# writes to build/tooling config: package.json, lockfiles, wrangler.*,
# vite/vitest/postcss/tailwind/babel/eslint/... config, .oxlintrc*, tsconfig*,
# jsconfig*, and the .wrangler/ dir (on top of Set P's deny list).
#
# Requires Set P. Idempotent via marker _kc_maintainer_commands_v1.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set P2: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_maintainer_commands_v1"
p = site / "slack/transport_dispatch.py"
s = p.read_text()
if MARK in s:
    print("Set P2: already applied — no-op")
else:
    if "_kc_channel_maintainer_v1" not in s:
        print("Set P2: FAIL — Set P not present; apply P first"); sys.exit(1)
    edits = [
        (
            "            # Set P (_kc_channel_maintainer_v1): a channel maintainer gets scoped write + git reads.\n"
            "            if (\n"
            "                not _kc_is_owner(user_id)\n"
            "                and not _kc_member_tool_allowed(event)\n",
            f"            # Set P2 ({MARK}): approved maintainer commands run without a prompt.\n"
            "            _kc_auto = not _kc_is_owner(user_id) and _kc_maintainer_cmd_approved(\n"
            "                event, user_id, channel, agent_override, gateway, getattr(client, \"cwd\", None)\n"
            "            )\n"
            "            # Set P (_kc_channel_maintainer_v1): a channel maintainer gets scoped write + git reads.\n"
            "            if (\n"
            "                not _kc_is_owner(user_id)\n"
            "                and not _kc_auto\n"
            "                and not _kc_member_tool_allowed(event)\n",
        ),
        (
            "            if result.action == TOOL_AUTO_APPROVE:\n"
            "                return \"auto_approve\"\n"
            "            return \"\"\n"
            "\n"
            "        # ── Drive the turn",
            "            if result.action == TOOL_AUTO_APPROVE:\n"
            "                return \"auto_approve\"\n"
            f"            return \"auto_approve\" if _kc_auto else \"\"  # Set P2 ({MARK})\n"
            "\n"
            "        # ── Drive the turn",
        ),
        (
            "    if name in _KC_DENY_DIRS:\n"
            "        return False\n"
            "    return True\n",
            "    if name in _KC_DENY_DIRS:\n"
            "        return False\n"
            f"    if _kc_build_config_locked(parts):  # Set P2 ({MARK})\n"
            "        return False\n"
            "    return True\n",
        ),
    ]
    for old, _new in edits:
        if s.count(old) != 1:
            print(f"Set P2: FAIL anchor count={s.count(old)} for {old[:60]!r} — re-derive"); sys.exit(1)
    for old, new in edits:
        s = s.replace(old, new)
    s += r'''

# ---------------------------------------------------------------------------
# Set P2 (''' + MARK + r'''): per-channel approved maintainer commands. See
# ~/.kiro/crew/repatch-set-p2-maintainer-commands.sh for the full contract.
# ---------------------------------------------------------------------------
KC_MAINTAINER_COMMAND_IDS = (
    "typecheck", "lint", "build", "deploy", "git-write", "gh-pr", "wrangler-tail"
)
_KC_LOCK_DIRS = frozenset({".wrangler"})
_KC_LOCK_EXACT = frozenset(
    {"package.json", "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml",
     "pnpm-workspace.yaml", "bun.lock", "bun.lockb", "wrangler.toml", "wrangler.json",
     "wrangler.jsonc", ".nvmrc", ".node-version"}
)
_KC_LOCK_PREFIXES = (
    "vite.config.", "vitest.config.", "postcss.config.", "tailwind.config.", "babel.config.",
    "eslint.config.", ".eslintrc", ".oxlintrc", "oxlint.config", ".postcssrc", ".babelrc",
    "svelte.config.", "astro.config.", "next.config.", "nuxt.config.", "rollup.config.",
    "webpack.config.", "esbuild.config.", "jest.config.", "playwright.config.", "tsconfig",
    "jsconfig", "vercel.json", "netlify.toml",
)
_KC_OUT_META = frozenset(";&|<>(){}$`\\*?[]~#!\n\r")
_KC_DQ_META = frozenset("$`\\\n\r")
_KC_BRANCH_RE = __import__("re").compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$")
_KC_CSS_EXEC_RE = __import__("re").compile(rb"@(plugin|config)\b")


def _kc_build_config_locked(parts: Any) -> bool:
    """True when a relpath (split parts) is build/tooling config approved commands execute."""
    if any(part in _KC_LOCK_DIRS for part in parts):
        return True
    low = parts[-1].lower()
    return low in _KC_LOCK_EXACT or low.startswith(_KC_LOCK_PREFIXES)


def _kc_channel_commands(channel: str) -> frozenset:
    """Approved command ids for *channel*. Fail closed (empty) on any error."""
    try:
        import json

        data = json.loads(_kc_roles_path().read_text(encoding="utf-8"))
        entry = ((data or {}).get("channels") or {}).get(channel) or {}
        cmds = entry.get("commands") or []
        return frozenset(c for c in cmds if c in KC_MAINTAINER_COMMAND_IDS)
    except Exception:
        return frozenset()


def _kc_cmd_lex(cmd: str) -> Any:
    """Quote-aware lexer: list of ("w", word) / ("op", "&&"|"|"|"2>&1"), or None."""
    out: list = []
    word: list = []
    has = False
    i, n = 0, len(cmd)

    def flush() -> None:
        nonlocal word, has
        if has:
            out.append(("w", "".join(word)))
        word, has = [], False

    while i < n:
        ch = cmd[i]
        if ch in " \t":
            flush()
            i += 1
        elif ch == "'":
            j = cmd.find("'", i + 1)
            if j < 0 or any(c in "\n\r" for c in cmd[i + 1 : j]):
                return None
            word.append(cmd[i + 1 : j])
            has = True
            i = j + 1
        elif ch == '"':
            j = cmd.find('"', i + 1)
            if j < 0 or any(c in _KC_DQ_META for c in cmd[i + 1 : j]):
                return None
            word.append(cmd[i + 1 : j])
            has = True
            i = j + 1
        elif cmd.startswith("&&", i):
            flush()
            out.append(("op", "&&"))
            i += 2
        elif ch == "|" and not cmd.startswith("||", i):
            flush()
            out.append(("op", "|"))
            i += 1
        elif not has and cmd.startswith("2>&1", i) and (i + 4 == n or cmd[i + 4] in " \t"):
            out.append(("op", "2>&1"))
            i += 4
        elif ch in _KC_OUT_META:
            return None
        else:
            word.append(ch)
            has = True
            i += 1
    flush()
    return out


def _kc_cmd_segments(cmd: str) -> Any:
    """Split into `&&` segments of words, allowing a trailing 2>&1 / | tail|head N."""
    toks = _kc_cmd_lex(cmd)
    if not toks:
        return None
    segs: list = []
    cur: list = []
    i = 0
    while i <= len(toks):
        if i == len(toks) or toks[i] == ("op", "&&"):
            if not cur:
                return None
            segs.append(cur)
            cur = []
            i += 1
            continue
        kind, val = toks[i]
        if kind == "w":
            cur.append(val)
            i += 1
            continue
        if val == "2>&1":
            i += 1
            continue
        # val == "|": only `tail|head [-n] N` may follow, then end or `&&`.
        j = i + 1
        rest = []
        while j < len(toks) and toks[j][0] == "w":
            rest.append(toks[j][1])
            j += 1
        ok = (
            len(rest) in (2, 3)
            and rest[0] in ("tail", "head")
            and (
                (len(rest) == 2 and rest[1].startswith("-") and rest[1][1:].isdigit())
                or (len(rest) == 3 and rest[1] == "-n" and rest[2].isdigit())
            )
        )
        if not ok or not cur or (j < len(toks) and toks[j] != ("op", "&&")):
            return None
        i = j
    return segs


def _kc_ws_path(arg: str, cwd: str, root: str) -> Any:
    """realpath of *arg* (relative to *cwd*) when inside *root* and not denied; else None."""
    import os

    real = os.path.realpath(arg if os.path.isabs(arg) else os.path.join(cwd, arg))
    if not _kc_inside(root, real):
        return None
    if real != root:
        parts = os.path.relpath(real, root).split(os.sep)
        if any(p in _KC_DENY_DIRS or p in _KC_LOCK_DIRS for p in parts):
            return None
    return real


def _kc_has_local_bin(cwd: str, root: str, name: str) -> bool:
    import os

    d = cwd
    while True:
        if os.path.isfile(os.path.join(d, "node_modules", ".bin", name)):
            return True
        if d == root or not _kc_inside(root, d):
            return False
        d = os.path.dirname(d)


def _kc_css_exec_free(root: str) -> bool:
    """No CSS in the workspace carries @plugin/@config (Tailwind executes those). Fail closed."""
    import os

    skip = set(_KC_DENY_DIRS) | set(_KC_LOCK_DIRS) | {"dist", "build", ".artifacts"}
    seen = 0
    try:
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if d not in skip]
            for fn in fns:
                if fn.lower().endswith((".css", ".pcss", ".scss", ".sass", ".less")):
                    seen += 1
                    if seen > 5000:
                        return False
                    with open(os.path.join(dp, fn), "rb") as fh:
                        if _KC_CSS_EXEC_RE.search(fh.read(2_000_000)):
                            return False
        return True
    except Exception:
        return False


def _kc_git_write_ok(args: list, cwd: str, root: str) -> bool:
    if not args:
        return False
    sub, rest = args[0], args[1:]
    if sub == "add":
        if not rest:
            return False
        for a in rest:
            if a in ("-A", "--all", "-u", "--update", "--"):
                continue
            if a.startswith("-"):
                return False  # -f/--force, -p, --chmod, ...
            if _kc_ws_path(a, cwd, root) is None:
                return False
            low = a.rstrip("/").rsplit("/", 1)[-1].lower()
            if low.startswith(".env") or low.endswith(_KC_DENY_SUFFIXES):
                return False
        return True
    if sub == "commit":
        has_msg, i = False, 0
        while i < len(rest):
            a = rest[i]
            if a in ("-m", "--message", "-am"):
                if i + 1 >= len(rest):
                    return False
                has_msg, i = True, i + 2
                continue
            if a.startswith("--message="):
                has_msg, i = True, i + 1
                continue
            if a in ("-a", "--all", "-s", "--signoff", "-q", "--quiet"):
                i += 1
                continue
            return False  # --amend, -F, --no-verify, --template, -c, paths, ...
        return has_msg
    if sub in ("checkout", "switch"):
        flag = "-b" if sub == "checkout" else "-c"
        if sub == "checkout" and (len(rest) != 2 or rest[0] != "-b"):
            return False
        if sub == "switch" and not (len(rest) == 1 or (len(rest) == 2 and rest[0] == flag)):
            return False
        return bool(_KC_BRANCH_RE.match(rest[-1]))
    if sub == "push":
        pos = [a for a in rest if a not in ("-u", "--set-upstream")]
        if any(a.startswith("-") for a in pos) or len(pos) != 2 or pos[0] != "origin":
            return False
        br = pos[1]
        return bool(_KC_BRANCH_RE.match(br)) and br not in ("main", "master", "HEAD")
    return False


_KC_GH_CREATE_VAL = frozenset(
    {"--title", "-t", "--body", "-b", "--base", "-B", "--head", "-H", "--label", "-l",
     "--assignee", "-a", "--reviewer", "-r", "--milestone", "-m", "--project", "-p"}
)
_KC_GH_CREATE_BARE = frozenset({"--draft", "-d", "--fill", "-f", "--fill-first", "--fill-verbose"})


def _kc_gh_pr_ok(args: list) -> bool:
    if len(args) < 2 or args[0] != "pr":
        return False
    sub, rest = args[1], args[2:]
    if any(a.startswith(("--repo", "-R", "--web", "-w")) for a in rest):
        return False  # another repo / opening a browser
    if sub == "create":  # unknown flags (--body-file, -F, --template, --editor, ...) fall through to deny
        i = 0
        while i < len(rest):
            a = rest[i]
            key = a.split("=", 1)[0]
            if key in _KC_GH_CREATE_VAL:
                i += 1 if "=" in a else 2
                if i > len(rest):
                    return False
                continue
            if a in _KC_GH_CREATE_BARE:
                i += 1
                continue
            return False
        return True
    return sub in ("view", "list", "checks", "diff", "status")


def _kc_cmd_segment_id(words: list, cwd: str, root: str) -> Any:
    """Command id one segment matches, "cd:<dir>" for a cd, or None."""
    if words and words[0] == "rtk":
        words = words[1:]
    if not words:
        return None
    w0 = words[0]
    if w0 == "cd":
        if len(words) != 2:
            return None
        d = _kc_ws_path(words[1], cwd, root)
        import os

        return f"cd:{d}" if d and os.path.isdir(d) else None
    if w0 == "npm":
        if len(words) == 3 and words[1] == "run":
            return {
                "lint": "lint", "build": "build", "build:frontend": "build",
                "deploy": "deploy", "deploy:api": "deploy",
            }.get(words[2])
        return None
    if w0 == "npx" and len(words) >= 2:
        tool, rest = words[1], words[2:]
        if not _kc_has_local_bin(cwd, root, tool):
            return None
        if tool == "tsc":
            if "--noEmit" not in rest:
                return None
            i = 0
            while i < len(rest):
                if rest[i] == "--noEmit":
                    i += 1
                elif rest[i] in ("-p", "--project") and i + 1 < len(rest):
                    if _kc_ws_path(rest[i + 1], cwd, root) is None:
                        return None
                    i += 2
                else:
                    return None
            return "typecheck"
        if tool == "wrangler" and rest:
            if rest[0] == "deploy" and all(a == "--dry-run" for a in rest[1:]):
                return "deploy"
            if rest[0] == "tail" and not any(a.startswith(("--config", "-c")) for a in rest[1:]):
                return "wrangler-tail"
        return None
    if w0 == "git":
        return "git-write" if _kc_git_write_ok(words[1:], cwd, root) else None
    if w0 == "gh":
        return "gh-pr" if _kc_gh_pr_ok(words[1:]) else None
    return None


def _kc_approved_cmd_ids(cmd: str, root: str) -> Any:
    """Ids a whole command line needs (cd segments excluded), or None when unmatched."""
    segs = _kc_cmd_segments(cmd or "")
    if not segs:
        return None
    cwd, ids = root, []
    for words in segs:
        cid = _kc_cmd_segment_id(words, cwd, root)
        if cid is None:
            return None
        if cid.startswith("cd:"):
            cwd = cid[3:]
            continue
        if cid == "build" and not _kc_css_exec_free(root):
            return None
        ids.append(cid)
    return ids or None


def _kc_maintainer_cmd_approved(
    event: Any, user_id: str, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any
) -> bool:
    """A maintainer shell call made ONLY of this channel's approved commands. Deny on doubt."""
    import os

    if not getattr(event, "is_shell", False):
        return False
    if not _kc_is_channel_maintainer(user_id, channel):
        return False
    approved = _kc_channel_commands(channel)
    if not approved:
        return False
    _ka, ws = _agent_workspace_binding(gateway, channel_agent)
    if not ws or not session_cwd:
        return False
    root = os.path.realpath(os.path.expanduser(ws))
    if os.path.realpath(os.path.expanduser(str(session_cwd))) != root or root == os.sep:
        return False
    cmd = getattr(event, "shell_command", None) or ""
    ids = _kc_approved_cmd_ids(cmd, root)
    if not ids or not set(ids) <= approved:
        return False
    sel().log_api_access(
        caller=user_id,
        operation="slack.channel_maintainer_cmd",
        outcome="allowed",
        source="slack",
        resources=f"channel={channel} ids={','.join(ids)} cmd={cmd[:200]}",
    )
    return True
'''
    shutil.copy2(p, p.with_name(p.name + f".bak-setp2-{stamp}"))
    p.write_text(s)
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()
    print("Set P2: patched slack/transport_dispatch.py")

import importlib
TD = importlib.import_module("kiro_crew.slack.transport_dispatch")
for n in ("_kc_maintainer_cmd_approved", "_kc_approved_cmd_ids", "_kc_build_config_locked", "KC_MAINTAINER_COMMAND_IDS"):
    assert hasattr(TD, n), n
print("Set P2: OK (imports + names verified)")
PY
