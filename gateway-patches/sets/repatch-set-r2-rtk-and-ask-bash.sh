#!/usr/bin/env bash
# ============================================================================
# Set R2 — close two holes found in the live Set R test (2026-10-20).
#
# 1. `rtk` wrappers. `rtk proxy|err|test|summary <cmd>` RUNS <cmd>; Set R read
#    `rtk proxy ls` as an unknown program "proxy" and offered to store it, which
#    would have allowed `rtk proxy <anything>`. Now every segment is normalised
#    first: rtk options dropped; proxy/err/test/summary -> the wrapped command
#    (checked like any other); read/smart/json/log -> `cat`; tsc -> `npx tsc`;
#    ls/tree/git/gh/find/diff/grep/wc/npm/npx -> the plain command; any other
#    rtk subcommand (aws, curl, wget, docker, pip, env, config, trust, hook…)
#    is never approvable. "proxy" and "rtk*" join the never-store list.
# 2. Claude Code runs "read-only" Bash (e.g. `echo x | sed s/a/b/`) WITHOUT
#    session/request_permission, so the gate never saw it (verified with
#    `claude -p`: runs with {} settings, asks with permissions.ask ["Bash"]).
#    The Set Q2 seed now asks for Bash too: ["Bash", "Glob", "Grep", "Read"].
#    (Project .claude/settings.json files written by the Channel Onboard app
#    carry the same list from app v0.5.1.)
#
# Requires Sets Q2 and R. Idempotent via marker _kc_rtk_normalize_v1.
# ============================================================================
set -uo pipefail
SITE=${KC_SITE_OVERRIDE:-}; [ -n "$SITE" ] || SITE=$(python3 -c "import pathlib; g=list(pathlib.Path.home().joinpath('.local/share/pipx/venvs/kirocrew/lib').glob('python*/site-packages/kiro_crew')); print(g[0] if g else '')")
[ -n "$SITE" ] || { echo "Set R2: venv not found — skipping"; exit 0; }
VENV_PY=$(ls "$HOME"/.local/share/pipx/venvs/kirocrew/bin/python* 2>/dev/null | head -1 || true)
STAMP=$(date +%Y%m%d-%H%M%S)

"$VENV_PY" - "$SITE" "$STAMP" <<'PY'
import sys, pathlib, shutil, py_compile
site, stamp = pathlib.Path(sys.argv[1]), sys.argv[2]
MARK = "_kc_rtk_normalize_v1"


def apply(rel, needs, edits, tail=""):
    p = site / rel
    s = p.read_text()
    if MARK in s:
        print(f"Set R2: {rel} already applied — no-op")
        return
    for n in needs:
        if n not in s:
            print(f"Set R2: FAIL — {rel} lacks {n}"); sys.exit(1)
    for old, _new in edits:
        if s.count(old) != 1:
            print(f"Set R2: FAIL {rel} anchor count={s.count(old)} for {old[:70]!r}"); sys.exit(1)
    for old, new in edits:
        s = s.replace(old, new)
    s += tail
    shutil.copy2(p, p.with_name(p.name + f".bak-setr2-{stamp}"))
    p.write_text(s)
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()
    print(f"Set R2: patched {rel}")


apply(
    "acp/client.py",
    ["_kc_claude_ask_reads_v1"],
    [(
        "        perms[\"ask\"] = sorted(set(perms.get(\"ask\") or []) | {\"Read\", \"Grep\", \"Glob\"})\n",
        f"        # Set R2 ({MARK}): Bash too — Claude Code auto-runs 'read-only' Bash without asking.\n"
        "        perms[\"ask\"] = sorted(set(perms.get(\"ask\") or []) | {\"Read\", \"Grep\", \"Glob\", \"Bash\"})\n",
    )],
)

