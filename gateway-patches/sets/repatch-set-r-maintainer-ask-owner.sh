#!/usr/bin/env bash
# ============================================================================
# Set R — a maintainer's missing permission is ASKED of the owner in Slack, and
#         "always" becomes a rule stored in channel-roles.json (2026-10-20).
#
# Before: a maintainer tool call outside Sets P/P2/P3 was a hard deny, and the
# rules were partly hardcoded (P3 built-ins). Now:
#   1. Gate (slack/transport_dispatch.py _tool_gate): when a MAINTAINER of the
#      channel (session cwd = channel workspace) hits something not allowed,
#      the verdict is "ask_owner" instead of "deny" — unless the keystone /
#      deny-list hook denies it (that stays final). Plain members still get deny.
#   2. Driver (messaging/driver.py): "ask_owner" ALWAYS posts the approval card
#      and waits for a click, whatever agent.approval_mode is (auto/trust/YOLO
#      and per-session Trust never answer it). No decider => deny.
#   3. Card (slack/renderer.py): "🔐 <@owner> maintainer <@U> needs …" with
#      [Cho phép 1 lần] [Luôn cho phép: <rule>] [Từ chối]. The middle button is
#      shown only when a durable rule can be derived:
#        - a known command family that is merely not approved -> its command id
#          (typecheck, lint, build, deploy, git-write, gh-pr, wrangler-tail,
#          fs, ls, git-read)
#        - an unknown program -> "program: <name>" (path args must still stay
#          inside the workspace and not name secrets; never offered for shells,
#          interpreters, network/remote, package managers, privilege tools).
#      Path/secret failures (e.g. reading GCP_SA_KEY.json) only get "1 lần".
#   4. Click (slack/interactions.py): only the owner can press (Set O3).
#      "Luôn cho phép" approves AND appends the rule to channels.<C>.commands /
#      channels.<C>.programs; it never grants per-session Trust. SEL:
#      slack.maintainer_ask_owner, slack.maintainer_rule_added.
#   5. P3 built-ins become ordinary command ids (fs, ls, git-read) so every
#      maintainer right is visible/editable in the Channel Onboard app.
#   6. Shell grammar widened: `;`, `||`, `|` between checked segments,
#      redirection only to /dev/null (or 2>&1); read-only text tools (cat head
#      tail wc grep(-r refused) sort uniq cut diff stat file du find(no
#      -exec/-delete)) join the "ls" family; a pipe target with no file args is
#      a free filter.
#
# Requires Sets O2, P, P2, P3, Q. Idempotent via marker _kc_maintainer_ask_owner_v1.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set R: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_maintainer_ask_owner_v1"

plans = []  # (path, new_text) — computed for all files first, written only if all anchors hold


def plan(rel, needs, edits, tail=""):
    p = site / rel
    s = p.read_text()
    if MARK in s:
        print(f"Set R: {rel} already applied — no-op")
        return
    for n in needs:
        if n not in s:
            print(f"Set R: FAIL — {rel} lacks {n}; apply prerequisite Sets first"); sys.exit(1)
    # An edit is (old, new) or a list of alternative (old, new) pairs, tried in
    # order (release layouts differ); the first whose anchor is unique wins.
    for item in edits:
        alts = item if isinstance(item, list) else [item]
        pick = next(((o, n) for o, n in alts if s.count(o) == 1), None)
        if pick is None:
            o = alts[0][0]
            print(f"Set R: FAIL {rel} anchor count={s.count(o)} for {o[:70]!r} — re-derive"); sys.exit(1)
        s = s.replace(pick[0], pick[1])
    plans.append((p, s + tail))


def _kc_driver_alts(edits):
    """0.9.0+: the hook_deny branch steers + rejects after its log and the gate runs
    off-loop; insert the ask_owner branch right before the auto_approve branch."""
    (o, n), = edits
    anchor = '                    if _gate == "auto_approve":\n'
    return [[(o, n), (anchor, n[len(o):] + anchor)]]


