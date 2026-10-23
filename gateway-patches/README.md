# Gateway patches

On a **stock** Kiro Crew 0.9.0 gateway the app can write every binding, but a
Slack channel turn does not use it: the chat path passes the channel's agent
alias to kiro-cli as a mode name and runs in a scratch directory instead of the
agent's workspace. **Set B fixes that and is needed for the app's core
purpose.** Everything else here is optional. All of it lives here as patch sets
for the installed `kiro_crew` package, so you can read them and decide.

**Nothing here is installed by the app.** You run it yourself, or not at all.
Without the optional sets, the app hides their features and their routes refuse.

## Read this first

- **They change access control.** Stock Kiro Crew is owner-only on Slack. These
  sets let other people talk to the bot (read-only), let chosen maintainers
  write inside one channel's workspace, and ask the owner in Slack for missing
  permissions. Review them like any security change.
- **They patch the installed package in place**, by anchored text replacement.
  They are written against **Kiro Crew 0.9.0**. On any other version an anchor
  may not match: that set stops with `CHECK ANCHORS`, writes nothing, and
  `apply.sh` stops there. They are not a supported Kiro Crew feature.
- **A Kiro Crew update overwrites them.** Re-run `apply.sh` after every update.
  A set that finds the fix already shipped upstream turns itself into a no-op.
- The Slack approval buttons added by Set R/R3 are in Vietnamese
  (*Cho phép 1 lần*, *Cho phép cả lượt này*, *Luôn cho phép*, *Từ chối*).

## Which feature needs which set

The app detects every feature at runtime, by the function the gateway exposes
(`access_capabilities()` and `backend_support()` in `backend/gateway_ops.py`).

| App feature | Sets | Upstream status |
|---|---|---|
| **Channel turns use the agent and its workspace (core)** | B | fixed upstream by kirodotdev/KiroCrew#22858, after 0.9.0; the set no-ops on a release that carries it |
| Members (`slack.allowed_users`, read-only) | K, M, M2, O, O2, O3 | proposed in kirodotdev/KiroCrew#22759 |
| Maintainers per channel (scoped write) | P, P3 | proposed in kirodotdev/KiroCrew#22759 |
| Approved commands per channel | P2 | proposed in kirodotdev/KiroCrew#22759 |
| Approved programs; owner asked in Slack | R, R2, R3 | proposed in kirodotdev/KiroCrew#22759 |
| Open channels (every channel member, read-only) | Q, Q2 | proposed in kirodotdev/KiroCrew#22759 |
| Workspace confinement for maintainer channels | T (+ `sets/patch-src/kc_confine.py`) | proposed in kirodotdev/KiroCrew#22759 |
| Agent backend per channel | U | issue kirodotdev/KiroCrew#21910, PR #16200 (open) |
| (support) | S: `KIROCREW_SLACK_TEAM_ID` in the agent env | PR kirodotdev/KiroCrew#22380 (open) |

Every script's header explains what it changes, why, and how to roll it back.

## Apply

```bash
# pipx install (default location):
bash gateway-patches/apply.sh

# any other install: point at the installed kiro_crew package
KC_SITE_OVERRIDE=/path/to/site-packages/kiro_crew bash gateway-patches/apply.sh

bash gateway-patches/apply.sh --list   # the sets, in the order they run
```

Pick only what you need with `--only` (sets still run in the fixed order).
Combinations tested on a pristine 0.9.0 tree:

| You want | Command |
|---|---|
| Core only | `apply.sh --only b` |
| Core + agent backend per channel | `apply.sh --only b,u` |
| + members (read-only) | `apply.sh --only b,k,m,o,m2,o2,o3` |
| + maintainers, open channels, ask-the-owner | `apply.sh --only b,k,m,o,m2,o2,o3,p,p2,p3,q,q2,r,r2,r3` |
| Everything, including confinement | `apply.sh` |

Then restart the gateway. The sets run in a fixed order (later sets anchor on
text earlier ones wrote), and the run stops at the first failure.

Requirements: Python 3 (the scripts use the gateway's own venv when found).
Set T needs `bwrap` (bubblewrap); without it confinement stays off and the
strict approval gate applies. Set T mounts a fixed list of toolchain
directories from your home read-only into the sandbox (`HOME_ALLOW_RO` in
`sets/patch-src/kc_confine.py`); add yours there if an agent cannot find a tool.

## Undo

Every edited file has a `*.bak-set<x>-<stamp>` copy next to it: restore those,
delete `kiro_crew/_kc_confine.py` and `kiro_crew/slack/team_ids.py` if present,
clear `__pycache__`, restart. Or reinstall the package
(`pipx reinstall kirocrew`), which drops every set at once.

## Tested

Every combination above applies to a pristine `v0.9.0` tree, and the full set
runs on a live 0.9.0 gateway. Not tested on other versions or on Windows.
