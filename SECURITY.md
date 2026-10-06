# Security Policy

## Reporting a Vulnerability

**Do NOT open a public issue for security vulnerabilities.**

Please report security vulnerabilities through
[GitHub Security Advisories](https://github.com/tomada1114/townsfolk/security/advisories/new).

Include:

- Description of the vulnerability
- Steps to reproduce
- The commit on `main` you tested against
- Suggested fix (if available)

## Response

This project is maintained on a best-effort basis and makes no guaranteed response
time. Townsfolk has no releases — it is not distributed and is built from source
([`docs/architecture.md` › Distribution](docs/architecture.md#distribution)) — so reports are
assessed against `main`, and a fix lands on `main` once one is ready.

## Supported Versions

There are no released versions. Only the current `main` branch is supported.

## Supply-Chain Posture

This repository pins every GitHub Action to a full commit SHA, pins CLI tools
in `mise.toml`, runs zizmor and OpenSSF Scorecard, and delays automated
dependency updates with a Dependabot cooldown. Scorecard's Fuzzing and
Packaging checks legitimately read N/A for a macOS GUI app.

`main`'s intended branch protection is defined as code in
[`.github/rulesets/main.json`](.github/rulesets/main.json) (PR required, checks
green, no force-push or deletion) and applied by a repository admin running
`just ruleset` (`scripts/apply-ruleset.sh`). Whether it is actually in force on
this repository is visible only via `gh api repos/{owner}/{repo}/rulesets`, not
from the checkout — rulesets are server-side configuration.

## Responsible Disclosure

We follow a coordinated disclosure process. We ask that you:

1. Report the issue privately using the method above
2. Allow reasonable time for a fix before public disclosure
3. Avoid exploiting the vulnerability beyond what is necessary to demonstrate it

We will credit reporters in the fix's pull request or its `CHANGELOG.md` entry unless they prefer to remain
anonymous.