# ------------------------------------------------------------ 2. driver
plan(
    "messaging/driver.py",
    [],
    _kc_driver_alts([(
        "                                f\"mode={self.approval_mode} reason=hook_deny\"\n"
        "                            ),\n"
        "                        )\n"
        "                        continue\n",
        "                                f\"mode={self.approval_mode} reason=hook_deny\"\n"
        "                            ),\n"
        "                        )\n"
        "                        continue\n"
        f"                    # Set R ({MARK}): the owner must click, whatever the approval mode.\n"
        "                    if _gate == \"ask_owner\":\n"
        "                        _kc_ok = False\n"
        "                        if self.decider is not None:\n"
        "                            _kc_tcid = str(getattr(event, \"tool_call_id\", \"\") or \"\")\n"
        "                            await self.renderer.dispatch(\n"
        "                                OutputEvent(\n"
        "                                    kind=PROMPT_CHOICE,\n"
        "                                    options=[\n"
        "                                        {k: _redact(v) if isinstance(v, str) else v for k, v in o.items()}\n"
        "                                        for o in (event.options or [])\n"
        "                                    ],\n"
        "                                    request_id=event.request_id,\n"
        "                                    title=_redact(getattr(event, \"title\", \"\") or \"\"),\n"
        "                                    tool_purpose=tool_purposes.get(_kc_tcid, \"\"),\n"
        "                                    tool_input=_redact(getattr(event, \"tool_input\", \"\") or \"\"),\n"
        "                                )\n"
        "                            )\n"
        "                            _kc_ok = bool(await self.decider(event))\n"
        "                        if _kc_ok:\n"
        "                            _kc_sent = await self.provider.approve_tool(event.request_id)\n"
        "                            _kc_out = \"approved\" if _kc_sent is not False else OUTCOME_REJECTED_TRANSPORT_FLOOR\n"
        "                        else:\n"
        "                            _kc_out = \"denied\"\n"
        "                            await self._steer_deny_cause(event)\n"
        "                            await self.provider.reject_tool(event.request_id)\n"
        "                        sel().log_api_access(\n"
        "                            caller=\"turn_driver\",\n"
        "                            operation=\"tool_permission\",\n"
        "                            outcome=_kc_out,\n"
        "                            source=\"messaging\",\n"
        "                            resources=f\"request_id={event.request_id} mode={self.approval_mode} reason=ask_owner\",\n"
        "                        )\n"
        "                        continue\n",
    )]),
)

# ------------------------------------------------------------ 3. card
plan(
    "slack/renderer.py",
    [],
    [(
        "    key = _approval_registry_key(session_key, request_id)\n"
        "    token = build_approval_token(session_key, request_id, nonce)\n"
        "    return [\n",
        "    key = _approval_registry_key(session_key, request_id)\n"
        "    token = build_approval_token(session_key, request_id, nonce)\n"
        f"    _kc_ask = _KC_ASK_OWNER.get(key)  # Set R ({MARK})\n"
        "    if _kc_ask is not None:\n"
        "        return _kc_ask_owner_blocks(title, key, token, _kc_ask)\n"
        "    return [\n",
    )],
    r'''

# ---------------------------------------------------------------------------
# Set R (''' + MARK + r'''): approval card for a maintainer request. The
# registry is written by the gate (transport_dispatch) and read/popped by the
# click handler (interactions); keyed like the approval registry.
# ---------------------------------------------------------------------------
_KC_ASK_OWNER: dict = {}
_KC_ASK_OWNER_MAX = 500


def _kc_ask_owner_blocks(title: str, key: str, token: str, ask: dict) -> list:
    owner = ask.get("owner") or ""
    who = f"<@{ask.get('user')}>" if ask.get("user") else "maintainer"
    head = (f"<@{owner}> " if owner else "") + f"🔐 Maintainer {who} cần quyền: *{title}*"
    rule = ask.get("rule_label") or ""
    if rule:
        head += f"\nNếu chọn *Luôn cho phép*, quy tắc `{rule}` được lưu cho channel này (xem/gỡ trong app Channel Onboard)."
    else:
        head += "\n(Không tạo được quy tắc lâu dài cho lệnh này — chỉ cho phép 1 lần.)"
    buttons = [{
        "type": "button", "text": {"type": "plain_text", "text": "Cho phép 1 lần"}, "style": "primary",
        "action_id": f"{TOOL_APPROVE_ACTION_PREFIX}{key}", "value": token,
    }]
    if rule:
        buttons.append({
            "type": "button", "text": {"type": "plain_text", "text": f"Luôn cho phép: {rule}"[:75]},
            "action_id": f"{TOOL_TRUST_ACTION_PREFIX}{key}", "value": token,
        })
    buttons.append({
        "type": "button", "text": {"type": "plain_text", "text": "Từ chối"}, "style": "danger",
        "action_id": f"{TOOL_DENY_ACTION_PREFIX}{key}", "value": token,
    })
    return [{"type": "section", "text": {"type": "mrkdwn", "text": head}},
            {"type": "actions", "elements": buttons}]
''',
)

