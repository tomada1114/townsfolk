# Contributing

Thank you for considering a contribution! This document explains how to set up
your development environment and submit changes.

## Prerequisites

Install these tools:

- [Xcode 26.5+](https://developer.apple.com/xcode/) (CI pins the exact version in
  `.xcode-version`)
- [mise](https://mise.jdx.dev/) — provides the pinned CLI tools from `mise.toml`
- [Just](https://just.systems/man/en/installation.html) (optional — you can run
  the underlying commands directly)

Then:

```bash
mise trust     # approve mise.toml (asked once per fresh clone)
just install
```

## Development Workflow

```bash
# Format
just fmt

# Format, auto-fix SwiftLint violations, then run the full lint check
just fix

# Lint (scripts/lint.sh: swiftformat --lint + swiftlint --strict + shellcheck + actionlint + typos)
just lint

# Run the plain-bash tests for scripts/
just test-scripts

# Re-assert the harness's claims about itself (recipe names, workflow pins, skills)
just check-harness

# Run tests with the coverage floor
just test

# While iterating: run only the matching tests, with no coverage floor
just test-fast CounterTests

# The adapter tests CI cannot run (real OS, local machine only) — run these by hand
# whenever you change something under Sources/TownsfolkPlatform, and put the output in the PR
just test-local

# Build the app
just build

# Build (Debug), quit any running instance, and launch the fresh build
just run

# Stream this app's unified-log output (Ctrl-C to stop)
just logs

# Make macOS forget this app's permission (TCC) grants, so the next launch asks again
# (docs/getting-started.md explains when you need this)
just reset-permissions

# Launch guarantee (Release build + alive check)
just smoke

# Run everything (verify-hooks → fmt → lint → test-scripts → check-harness → test → build)
just check

# Prepare a release: version bump + changelog roll, checked (docs/distribution.md)
just release-prep 0.2.0
```

**Without Just**, run the equivalent commands (`just check` is the justfile's
`check` recipe: verify-hooks, fmt, lint, test-scripts, check-harness, test, build):

```bash
mise install
git config core.hooksPath .githooks   # pre-commit lint gate (just install does this)
scripts/verify-hooks.sh               # confirm the hooks are installed and executable
mise exec -- swiftformat .
mise exec -- swiftlint lint --fix --quiet   # just fix = swiftformat, this, then scripts/lint.sh
mise exec -- scripts/lint.sh
mise exec -- scripts/tests/run.sh
mise exec -- scripts/checks/run-all.sh
scripts/coverage.sh
(cd Packages/TownsfolkKit && swift test --filter CounterTests)   # just test-fast CounterTests
(cd Packages/TownsfolkKit && RUN_LOCAL_MACHINE_TESTS=1 swift test --filter TownsfolkPlatformTests)  # just test-local
mise exec -- xcodegen generate
xcodebuild -project Townsfolk.xcodeproj -scheme Townsfolk -configuration Debug -derivedDataPath build/dev-derived-data build
scripts/run-app.sh               # just run — quits the running instance, then launches
scripts/bundle-id.sh             # the bundle identifier project.yml declares
log stream --predicate "subsystem == \"$(scripts/bundle-id.sh)\"" --level debug   # just logs
scripts/reset-permissions.sh     # just reset-permissions — resets TCC for this app only
rm -rf build/LaunchUITests.xcresult
xcodebuild test -project Townsfolk.xcodeproj -scheme Townsfolk -destination 'platform=macOS' -derivedDataPath build/dev-derived-data -resultBundlePath build/LaunchUITests.xcresult
scripts/smoke_launch.sh
scripts/sync-agents.sh           # after editing .agents/skills/ (just agents-sync)
scripts/sync-agents.sh --check   # just agents-check
scripts/sync-labels.sh           # just labels — writes labels to the GitHub repo gh is pointed at
scripts/release-prep.sh 0.2.0    # just release-prep 0.2.0 — version bump + changelog roll
```

## Pull Request Process

1. Fork the repository and create a branch from `main`
2. Make your changes
3. Ensure `just check` passes
4. Write or update tests for your changes
5. Open a pull request using the PR template

### Code Standards

- New logic lives in `TownsfolkCore` with Swift Testing coverage (happy + error path)
- SwiftLint strict and SwiftFormat must pass with no warnings
- Maintain or improve the 80% line-coverage and 75% function-coverage floors on `TownsfolkCore`
- Public API carries `///` doc comments that explain *why*

### Commit Messages

Use Conventional Commits for both commits and PR titles:

```
<type>(<optional-scope>): <short summary>
```

Examples:

- `feat: add JSON export support`
- `fix(ui): handle window restoration`
- `docs: update installation guide`

Recommended types: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`,
`perf`, `build`, `deps` (dependency bumps).

### Changelog Policy

`CHANGELOG.md` (in [Keep a Changelog](https://keepachangelog.com/) format) is
the canonical, human-curated record of user-facing changes. Add an entry
under `[Unreleased]` for any user-facing change in the same PR that makes it.

GitHub's auto-generated release notes (via `.github/release.yml` categories)
are supplementary — useful for a quick PR-by-PR diff, but `CHANGELOG.md` is
what users should read to understand what changed in a release.

## Getting Help

If something is unclear, open an issue. We're happy to help you get started.
