## What and why

<!-- What this changes and why. Link the issue: Fixes #123 -->

## How it was tested

<!-- Commands run and what you checked by hand. For gateway-patches/ changes:
     the apply.sh run against a pristine tree of the targeted Kiro Crew tag. -->

## Checklist

- [ ] One change, branched off `main`, with a Conventional Commits title
- [ ] `python -m pytest tests -q` passes; tests added or updated for the change
- [ ] `ui/dist/` rebuilt if `ui/src/` changed; new UI strings are in `ui/src/i18n.ts`
- [ ] `version` in `app.json` bumped if behaviour changed
- [ ] Docs updated (README, `gateway-patches/README.md` for patch changes)
- [ ] No real Slack ids, channel or person names, paths, hostnames or tokens anywhere in the diff