# ------------------------------------------------------------ 4. click
plan(
    "slack/interactions.py",
    ["_kc_member_no_escalation_v1"],
    [
        (
            "        if is_trust:\n            sess_key = SlackApprovalDecider.session_for(approval_key, nonce=press_nonce)\n",
            f"        # Set R ({MARK}): a maintainer request — 'always' stores a rule, never session Trust.\n"
            "        _kc_persisted = \"\"\n"
            "        from kiro_crew.slack import renderer as _kc_rmod\n"
            "        _kc_entry = _kc_rmod._KC_ASK_OWNER.get(approval_key)\n"
            "        if _kc_entry is not None:\n"
            "            if is_trust and is_owner(user_id) and SlackApprovalDecider.session_for(approval_key, nonce=press_nonce):\n"
            "                from kiro_crew.slack.transport_dispatch import _kc_add_maintainer_rule\n"
            "                _kc_persisted = _kc_add_maintainer_rule(_kc_entry, user_id)\n"
            "                if not _kc_persisted:\n"
            "                    approved = False  # could not store the rule: fail closed\n"
            "            is_trust = False\n"
            "            _kc_rmod._KC_ASK_OWNER.pop(approval_key, None)\n"
            "        if is_trust:\n            sess_key = SlackApprovalDecider.session_for(approval_key, nonce=press_nonce)\n",
        ),
        (
            "        sel().log_api_access(\n            caller=user_id,\n            operation=\"slack.transport_tool_approval\",\n            outcome=outcome,\n",
            "        if _kc_persisted and resolved:  # Set R\n"
            "            label = f\"🔓 Đã cho phép và ghi nhớ cho maintainer: {_kc_persisted}\"\n"
            "            outcome = \"approved_rule_added\"\n"
            "        sel().log_api_access(\n            caller=user_id,\n            operation=\"slack.transport_tool_approval\",\n            outcome=outcome,\n",
        ),
    ],
)