apply(
    "slack/transport_dispatch.py",
    ["_kc_maintainer_ask_owner_v1"],
    [],
    r'''

# ---------------------------------------------------------------------------
# Set R2 (''' + MARK + r'''): rtk wrapper normalisation. Rebinds
# _kc_walk_segments; see ~/.kiro/crew/repatch-set-r2-rtk-and-ask-bash.sh.
# ---------------------------------------------------------------------------
_KC_PROGRAM_NEVER = _KC_PROGRAM_NEVER | frozenset({"proxy"})
_KC_RTK_RUNS = frozenset({"proxy", "err", "test", "summary"})
_KC_RTK_READS = frozenset({"read", "smart", "json", "log"})
_KC_RTK_PLAIN = frozenset({"ls", "tree", "git", "gh", "find", "diff", "grep", "wc", "npm", "npx"})
_KC_RTK_OPTS = frozenset({"-v", "-vv", "-vvv", "--verbose", "-u", "--ultra-compact", "--skip-env"})


def _kc_norm_words(words: list) -> Any:
    """Strip rtk wrappers to the command that actually runs. None = never approvable."""
    w = list(words)
    for _ in range(4):  # rtk proxy rtk proxy … is still bounded
        if not w or w[0] != "rtk":
            return w
        w = w[1:]
        while w and w[0] in _KC_RTK_OPTS:
            w = w[1:]
        if not w:
            return None
        sub = w[0]
        if sub in _KC_RTK_RUNS:
            w = w[1:]
        elif sub in _KC_RTK_READS:
            w = ["cat"] + w[1:]
        elif sub == "tsc":
            w = ["npx", "tsc"] + w[1:]
        elif sub in _KC_RTK_PLAIN:
            pass
        else:
            return None
    return None


def _kc_program_ok_name(name: str) -> bool:
    return bool(_KC_PROGRAM_RE.match(name)) and name not in _KC_PROGRAM_NEVER and not name.startswith("rtk")


def _kc_channel_programs(channel: str) -> frozenset:  # noqa: F811
    progs = _kc_channel_entry(channel).get("programs") or []
    return frozenset(p for p in progs if isinstance(p, str) and _kc_program_ok_name(p))


_kc_r_program_segment_ok = _kc_program_segment_ok


def _kc_program_segment_ok(words: list, cwd: str, root: str) -> bool:  # noqa: F811
    return bool(words) and _kc_program_ok_name(words[0]) and _kc_r_program_segment_ok(words, cwd, root)


def _kc_walk_segments(cmd: str, root: str, programs: frozenset, approved: frozenset) -> Any:  # noqa: F811
    """Set R walk, with every segment normalised through _kc_norm_words first."""
    segs = _kc_cmd_segments_full(cmd or "")
    if not segs:
        return None
    cwd, out = root, []
    for words, piped in segs:
        ws = _kc_norm_words(words)
        if ws is None:
            out.append(("no", None))
            continue
        if not ws:
            return None
        if piped and ws[0] in _KC_FILTERS and ws[0] != "cat" and all(a.startswith("-") or a.isdigit() for a in ws[1:]):
            out.append(("ok", "filter"))
            continue
        if ws[0] == "grep" and piped and len([a for a in ws[1:] if not a.startswith("-")]) <= 1:
            out.append(("ok", "filter"))
            continue
        cid = _kc_cmd_segment_id(ws, cwd, root)
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
    return out


def _kc_add_maintainer_rule(entry: dict, approver: str) -> str:  # noqa: F811
    rule = dict((entry or {}).get("rule") or {})
    rule["programs"] = [p for p in rule.get("programs") or [] if _kc_program_ok_name(p)]
    return _kc_r_add_maintainer_rule({**(entry or {}), "rule": rule}, approver)
''' ,
)

# _kc_add_maintainer_rule must be captured BEFORE its rebinding above; patch the
# capture in place (the tail is appended after the original definition).
p = site / "slack/transport_dispatch.py"
s = p.read_text()
cap = "def _kc_add_maintainer_rule(entry: dict, approver: str) -> str:  # noqa: F811\n"
if "_kc_r_add_maintainer_rule = _kc_add_maintainer_rule\n" not in s and s.count(cap) == 1:
    s = s.replace(cap, "_kc_r_add_maintainer_rule = _kc_add_maintainer_rule\n\n\n" + cap)
    p.write_text(s)
    py_compile.compile(str(p), doraise=True)
    for pyc in (p.parent / "__pycache__").glob(p.stem + ".*.pyc"):
        pyc.unlink()

import importlib, inspect
TD = importlib.import_module("kiro_crew.slack.transport_dispatch")
C = importlib.import_module("kiro_crew.acp.client")
assert TD._kc_norm_words(["rtk", "proxy", "bash", "-c", "x"]) == ["bash", "-c", "x"]
assert TD._kc_norm_words(["rtk", "curl", "x"]) is None
assert "proxy" in TD._KC_PROGRAM_NEVER
assert '"Bash"}' in inspect.getsource(C)
print("Set R2: OK")
PY
