#!/usr/bin/env bash
# ============================================================================
# Set P3 — maintainer FILE OPS + listing (2026-10-20, after a maintainer's rm was denied).
#
# Extends Set P/P2. Built-in for every channel maintainer (no "commands" entry
# needed), auto-approved, only inside the channel workspace:
#   fs        rm [-f -r] / rmdir / mkdir [-p] / touch / mv [-f -n] / cp [-r -p]
#             every target passes Set P's write check (+ P2's build-config
#             lock); a recursive rm/mv of a directory requires EVERY entry under
#             it to pass too (so `rm -r frontend` cannot take package.json or
#             .git along); cp sources must pass the READ check (no copying
#             .env / keys / service-account json into a readable name).
#   ls        ls [-flags] [dirs] / tree [-L N -a -d -f] [dirs] / pwd
#   git-read  the Set P read-only git subset, now chainable (`rm x && git status`)
#   ACP tool kinds `delete` / `move` get the same write check on every path.
# Globs, ~, $ and other metacharacters are refused by the P2 lexer.
#
# Also defines the shared READ check (_kc_read_target_ok) used by Set Q:
# inside the workspace, not under .git .kiro .claude .ssh .aws .gnupg .wrangler
# .config, and no path part that looks like a secret (secret, credential,
# service-account, sa_key, private_key, .env*, .dev.vars, .npmrc, .netrc,
# .pypirc, .mcp.json, *.pem *.key *.p12 *.pfx, id_rsa/ed25519/ecdsa/dsa).
#
# Requires Set P2. Idempotent via marker _kc_maintainer_file_ops_v1.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set P3: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_maintainer_file_ops_v1"
p = site / "slack/transport_dispatch.py"
s = p.read_text()
if MARK in s:
    print("Set P3: already applied — no-op")
