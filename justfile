# Development task runner — requires Just (https://just.systems)
# All commands also work without Just by running the underlying commands directly
# (see CONTRIBUTING.md). Tools come from mise (mise.toml pins the versions).

# Show available recipes
default:
    @just --list

# Install pinned tools, git hooks, and generate the Xcode project
install:
    mise install
    if git rev-parse --git-dir >/dev/null 2>&1; then git config core.hooksPath .githooks; else echo "Skipping git hook installation (not a Git repository)."; fi
    mise exec -- xcodegen generate
    @if command -v xcodebuild >/dev/null 2>&1; then xcode_local="$(xcodebuild -version | head -n1 | awk '{print $2}')"; xcode_pinned="$(cat .xcode-version)"; if [ "$xcode_local" != "$xcode_pinned" ]; then echo "warning: local Xcode $xcode_local differs from the CI-pinned $xcode_pinned — results may diverge from CI"; fi; fi
    just verify-hooks

# Regenerate Townsfolk.xcodeproj from project.yml
generate:
    mise exec -- xcodegen generate

# Format code
fmt:
    mise exec -- swiftformat .

# Format and auto-fix SwiftLint violations, then run the full lint check: some
# violations have no safe auto-fix, and the check reports what still needs a hand edit
[doc("Format, auto-fix SwiftLint violations, then run the full lint check")]
fix:
    mise exec -- swiftformat .
    mise exec -- swiftlint lint --fix --quiet
    just lint

# Run formatters and linters in check mode (swiftformat, swiftlint, shellcheck, actionlint, typos)
lint:
    mise exec -- scripts/lint.sh

# Verify the git hooks are installed and executable (skips under CI or ALLOW_MISSING_GIT_HOOKS)
verify-hooks:
    scripts/verify-hooks.sh

# Run the plain-bash tests for the scripts under scripts/ (through mise: the
# scripts/checks/ tests call the pinned `just`)
[doc("Run the plain-bash tests for scripts/ and the skills' Python suites")]
test-scripts:
    mise exec -- scripts/tests/run.sh

# Re-assert the harness's claims about itself: every check under scripts/checks/,
# each listed in AGENTS.md's Enforcement layers
[doc("Re-assert the harness's claims about itself (scripts/checks/)")]
check-harness:
    mise exec -- scripts/checks/run-all.sh

# Run tests with the 80% line-coverage and 75% function-coverage floors on TownsfolkCore
test:
    scripts/coverage.sh

# Run only the tests matching FILTER (swift test --filter), with no coverage floor —
# for fast local iteration; `just test` is still the gate
[doc("Run only the tests matching FILTER, with no coverage floor")]
test-fast filter:
    cd Packages/TownsfolkKit && swift test --filter '{{filter}}'

# Build the app (Debug)
build:
    mise exec -- xcodegen generate
    set -o pipefail && xcodebuild -project Townsfolk.xcodeproj -scheme Townsfolk -configuration Debug -derivedDataPath build/dev-derived-data build | mise exec -- xcbeautify --quiet

# Build (Debug), quit any running instance of this app, and launch the fresh
# build, left running until you quit it (scripts/run-app.sh)
[doc("Build (Debug), quit any running instance, and launch the fresh build")]
run: build
    scripts/run-app.sh

# Make macOS forget every permission (TCC) decision for this app — and only this
# app, whose bundle identifier is read from project.yml — so the next launch asks
# again (scripts/reset-permissions.sh)
[doc("Make macOS forget this app's permission (TCC) grants")]
reset-permissions:
    scripts/reset-permissions.sh

# Stream this app's unified-log output (subsystem == the bundle identifier
# project.yml declares), until you stop it with Ctrl-C
[doc("Stream this app's unified-log output (Ctrl-C to stop)")]
logs:
    bundle_id="$(scripts/bundle-id.sh)" && log stream --predicate "subsystem == \"${bundle_id}\"" --level debug

# Run the XCUITest launch test (may prompt for Accessibility permission on first local run)
uitest:
    mise exec -- xcodegen generate
    rm -rf build/LaunchUITests.xcresult
    set -o pipefail && xcodebuild test -project Townsfolk.xcodeproj -scheme Townsfolk -destination 'platform=macOS' -derivedDataPath build/dev-derived-data -resultBundlePath build/LaunchUITests.xcresult | mise exec -- xcbeautify

