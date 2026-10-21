# Security policy

This app runs Python inside the Kiro Crew gateway, and its optional
`gateway-patches/` change who may use the bot on Slack. Security reports are
taken seriously.

## Reporting a vulnerability

Report privately through this repository's **Security → Report a vulnerability**
form (GitHub private vulnerability reporting). Please do not open a public issue
for a vulnerability.

Include what you found, how to reproduce it, the app version (`app.json`), the
Kiro Crew version, and which gateway patch sets are applied
(`bash gateway-patches/apply.sh --list` lists them; the `_kc_*` markers in the
installed package show which are present).

You will get an acknowledgement within a few days. A fix ships as a new release;
the advisory is published once users can update.

## Supported versions

| Version | Supported |
|---|---|
| latest release | yes |
| older releases | no, update to the latest |

## Scope

In scope:

- The app's backend routes and config writes (owner-only checks, input
  validation, what reaches `config.json` and `channel-roles.json`).
- The patch sets in `gateway-patches/`: a way for a member, a maintainer or an
  open-channel user to exceed the rights that README describes, to reach
  another channel's workspace or the owner's secrets, or to escape Set T's
  confinement.

Out of scope: vulnerabilities in Kiro Crew itself on a stock gateway (report
those to [kirodotdev/KiroCrew](https://github.com/kirodotdev/KiroCrew)), and
issues that need the owner's own credentials or shell access.
