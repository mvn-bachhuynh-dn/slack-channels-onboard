# Contributing

Thanks for helping. Bug reports, fixes and ideas are all welcome. Please follow
the [Code of Conduct](CODE_OF_CONDUCT.md), and report security problems
privately as described in [SECURITY.md](SECURITY.md), not in an issue.

The rules below are the same ones AI agents follow in [AGENTS.md](AGENTS.md);
read it for the details.

## Before you start

- **Bug or idea:** open an issue with the matching template first, so we can
  agree on the approach before you write code.
- **Small fix** (typo, obvious bug): a pull request on its own is fine.

## Development

You need Python 3.10+, Node.js 18+ and a Kiro Crew 0.9.0 gateway to try changes
on.

```bash
pip install -r requirements-dev.txt               # aiohttp + pytest
python -m pytest tests -q                         # backend tests (no gateway needed)
cd ui && npm ci && npm run build && rm -rf node_modules && cd ..
```

- `ui/dist/` is committed: rebuild it whenever `ui/src/` changes.
- UI text lives in `ui/src/i18n.ts` (English, with Vietnamese overrides); never
  hardcode a user-facing string in `App.tsx`.
- Anything that depends on a gateway capability is detected at runtime
  (`access_capabilities()`, `backend_support()` in `backend/gateway_ops.py`),
  never assumed from a version. Without the capability the UI hides it and the
  route refuses.
- Kiro Crew internals are imported lazily, inside functions.
- To try a change on your gateway: Apps → Slack Channels Onboard → Update in the
  dashboard, then restart the gateway.

## Pull requests

- Branch off `main`, one change per pull request, and keep it small.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `chore:` …).
- Bump `version` in `app.json` (semver) when behaviour changes.
- Add or update tests for what you change; `python -m pytest tests -q` must pass.
- Never include real Slack ids, channel or person names, home paths, hostnames,
  tokens or other personal data, in code, comments, tests or screenshots.

CI runs on every pull request: the backend tests on Python 3.10 and 3.12, a
check that `ui/dist/` matches a fresh build, and every documented
`gateway-patches` combination applied twice to a pristine Kiro Crew 0.9.0.

`main` moves only through pull requests. The App Store installs the `release`
branch, which only advances to a `main` commit after a Kiro Crew maintainer has
reviewed it, so a merged change does not reach store users by itself.

## Gateway patches

Changes under `gateway-patches/` patch Kiro Crew itself and touch access
control, so they get extra scrutiny:

- keep each set idempotent and anchor-checked, with a header that says what it
  changes, why, the upstream issue or PR, and how to roll it back;
- prove it with `apply.sh` against a pristine tree of the targeted tag
  (`git archive v0.9.0 src/kiro_crew` from kirodotdev/KiroCrew);
- update `gateway-patches/README.md` in the same pull request.

## License

By contributing you agree that your contribution is licensed under the
[Apache License 2.0](LICENSE), the license of this project.