# ------------------------------------------------------------ 1/5/6. gate + grammar
plan(
    "slack/transport_dispatch.py",
    ["_kc_open_channel_v1", "_kc_maintainer_file_ops_v1"],
    [
        (
            "        decider = (\n            SlackApprovalDecider(session_key=session_key)\n"
            "            if approval_mode == APPROVAL_INTERACTIVE\n            else None\n        )\n",
            f"        # Set R ({MARK}): always build the decider — a maintainer request asks the owner\n"
            "        # even when approval_mode is auto (the driver only uses it on ask_owner / interactive).\n"
            "        decider = SlackApprovalDecider(session_key=session_key)\n",
        ),
        (
            "            # Set P2 (_kc_maintainer_commands_v1): approved maintainer commands run without a prompt.\n",
            f"            _kc_ask = False  # Set R ({MARK})\n"
            "            # Set P2 (_kc_maintainer_commands_v1): approved maintainer commands run without a prompt.\n",
        ),
        (
            "                    error=\"non-owner write/execute blocked (Set O2)\",\n                )\n"
            "                return \"deny\"\n            if context_builder is None:\n                return \"\"\n",
            "                    error=\"non-owner write/execute blocked (Set O2)\",\n                )\n"
            "                if not _kc_ask_owner_register(\n"
            "                    event, user_id, channel, agent_override, gateway, getattr(client, \"cwd\", None), decider\n"
            "                ):\n"
            "                    return \"deny\"\n"
            "                _kc_ask = True\n"
            "            if context_builder is None:\n                return \"deny\" if _kc_ask else \"\"\n",
        ),
        (
            "            if result.action == TOOL_DENY:\n                return \"deny\"\n"
            "            if result.action == TOOL_AUTO_APPROVE:\n",
            "            if result.action == TOOL_DENY:\n                return \"deny\"\n"
            "            if _kc_ask:  # Set R: never let a hook auto-approve skip the owner\n"
            "                return \"ask_owner\"\n"
            "            if result.action == TOOL_AUTO_APPROVE:\n",
        ),
    ],
    r'''

# ---------------------------------------------------------------------------
# Set R (''' + MARK + r'''): ask-the-owner for maintainers, durable rules,
# wider (still checked) shell grammar. Definitions below REPLACE the Set P2/P3/Q
# versions of the same names (module-level rebinding; callers resolve at call
# time). See ~/.kiro/crew/repatch-set-r-maintainer-ask-owner.sh.
# ---------------------------------------------------------------------------
KC_MAINTAINER_COMMAND_IDS = (
    "fs", "ls", "git-read", "typecheck", "lint", "build", "deploy", "git-write", "gh-pr", "wrangler-tail"
)
_KC_BUILTIN_CMD_IDS = frozenset()  # P3 built-ins are now ordinary, visible command ids
_KC_PROGRAM_RE = __import__("re").compile(r"^[a-z][a-z0-9._+-]{0,31}$")
_KC_PROGRAM_NEVER = frozenset(
    {"sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh", "env", "sudo", "su", "doas", "pkexec",
     "eval", "exec", "xargs", "nohup", "setsid", "timeout", "nice", "ionice", "stdbuf", "busybox", "time",
     "watch", "script", "expect", "python", "python2", "python3", "pip", "pip3", "pipx", "uv", "uvx",
     "node", "nodejs", "deno", "bun", "perl", "ruby", "php", "lua", "awk", "gawk", "mawk", "tclsh",
     "osascript", "curl", "wget", "ssh", "scp", "sftp", "rsync", "nc", "ncat", "netcat", "socat",
     "telnet", "ftp", "openssl", "gpg", "npm", "npx", "pnpm", "yarn", "make", "cmake", "cargo", "go",
     "docker", "podman", "kubectl", "terraform", "aws", "gcloud", "az", "wrangler", "git", "gh",
     "rm", "mv", "cp", "ln", "chmod", "chown", "chgrp", "dd", "tee", "truncate", "shred", "install",
     "crontab", "at", "systemctl", "service", "kill", "pkill", "killall", "mount", "umount",
     "kirocrew", "kiro-cli", "claude", "rtk", "cd", "source", "alias", "export", "unset", "set"}
)
_KC_READ_CMDS = frozenset({"cat", "head", "tail", "wc", "grep", "sort", "uniq", "cut", "diff", "stat", "file", "du", "find"})
_KC_FILTERS = frozenset({"head", "tail", "wc", "sort", "uniq", "cut", "grep", "tr", "column", "cat", "nl"})
_KC_FIND_DENY = frozenset({"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"})
_KC_KNOWN_FAMILIES = frozenset({"cd", "pwd", "ls", "tree", "git", "rm", "rmdir", "mkdir", "touch", "mv", "cp",
                                "npm", "npx", "gh"}) | _KC_READ_CMDS


def _kc_cmd_lex(cmd: str) -> Any:
    """Quote-aware lexer: ("w", word) / ("op", "&&"|";"|"||"|"|"), or None.

    Redirection is accepted only to /dev/null (and 2>&1 / 1>&2) and dropped.
    Any other metacharacter outside quotes, or $ ` \\ newline inside double
    quotes, refuses the whole line.
    """
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
        elif cmd.startswith("&&", i) or cmd.startswith("||", i):
            flush()
            out.append(("op", cmd[i : i + 2]))
            i += 2
        elif ch in ";|":
            flush()
            out.append(("op", ch))
            i += 1
        elif ch == ">" or (not has and cmd[i : i + 2] in ("2>", "1>", "&>")):
            flush()
            j = i + 1 if ch == ">" else i + 2
            if cmd.startswith(">", j):
                return None  # append redirection
            while j < n and cmd[j] in " \t":
                j += 1
            k = j
            while k < n and cmd[k] not in " \t;|" and not cmd.startswith("&&", k):
                k += 1
            if cmd[j:k] not in ("/dev/null", "&1", "&2"):
                return None
            i = k
        elif ch in _KC_OUT_META:
            return None
        else:
            word.append(ch)
            has = True
            i += 1
    flush()
    return out


def _kc_cmd_segments_full(cmd: str) -> Any:
    """[(words, piped)] split on && ; || |, or None (empty segment / bad lex)."""
    toks = _kc_cmd_lex(cmd)
    if not toks:
        return None
    segs: list = []
    cur: list = []
    piped = False
    for kind, val in toks + [("op", "END")]:
        if kind == "w":
            cur.append(val)
            continue
        if not cur:
            return None
        segs.append((cur, piped))
        cur, piped = [], val == "|"
    return segs


def _kc_cmd_segments(cmd: str) -> Any:
    segs = _kc_cmd_segments_full(cmd)
    return [w for w, _p in segs] if segs else None


def _kc_read_args_ok(args: list, cwd: str, root: str, skip_first: bool = False) -> bool:
    import os

    seen_first = not skip_first
    for a in args:
        if a.startswith("-"):
            if "=" in a and ("/" in a.split("=", 1)[1]):
                v = a.split("=", 1)[1]
                if not _kc_read_target_ok(os.path.normpath(v if os.path.isabs(v) else os.path.join(cwd, v)), root):
                    return False
            continue
        if not seen_first:
            seen_first = True
            continue
        t = os.path.normpath(a if os.path.isabs(a) else os.path.join(cwd, a))
        if not _kc_read_target_ok(t, root):
            return False
    return True


def _kc_read_cmd_ok(w0: str, args: list, cwd: str, root: str) -> bool:
    if w0 == "grep":
        if any(a in ("-r", "-R", "--recursive", "-d", "--directories", "--dereference-recursive")
               or (a.startswith("-") and not a.startswith("--") and ("r" in a[1:] or "R" in a[1:])) for a in args):
            return False  # a recursive grep reads .env / keys inside the tree
        has_e = any(a in ("-e", "--regexp") or a.startswith("--regexp=") for a in args)
        return _kc_read_args_ok(args, cwd, root, skip_first=not has_e)
    if w0 == "find":
        if any(a in _KC_FIND_DENY for a in args):
            return False
        paths = []
        for a in args:
            if a.startswith("-") or a in ("(", ")", "!"):
                break
            paths.append(a)
        return _kc_read_args_ok(paths or ["."], cwd, root)
    return _kc_read_args_ok(args, cwd, root)


_kc_p3_builtin_segment_id = _kc_builtin_segment_id


def _kc_builtin_segment_id(words: list, cwd: str, root: str) -> Any:  # noqa: F811
    w0 = words[0]
    if w0 in _KC_READ_CMDS:
        return "ls" if _kc_read_cmd_ok(w0, words[1:], cwd, root) else None
    return _kc_p3_builtin_segment_id(words, cwd, root)


def _kc_program_segment_ok(words: list, cwd: str, root: str) -> bool:
    """An owner-approved program: every path-looking arg stays readable in the workspace."""
    import os

    w0, args = words[0], words[1:]
    if not _KC_PROGRAM_RE.match(w0) or w0 in _KC_PROGRAM_NEVER:
        return False
    writes = w0 == "sed" and any(a == "-i" or a.startswith(("-i", "--in-place")) for a in args)
    for a in args:
        v = a.split("=", 1)[1] if a.startswith("-") and "=" in a else (None if a.startswith("-") else a)
        if not v:
            continue
        t = os.path.normpath(v if os.path.isabs(v) else os.path.join(cwd, v))
        if "/" in v or os.path.lexists(t):
            if not _kc_read_target_ok(t, root):
                return False
            if writes and os.path.isfile(t) and not _kc_write_target_ok(t, root):
                return False
    return True


def _kc_channel_entry(channel: str) -> dict:
    try:
        import json

        data = json.loads(_kc_roles_path().read_text(encoding="utf-8"))
        return ((data or {}).get("channels") or {}).get(channel) or {}
    except Exception:
        return {}


def _kc_channel_programs(channel: str) -> frozenset:
    progs = _kc_channel_entry(channel).get("programs") or []
    return frozenset(p for p in progs if isinstance(p, str) and _KC_PROGRAM_RE.match(p) and p not in _KC_PROGRAM_NEVER)


def _kc_walk_segments(cmd: str, root: str, programs: frozenset, approved: frozenset) -> Any:
    """Per segment: ("ok", id) / ("need", id) / ("prog", name) / ("no", None). None = bad line."""
    import os

    segs = _kc_cmd_segments_full(cmd or "")
    if not segs:
        return None
    cwd, out = root, []
    for words, piped in segs:
        ws = words[1:] if words and words[0] == "rtk" else words
        if not ws:
            return None
        if piped and ws[0] in _KC_FILTERS and all(a.startswith("-") or a.isdigit() for a in ws[1:]) and ws[0] != "cat":
            out.append(("ok", "filter"))
            continue
        if ws[0] == "grep" and piped and len([a for a in ws[1:] if not a.startswith("-")]) <= 1:
            out.append(("ok", "filter"))
            continue
        cid = _kc_cmd_segment_id(words, cwd, root)
        if cid and cid.startswith("cd:"):
            cwd = cid[3:]
            out.append(("ok", "cd"))
            continue
        if cid == "build" and not _kc_css_exec_free(root):
            cid = None
        if cid:
            out.append(("ok" if cid in approved else "need", cid))
            continue
        if ws[0] in programs and _kc_program_segment_ok(ws, cwd, root):
            out.append(("ok", f"prog:{ws[0]}"))
            continue
        if ws[0] not in _KC_KNOWN_FAMILIES and _kc_program_segment_ok(ws, cwd, root):
            out.append(("prog", ws[0]))
            continue
        out.append(("no", None))
    _ = os
    return out


def _kc_approved_cmd_ids(cmd: str, root: str) -> Any:  # noqa: F811
    """Ids the WHOLE line needs (cd/filters excluded) assuming every id were approved."""
    walk = _kc_walk_segments(cmd, root, frozenset(), frozenset(KC_MAINTAINER_COMMAND_IDS))
    if not walk or any(st not in ("ok",) for st, _ in walk):
        return None
    ids = [i for _st, i in walk if i not in ("cd", "filter")]
    return ids or None


def _kc_maintainer_cmd_approved(  # noqa: F811
    event: Any, user_id: str, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any
) -> bool:
    """A maintainer shell line made ONLY of this channel's approved ids/programs."""
    if not getattr(event, "is_shell", False) or not _kc_is_channel_maintainer(user_id, channel):
        return False
    root, cwd_ok = _kc_channel_root(channel_agent, gateway, session_cwd)
    if not root or not cwd_ok:
        return False
    cmd = getattr(event, "shell_command", None) or ""
    walk = _kc_walk_segments(cmd, root, _kc_channel_programs(channel), _kc_channel_commands(channel))
    if not walk or any(st != "ok" for st, _ in walk):
        return False
    ids = [i for _st, i in walk if i not in ("cd", "filter")]
    if not ids:
        return False
    sel().log_api_access(
        caller=user_id,
        operation="slack.channel_maintainer_cmd",
        outcome="allowed",
        source="slack",
        resources=f"channel={channel} ids={','.join(ids)} cmd={cmd[:200]}",
    )
    return True


def _kc_member_shell_ok(event: Any, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any) -> bool:  # noqa: F811
    """Read-only listing/text tools inside the channel workspace, for any non-owner."""
    if not getattr(event, "is_shell", False):
        return False
    root, cwd_ok = _kc_channel_root(channel_agent, gateway, session_cwd)
    if not root or not cwd_ok:
        return False
    walk = _kc_walk_segments(getattr(event, "shell_command", None) or "", root, frozenset(), frozenset({"ls"}))
    return bool(walk) and all(st == "ok" for st, _ in walk) and any(i == "ls" for _s, i in walk)


def _kc_suggest_rule(event: Any, channel: str, root: str) -> Any:
    """{"commands": [...], "programs": [...]} that would allow this call, or None."""
    if not getattr(event, "is_shell", False):
        return None
    walk = _kc_walk_segments(getattr(event, "shell_command", None) or "", root,
                             _kc_channel_programs(channel), _kc_channel_commands(channel))
    if not walk or any(st == "no" for st, _ in walk):
        return None
    cmds = sorted({i for st, i in walk if st == "need"})
    progs = sorted({i for st, i in walk if st == "prog"})
    return {"commands": cmds, "programs": progs} if (cmds or progs) else None


def _kc_owner_id() -> str:
    try:
        from kiro_crew.slack import handler as _h

        return getattr(_h, "_owner_id", "") or ""
    except Exception:
        return ""


def _kc_ask_owner_register(
    event: Any, user_id: str, channel: str, channel_agent: Any, gateway: Any, session_cwd: Any, decider: Any
) -> bool:
    """Arm an ask-the-owner card for a MAINTAINER request. False => plain deny."""
    if decider is None or not _kc_is_channel_maintainer(user_id, channel):
        return False
    root, cwd_ok = _kc_channel_root(channel_agent, gateway, session_cwd)
    if not root or not cwd_ok:
        return False
    try:
        from kiro_crew.slack import renderer as _r

        key = _r._approval_registry_key(getattr(decider, "session_key", "") or "", getattr(event, "request_id", ""))
        rule = _kc_suggest_rule(event, channel, root)
        label = ""
        if rule:
            label = ", ".join(rule["commands"] + [f"program {p}" for p in rule["programs"]])
        if len(_r._KC_ASK_OWNER) >= _r._KC_ASK_OWNER_MAX:
            _r._KC_ASK_OWNER.pop(next(iter(_r._KC_ASK_OWNER)), None)
        _r._KC_ASK_OWNER[key] = {
            "channel": channel, "user": user_id, "owner": _kc_owner_id(),
            "rule": rule, "rule_label": label,
        }
    except Exception:
        return False
    sel().log_api_access(
        caller=user_id,
        operation="slack.maintainer_ask_owner",
        outcome="pending",
        source="slack",
        resources=f"channel={channel} kind={getattr(event, 'tool_kind', '')} rule={label or '-'}",
    )
    return True


def _kc_add_maintainer_rule(entry: dict, approver: str) -> str:
    """Append the entry's rule to channel-roles.json (atomic, 0600). Returns its label or ''."""
    import contextlib
    import json
    import os
    import tempfile

    rule = (entry or {}).get("rule") or {}
    channel = (entry or {}).get("channel") or ""
    cmds = [c for c in rule.get("commands") or [] if c in KC_MAINTAINER_COMMAND_IDS]
    progs = [p for p in rule.get("programs") or [] if _KC_PROGRAM_RE.match(p) and p not in _KC_PROGRAM_NEVER]
    if not channel or not (cmds or progs):
        return ""
    path = _kc_roles_path()
    try:
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"channels": {}}
        if not isinstance(data, dict) or not isinstance(data.get("channels", {}), dict):
            return ""
        ch = data.setdefault("channels", {}).setdefault(channel, {})
        if not isinstance(ch, dict):
            return ""
        have_c = [c for c in ch.get("commands") or [] if isinstance(c, str)]
        ch["commands"] = [c for c in KC_MAINTAINER_COMMAND_IDS if c in set(have_c) | set(cmds)]
        have_p = [p for p in ch.get("programs") or [] if isinstance(p, str)]
        ch["programs"] = sorted(set(have_p) | set(progs))
        if not ch["programs"]:
            ch.pop("programs")
        fd, tmp = tempfile.mkstemp(prefix=".channel-roles.", dir=str(path.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(data, fh, indent=2, ensure_ascii=False)
                fh.write("\n")
            os.chmod(tmp, 0o600)
            os.replace(tmp, path)
        except BaseException:
            with contextlib.suppress(OSError):
                os.unlink(tmp)
            raise
    except Exception:
        logger.warning("Set R: could not store maintainer rule", exc_info=True)
        return ""
    label = ", ".join(cmds + [f"program {p}" for p in progs])
    sel().log_api_access(
        caller=approver,
        operation="slack.maintainer_rule_added",
        outcome="allowed",
        source="slack",
        resources=f"channel={channel} maintainer={entry.get('user', '')} rule={label}",
    )
    return label
''',
)

if plans:
    for p, text in plans:
        shutil.copy2(p, p.with_name(p.name + f".bak-setr-{stamp}"))
        p.write_text(text)
        py_compile.compile(str(p), doraise=True)
        for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
            pyc.unlink()
        print(f"Set R: patched {p.relative_to(site)}")

import importlib
TD = importlib.import_module("kiro_crew.slack.transport_dispatch")
R = importlib.import_module("kiro_crew.slack.renderer")
D = importlib.import_module("kiro_crew.messaging.driver")
I = importlib.import_module("kiro_crew.slack.interactions")
for mod, n in ((TD, "_kc_ask_owner_register"), (TD, "_kc_add_maintainer_rule"), (TD, "_kc_walk_segments"),
               (R, "_KC_ASK_OWNER"), (R, "_kc_ask_owner_blocks")):
    assert hasattr(mod, n), n
import inspect
assert 'if _gate == "ask_owner":' in inspect.getsource(D)
assert "_kc_add_maintainer_rule" in inspect.getsource(I)
print("Set R: OK (imports + names verified)")
PY