else:
    if "_kc_maintainer_commands_v1" not in s:
        print("Set P3: FAIL — Set P2 not present; apply P2 first"); sys.exit(1)
    edits = [
        (
            "    elif kind == \"edit\" or getattr(event, \"diff_path\", \"\"):\n",
            f"    elif kind in (\"delete\", \"move\"):  # Set P3 ({MARK})\n"
            "        allowed = _kc_fs_kind_ok(event, root)\n"
            "    elif kind == \"edit\" or getattr(event, \"diff_path\", \"\"):\n",
        ),
        (
            "    if w0 == \"npm\":\n        if len(words) == 3 and words[1] == \"run\":\n",
            f"    _kc_b = _kc_builtin_segment_id(words, cwd, root)  # Set P3 ({MARK})\n"
            "    if _kc_b:\n"
            "        return _kc_b\n"
            "    if w0 == \"npm\":\n        if len(words) == 3 and words[1] == \"run\":\n",
        ),
        (
            "    approved = _kc_channel_commands(channel)\n    if not approved:\n        return False\n",
            f"    approved = _kc_channel_commands(channel) | _KC_BUILTIN_CMD_IDS  # Set P3 ({MARK})\n",
        ),
    ]
    for old, _new in edits:
        if s.count(old) != 1:
            print(f"Set P3: FAIL anchor count={s.count(old)} for {old[:60]!r} — re-derive"); sys.exit(1)
    for old, new in edits:
        s = s.replace(old, new)
    s += r'''

# ---------------------------------------------------------------------------
# Set P3 (''' + MARK + r'''): maintainer file ops + listing, and the shared
# READ check. See ~/.kiro/crew/repatch-set-p3-maintainer-file-ops.sh.
# ---------------------------------------------------------------------------
_KC_BUILTIN_CMD_IDS = frozenset({"fs", "ls", "git-read"})
_KC_READ_DENY_DIRS = frozenset({".git", ".kiro", ".claude", ".ssh", ".aws", ".gnupg", ".wrangler", ".config"})
_KC_SECRET_NAME_RE = __import__("re").compile(
    r"(secret|credential|service[-_]?account|sa[-_]?key|private[-_]?key|^\.env|\.dev\.vars$"
    r"|^\.npmrc$|^\.netrc$|^\.pypirc$|^\.mcp\.json$|\.pem$|\.key$|\.p12$|\.pfx$"
    r"|^id_(rsa|ed25519|ecdsa|dsa))",
    __import__("re").IGNORECASE,
)
_KC_TREE_MAX = 20000


def _kc_read_target_ok(path: str, root: str) -> bool:
    """A non-owner may READ *path*: inside the workspace, not a secret. Deny on doubt."""
    import os

    expanded = os.path.expanduser(os.path.expandvars(str(path)))
    if not os.path.isabs(expanded):
        return False
    real = os.path.realpath(expanded)
    if not _kc_inside(root, real):
        return False
    if real == root:
        return True
    parts = os.path.relpath(real, root).split(os.sep)
    if any(p in _KC_READ_DENY_DIRS for p in parts):
        return False
    return not any(_KC_SECRET_NAME_RE.search(p) for p in parts)


def _kc_tree_ok(path: str, root: str, check: Any) -> bool:
    """Every entry under directory *path* passes *check* (bounded walk, no symlink follow)."""
    import os

    n = 0
    try:
        for dp, dns, fns in os.walk(path, followlinks=False):
            for name in list(dns) + list(fns):
                n += 1
                if n > _KC_TREE_MAX or not check(os.path.join(dp, name), root):
                    return False
        return True
    except Exception:
        return False


def _kc_fs_write_path_ok(path: str, root: str, recursive: bool) -> bool:
    import os

    if not _kc_write_target_ok(path, root):
        return False
    if os.path.isdir(path) and not os.path.islink(path):
        return recursive and _kc_tree_ok(path, root, _kc_write_target_ok)
    return True


def _kc_split_flags(args: list, allowed: frozenset) -> Any:
    """(flags, operands) when every leading flag is allowed; None otherwise."""
    flags, ops, i = [], [], 0
    while i < len(args) and args[i].startswith("-") and args[i] != "-":
        if args[i] == "--":
            i += 1
            break
        if args[i] not in allowed:
            return None
        flags.append(args[i])
        i += 1
    ops = args[i:]
    if any(a.startswith("-") for a in ops):
        return None
    return flags, ops


_KC_RM_FLAGS = frozenset({"-f", "-r", "-R", "-rf", "-fr", "-Rf", "-fR", "--force", "--recursive", "-v"})


def _kc_builtin_segment_id(words: list, cwd: str, root: str) -> Any:
    """'fs' / 'ls' / 'git-read' when one segment is a built-in maintainer op, else None."""
    import os
    import shlex

    w0, args = words[0], words[1:]
    ab = lambda a: os.path.normpath(a if os.path.isabs(a) else os.path.join(cwd, a))  # noqa: E731
    if w0 == "pwd":
        return "ls" if not args else None
    if w0 == "ls":
        ops = []
        for a in args:
            if a.startswith("-"):
                if not (a == "--color=never" or (len(a) > 1 and a[1:].isalnum())):
                    return None
            else:
                ops.append(a)
        return "ls" if all(_kc_read_target_ok(ab(a), root) for a in (ops or [cwd])) else None
    if w0 == "tree":
        ops, i = [], 0
        while i < len(args):
            a = args[i]
            if a == "-L" and i + 1 < len(args) and args[i + 1].isdigit():
                i += 2
                continue
            if a in ("-a", "-d", "-f", "--noreport", "-C", "-n"):
                i += 1
                continue
            if a.startswith("-"):
                return None
            ops.append(a)
            i += 1
        return "ls" if all(_kc_read_target_ok(ab(a), root) for a in (ops or [cwd])) else None
    if w0 == "git":
        return "git-read" if _kc_git_read_ok(shlex.join(words), root) else None
    if w0 in ("rm", "rmdir", "mkdir", "touch"):
        allowed = {"rm": _KC_RM_FLAGS, "rmdir": frozenset({"-v"}), "mkdir": frozenset({"-p", "-v"}),
                   "touch": frozenset()}[w0]
        sp = _kc_split_flags(args, allowed)
        if not sp or not sp[1]:
            return None
        rec = w0 == "rm" and any(f in ("-r", "-R", "-rf", "-fr", "-Rf", "-fR", "--recursive") for f in sp[0])
        for a in sp[1]:
            t = ab(a)
            ok = _kc_fs_write_path_ok(t, root, rec) if w0 == "rm" else _kc_write_target_ok(t, root)
            if not ok:
                return None
        return "fs"
    if w0 in ("mv", "cp"):
        allowed = frozenset({"-f", "-n", "-v"}) if w0 == "mv" else frozenset({"-r", "-R", "-p", "-v", "-f", "-n", "-rp", "-pr"})
        sp = _kc_split_flags(args, allowed)
        if not sp or len(sp[1]) < 2:
            return None
        srcs, dst = [ab(a) for a in sp[1][:-1]], ab(sp[1][-1])
        if not _kc_write_target_ok(dst, root):
            return None
        for src in srcs:
            final = os.path.join(dst, os.path.basename(src)) if os.path.isdir(dst) else dst
            if not _kc_write_target_ok(final, root):
                return None
            if w0 == "mv":
                if not _kc_fs_write_path_ok(src, root, True):
                    return None
            else:
                if not _kc_read_target_ok(src, root):
                    return None
                if os.path.isdir(src) and not _kc_tree_ok(src, root, _kc_read_target_ok):
                    return None
        return "fs"
    return None


def _kc_fs_kind_ok(event: Any, root: str) -> bool:
    """ACP delete/move tool call: every path it names passes the write check."""
    from kiro_crew.platform.tool_paths import edit_target_candidates

    cands = edit_target_candidates(getattr(event, "raw_tool_params", None), getattr(event, "diff_path", "") or "")
    extra = []
    raw = getattr(event, "raw_tool_params", None)
    if isinstance(raw, dict):
        for k in ("destination", "dest", "new_path", "newPath", "target", "to", "source", "from", "old_path", "oldPath"):
            v = raw.get(k)
            if isinstance(v, str) and v:
                extra.append(v)
    paths = list(cands) + extra
    if not paths or cands.truncated or cands.unanchored:
        return False
    return all(_kc_fs_write_path_ok(str(x), root, True) for x in paths)
'''
    shutil.copy2(p, p.with_name(p.name + f".bak-setp3-{stamp}"))
    p.write_text(s)
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()
    print("Set P3: patched slack/transport_dispatch.py")

import importlib
TD = importlib.import_module("kiro_crew.slack.transport_dispatch")
for n in ("_kc_builtin_segment_id", "_kc_read_target_ok", "_kc_fs_kind_ok", "_KC_BUILTIN_CMD_IDS"):
    assert hasattr(TD, n), n
print("Set P3: OK (imports + names verified)")
PY