# Build Release and assert the app launches and stays alive
smoke:
    scripts/smoke_launch.sh

# Run all checks: verify hooks, format, lint, script tests, harness checks, test, build
# (CI's app job adds uitest + smoke)
[doc("Run all checks: verify-hooks, fmt, lint, test-scripts, check-harness, test, build")]
check: verify-hooks fmt lint test-scripts check-harness test build

# Regenerate the .claude/skills/ mirror from .agents/skills/ (run after any skill edit)
agents-sync:
    scripts/sync-agents.sh

# Fail if .claude/skills/ is not byte-identical to .agents/skills/ (writes nothing)
agents-check:
    scripts/sync-agents.sh --check

# Remove build artifacts and the generated project
clean:
    rm -rf build Packages/TownsfolkKit/.build Townsfolk.xcodeproj

# Create or update this repository's GitHub labels from .github/labels.yml
# (never deletes). Requires `gh`, authenticated against this repository: it is
# not a mise tool (see mise.toml), so it comes from your own PATH, not `mise exec --`.
[doc("Create or update GitHub labels from .github/labels.yml (never deletes)")]
labels:
    scripts/sync-labels.sh

# Create or update the "main" branch ruleset from .github/rulesets/main.json
# (admin-only: applying a ruleset needs repository admin permissions). Requires
# `gh`, authenticated against this repository: like `labels` above, it is not a
# mise tool, so it comes from your own PATH, not `mise exec --`.
[doc("Create or update the \"main\" branch ruleset (admin-only)")]
ruleset:
    scripts/apply-ruleset.sh

# Run the local-machine tests (TownsfolkPlatformTests): the adapter tests CI cannot run,
# because a runner has no logged-in GUI session and cannot be granted the permissions
# below. Sets RUN_LOCAL_MACHINE_TESTS=1, the opt-in the `.requiresLocalMachine` trait
# reads, so these run here and stay reported-as-skipped everywhere else. No coverage
# floor: adapters translate rather than decide, so `scripts/coverage.sh` still measures
# TownsfolkCore only, and `just test` is still the gate.
#
# Grants: today's suite needs none — NSWorkspace only needs a GUI session. A test that
# reaches for Accessibility, Input Monitoring, or Screen Recording needs that permission
# granted to the application that launched the run (your terminal, or Xcode) in System
# Settings › Privacy & Security; the test process inherits its launcher's grants and
# never gets its own. macOS reports a missing grant as an empty answer rather than an
# error, so such a test unwraps through `LocalMachineTests.require(_:requires:)`, whose
# failure names the grant to give instead of failing as a bare nil.
#
# Run it before a PR that touches an adapter, and paste the result in the PR: no gate
# can do it for you.
[doc("Run the local-machine adapter tests (TownsfolkPlatformTests) CI cannot run")]
test-local:
    cd Packages/TownsfolkKit && RUN_LOCAL_MACHINE_TESTS=1 swift test --filter 'TownsfolkPlatformTests'

# Prepare a release — `just release-prep <version>`, plus `--dry-run` to check
# without writing: sets MARKETING_VERSION, increments CURRENT_PROJECT_VERSION, and
# rolls CHANGELOG.md's [Unreleased] entries into a dated section. Writes those two
# files and nothing else — it refuses a dirty tree, a version that is not above the
# current one, and an empty [Unreleased], creates no commit, tag, or push, and
# prints the commands that do (scripts/release-prep.sh).
#
# `{{ args }}` is unquoted because just substitutes a variadic parameter as one
# string, with no array expansion: quoting it would hand the script `--dry-run 0.2.0`
# as a single argument. So an argument containing whitespace cannot come through this
# recipe — call the script directly for that (`scripts/release-prep.sh --root "dir
# with space" 0.2.0`), which only its tests need.
[doc("Set MARKETING_VERSION, bump the build, and roll CHANGELOG.md (no commit/tag/push)")]
release-prep *args:
    scripts/release-prep.sh {{ args }}
