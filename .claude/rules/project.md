---
paths:
  - "project.yml"
  - "Config/*.xcconfig"
  - "Packages/**/Package.swift"
  - "Packages/**/Package.resolved"
  - "mise.toml"
  - ".swiftlint.yml"
  - ".swiftformat"
  - "scripts/coverage.sh"
---

## Dependency Policy

- The template ships with ZERO package dependencies — keep it that way unless the app truly needs one
- Before adding a dependency, record in the pull request why it passes each of these
  (a new dependency also needs human sign-off — AGENTS.md › Security and human approval):
  - **Need** — why a small hand-written type, the Swift standard library, or Foundation
    cannot do the job
  - **Continuity** — recent releases, and more than one maintainer or an organization
    behind it
  - **License** — in the allow-list below, which `.github/workflows/dependency-review.yml`
    enforces
  - **Weight** — the direct and transitive package count after `swift package resolve`
  - **Build-time code** — whether it ships a binary target or a build/command plugin (code
    that runs at build time); either needs explicit human approval
  - **Platforms** — its platform floor is at or below this package's `.macOS(.v14)`
    (`platforms:` in `Packages/TownsfolkKit/Package.swift`)
  - **Advisories** — no open security advisory against the version being added
- Allowed licenses (SPDX): MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, 0BSD, Zlib.
  `.github/workflows/dependency-review.yml` enforces this exact list (`allow-licenses`) on
  every pull request — change both together; a per-package exception goes in its
  `allow-dependencies-licenses` with a comment giving the reason
- `Package.resolved` MUST be committed alongside any dependency change

## Version Requirements

- Declare a dependency with `.upToNextMajor(from:)` by default: the committed
  `Package.resolved` pins the exact version, so a range plus the resolved file reproduces
  the build
- Add or bump one by editing `Package.swift` and running `swift package resolve` (or
  `swift package update <Name>`) inside `Packages/TownsfolkKit` — never hand-edit
  `Package.resolved`: a hand-written entry states a revision nobody verified
- Verify with `just check`

## Gates

- NEVER lower a coverage floor (currently 80% of lines and 75% of functions on TownsfolkCore)
- NEVER remove SwiftLint rules without explicit user approval

## Project Generation

- `project.yml` is the source of truth; `Townsfolk.xcodeproj` is generated and gitignored —
  never hand-edit or commit it
- After changing `project.yml`, run `just generate` and build to verify
- `Config/Debug.xcconfig` holds only what `project.yml` cannot express — the optional
  `#include?` of a gitignored `Config/Local.xcconfig` and the ad-hoc default it may
  override. Any other setting belongs in `project.yml`, and Release reads no xcconfig
  at all, so a local file can never change a Release or release-workflow build

## Local Signing Identity

- `Config/Local.xcconfig` is per-machine, gitignored, and refused by the commit-time
  guard (`scripts/guard/paths.sh`) — never commit one, and never put a Team ID or a
  certificate name into a tracked file, a commit message, or a pull request
- A build with no such file is signed ad hoc, exactly as CI and a fresh clone sign it;
  see `docs/getting-started.md` for when a developer needs one

## Toolchain Pinning

- `.xcode-version` is the single source of truth for the CI Xcode pin (every macOS job
  derives `DEVELOPER_DIR` from it); CLI tools are pinned in `mise.toml`
- This section is the one statement of the pin-bump policy; `mise.toml`, the
  `changing-gates` skill, and `check-pr-title.yml` point here rather than restate it
- Bot-bumped pins arrive as bot PRs, never by hand: Dependabot (`.github/dependabot.yml`)
  for SwiftPM (`Package.resolved`, prefix `deps:`) and GitHub Actions (prefix `ci:`),
  Renovate (`.github/renovate.json`, `enabledManagers: ["mise"]`, prefix `deps:`) for
  `mise.toml`. CI on the PR is the gate; merge when it is green. A SwiftLint or
  SwiftFormat bump may fire new rules — fix the code on that PR, never skip the bump
  (landing these PRs, and the human approval merging them needs: the
  `merging-dependency-prs` skill)
- Both wait 7 days after a release (Dependabot's `cooldown.default-days`, Renovate's
  `minimumReleaseAge`) before opening a PR, so a compromised fresh release has time to be pulled; note that
  SwiftPM itself has no resolver-level cooldown, so fresh installs
  are only protected by the committed `Package.resolved`
- `.xcode-version` is the one hand-bumped pin: neither bot has an ecosystem for it, and
  the value must name an Xcode that GitHub's macOS runner image actually installs
  (`/Applications/Xcode_<version>.app`), which no release feed tracks. Bump it by hand
  in a `ci:` PR once the runner image ships the new Xcode, keep
  `docs/getting-started.md`'s Xcode requirement in step, and let the PR's macOS jobs
  prove the path exists
- `.github/workflows/check-pr-title.yml` accepts the bots' prefixes (`deps`, `ci`); a
  prefix change in either bot config changes that list in the same PR.
  `scripts/checks/dependency-bots-agree.sh` (`just check-harness`) fails while a bot's
  prefix is missing or not a listed type, or the two bots' cooldowns disagree
