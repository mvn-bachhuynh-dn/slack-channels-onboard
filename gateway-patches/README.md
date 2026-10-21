# Gateway patches (optional)

The app works on a **stock** Kiro Crew gateway: onboarding, workspace,
activation, `thread_follow` and unbind need nothing extra. Some features need
behaviour that stock Kiro Crew does not have yet. They live here as patch sets
for the installed `kiro_crew` package, so you can read them and decide.

**Nothing here is installed by the app.** You run it yourself, or not at all.
Without it, the app hides the features below and their routes refuse.

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
| Members (`slack.allowed_users`, read-only) | K, M, M2, O, O2, O3 | proposed in kirodotdev/KiroCrew#22759 |
| Maintainers per channel (scoped write) | P, P3 | proposed in kirodotdev/KiroCrew#22759 |
| Approved commands per channel | P2 | proposed in kirodotdev/KiroCrew#22759 |
| Approved programs; owner asked in Slack | R, R2, R3 | proposed in kirodotdev/KiroCrew#22759 |
| Open channels (every channel member, read-only) | Q, Q2 | proposed in kirodotdev/KiroCrew#22759 |
| Workspace confinement for maintainer channels | T (+ `sets/patch-src/kc_confine.py`) | proposed in kirodotdev/KiroCrew#22759 |
| Agent backend per channel | U | issue kirodotdev/KiroCrew#21910, PR #16200 (open) |
| (support) | L: no Slack stream without a recipient user | issue kirodotdev/KiroCrew#14625, closed upstream after 0.9.0 |
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

All sets apply in order to a pristine `v0.9.0` tree and run on a live 0.9.0
gateway. Not tested on other versions or on Windows.
