# Rules for AI agents

This file is the single source of truth for agents working in this repository.
`CLAUDE.md` and `.kiro/steering/agents.md` only point here.

## What this is

Slack Channels Onboard is a third-party Kiro Crew app (`app.json` name
`slack-channels-onboard`). Its backend runs as in-gateway Python hooks, so every
change here is code that runs with full gateway privileges and touches who may
use the bot on Slack. Treat it as an access-control surface.

## Branches and how code ships

| Branch | Role | How it moves |
|---|---|---|
| `main` | integration | Only through a pull request on this repo. Never push to it directly. |
| `release` | what the Kiro Crew App Store installs | Fast-forward only, to a commit of `main` that a Kiro Crew maintainer has reviewed. Never commit on it directly. |
| feature branches | one change each | Branch off `main`, open a PR into `main`, delete the branch after merge. |

The App Store row in kirodotdev/KiroCrew (`src/kiro_crew/apps/app-registry.json`,
proposed in kirodotdev/KiroCrew#22664) tracks `release`. That is the promise made
to the upstream reviewers: a push to this repo never reaches store users on its
own. So:

1. Work on a feature branch, PR into `main`, merge, delete the branch.
2. Do not touch `release` as part of a feature. Advancing it is a separate step:
   ask for an upstream review of the exact `main` commit, and only after it is
   approved run `git push origin <reviewed-sha>:release` (fast-forward; never
   `--force`).
3. A commit pushed to a feature branch after its PR merged is lost unless it gets
   its own PR. Check `gh pr view <n> --json state` before pushing to a PR branch.

Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:` …).
Bump `version` in `app.json` (semver) in the PR that changes behaviour.

## Gateway compatibility

- Stock Kiro Crew is owner-only on Slack and has no per-agent backend. Every
  feature that depends on a gateway capability is detected at runtime
  (`access_capabilities()`, `backend_support()` in `backend/gateway_ops.py`),
  never assumed from a version. A missing capability hides the UI and makes the
  route refuse; it must never write config the gateway would ignore or drop.
- Kiro Crew internals are imported lazily inside functions; a top-level import of
  a `kiro_crew.slack` module has taken the gateway down before.
- Every route calls `require_owner_dashboard_request`; every write is SEL-audited.

## Gateway patches

`gateway-patches/` holds the patch sets for the installed `kiro_crew` package
that the optional features need (members, maintainers, open channels,
confinement, per-agent backend). They are copies of the owner's local sets,
published so users can decide for themselves.

- Never add personal data: no real Slack ids, channel or person names, home
  paths, hostnames or domains, in code or comments. Scan before committing.
- Keep each set idempotent, anchor-checked, with a header that says what it
  changes, why, the upstream issue/PR, and how to roll back.
- Every script honours `KC_SITE_OVERRIDE`; prove a change by running
  `apply.sh` against a pristine tree of the targeted tag
  (`git archive v0.9.0 src/kiro_crew` from kirodotdev/KiroCrew).
- When a set changes, update `gateway-patches/README.md` (feature map, upstream
  status, tested version) in the same PR.

## Before you open a PR

```bash
python -m pytest tests -q                       # backend tests
cd ui && npm install && npm run build && rm -rf node_modules && cd ..   # ui/dist is committed
```

UI strings live in `ui/src/i18n.ts` (English default, Vietnamese overrides);
never hardcode a user-facing string in `App.tsx`.

## Installing a change on the local gateway

The running gateway installs this app from this directory. `kirocrew app install`
refuses an app that is already installed; update it from the dashboard
(Apps → Slack Channels Onboard → Update), then restart the gateway so the backend
hooks reload.
