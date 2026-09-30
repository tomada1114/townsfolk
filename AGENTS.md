# Project Guide

This file holds what every agent needs before it knows which task it is on: what the
app is, how to check a change, where code goes, and which decisions need a human. It is
the one guide Claude Code and Codex CLI share, and it leaves three things to others:

- **The conventions of one kind of change** belong to a skill under `.agents/skills/`,
  loaded when the work calls for it — [Skills](#skills) is the index.
- **The rules for one kind of file** belong to `.claude/rules/`, loaded by path —
  [Rules](#rules) lists them.
- **A value a gate enforces** — a lint rule, a format option, the coverage floor, a tool
  pin — belongs to its config (`.swiftlint.yml`, `.swiftformat`, `Package.swift`,
  `scripts/coverage.sh`, `mise.toml`); running the gate is how you learn it.

A rule that belongs to one of those lands there, and this file points to it rather than
keeping a second copy that goes stale.

## Overview

This is a macOS SwiftUI app built from a strict template: XcodeGen generates the
Xcode project from `project.yml`, all real code lives in a local Swift package
(`Packages/TownsfolkKit`), and quality gates (SwiftLint strict, SwiftFormat, Swift 6
language mode, an 80% line-coverage and a 75% function-coverage floor on the Core
module) are enforced from day one.

## Product

Section numbers (§) below refer to `docs/product/requirements.md`.

- **What it is, and who it is for** — Townsfolk is a small fictional town that lives in
  a window at the edge of your Mac screen. Its residents — people, text only in this
  version — post to a shared board shaped like a small social feed and keep
  conversations going on their own. You glance at it for a few seconds while you work,
  read it like a social app when you have a minute, and now and then post a line as one
  of the residents; the town answers over the following minutes, one resident at a
  time. It is not a tool: it exists to be pleasant to watch. It is for its developer
  first, at a Mac during work and breaks, and built so that others could use it too —
  every install founds its own town. Every word the town writes comes from Apple's
  on-device model through the Foundation Models framework: no server, no API key,
  nothing leaves the Mac (macOS 27 or later, Apple silicon, Apple Intelligence on).
- **The core interaction** — glance at the timeline and the town's status line and see
  the town moving; occasionally post one line and watch the town respond over time. If
  glancing does not show a living town, nothing else matters.
- **Non-goals** — moving anything from this list to a goal is the owner's decision, not
  an implementer's. The Later list (§2) is out of scope too, until
  `docs/architecture/roadmap.md` pulls an item in.
  - **Being useful** — no task management, no help with work, no accurate answers. The
    town is for watching.
  - **Instant replies** — every response is delayed by minutes; there is one generation
    path. A reply within seconds turns the town into a chat app.
  - **Running while out of sight** — no menu-bar agent, no background running while the
    window is closed or hidden; the pause and catch-up in §3.7 replace it.
  - **Following the time of day** — the town is as lively at 3 a.m. as at noon.
  - **Measuring engagement** — no analytics, no metrics, no telemetry.
  - **Network access** — none in this version (outside information is Later).
  - **Curating residents** — no creating, editing, or removing residents by hand, and no
    approving generated ones. Hand-picked lists run out and make every town the same.
  - **Editing your posts** — once residents have responded, an edit would make them wrong.
  - **Other reactions** — no reposts, quotes, emoji reactions, or follower counts (likes
    are Later).
  - **Feed conveniences** — no searching, filtering, bookmarking, or exporting the log. The
    town borrows a social feed's shape, not its utility features.
  - **Several towns, sync, accounts** — one town at a time, on one Mac, with no account.
  - **Pulling you back** — no notifications, Dock badges, sounds, streaks, or messages
    that the residents miss you. The town only moves while its window is visible, so there
    is nothing to announce, and a hook that pulls you back is exactly the compulsive use
    this app stays away from.
  - **Window extras** — no always-on-top, no showing on every Space, no launch at login,
    no global shortcut (the owner does not want them in this version). If the town stops
    too often because work windows cover it, always-on-top and every-Space are the first
    things to revisit.
- **Where these decisions are recorded** — `docs/product/requirements.md` (scope, the
  Later and Non-goals lists, and the reasoning in its §7 decision log);
  `docs/product/ux-flows.md` and `docs/design/ux-guidelines.md` (screens, flows, and UX
  policy); `docs/design/design-direction.md` (the visual direction behind the design
  lock); ADRs under `docs/architecture/adr/` for the hard-to-reverse choices.

## Quick Reference

```bash
just install   # Install pinned tools (mise), git hooks, and generate the Xcode project
just generate  # Regenerate Townsfolk.xcodeproj from project.yml
just fmt       # Format code (swiftformat)
just fix       # Format, auto-fix SwiftLint violations, then run just lint
just lint      # Lint (scripts/lint.sh: swiftformat --lint + swiftlint --strict + shellcheck + actionlint + typos)
just verify-hooks  # Verify the git hooks are installed and executable (scripts/verify-hooks.sh)
just test-scripts  # Run the plain-bash tests for scripts/ and the skills' Python suites (scripts/tests/run.sh)
just check-harness # Re-assert the harness's claims about itself (scripts/checks/run-all.sh)
just test      # Run tests with the 80% line / 75% function coverage floors on TownsfolkCore
just test-fast CounterTests  # Run only the matching tests, no coverage floor (iteration only)
just test-local    # Run the local-machine adapter tests (TownsfolkPlatformTests) CI cannot run
just build     # Build the app (Debug)
just run       # Build (Debug), quit any running instance, and launch the fresh build
just logs      # Stream this app's unified-log output (Ctrl-C to stop)
just reset-permissions  # Make macOS forget this app's permission (TCC) grants
just uitest    # Run the XCUITest launch test
just smoke     # Build Release and assert the app launches
just check     # Run all checks: verify-hooks → fmt → lint → test-scripts → check-harness → test → build
just agents-sync   # Regenerate the .claude/skills/ mirror from .agents/skills/
just agents-check  # Fail if .claude/skills/ differs from .agents/skills/
just clean     # Remove build artifacts and the generated project
just labels    # Create/update GitHub labels from .github/labels.yml (never deletes)
just ruleset   # Create/update the "main" branch ruleset from .github/rulesets/main.json (admin-only)
just release-prep 0.2.0  # Set MARKETING_VERSION, bump the build, roll CHANGELOG.md's [Unreleased] (no commit/tag/push)
```

Without Just: run the underlying commands listed in each `justfile` recipe
(see CONTRIBUTING.md).

## Validating a change

Run the narrowest check that can fail, then `just check` before you open a PR.
`just lint` runs `scripts/lint.sh`, the same script the pre-commit hook and CI's lint
job call.

| What you changed | The narrowest check that can fail |
|---|---|
| A Swift file under `Packages/TownsfolkKit/Sources/TownsfolkCore/` | `just test` |
| A test under `Packages/TownsfolkKit/Tests/TownsfolkCoreTests/` | `just test` |
| A view under `Packages/TownsfolkKit/Sources/TownsfolkUI/`, or anything under `App/` | `just build` |
| An adapter under `Packages/TownsfolkKit/Sources/TownsfolkPlatform/` | `just test` (it compiles under `swift test`); then `just test-local` for its real-OS test, whose output goes in the PR; `just build` if `App/` wires it |
| A test under `Packages/TownsfolkKit/Tests/TownsfolkPlatformTests/` | `just test-local` (`just test` and CI report these skipped — they are human-run) |
| A fake or a port contract under `Packages/TownsfolkKit/Tests/TownsfolkTestSupport/` | `just test` (the contract against the fake); then `just test-local` (the contract against the real adapter) |
| Formatting or style of any Swift file | `just lint` |
| A SwiftLint or SwiftFormat violation that may be auto-fixable | `just fix` (formats, runs `swiftlint --fix`, then `just lint` reports what still needs a hand edit) |
| One Core suite, while iterating | `just test-fast <filter>` (e.g. `just test-fast CounterTests`) — no coverage floor, so finish with `just test` |
| `Packages/TownsfolkKit/Sources/TownsfolkCore/Resources/Localizable.xcstrings`, or a `LocalizedStringResource` in Core | `just test` (`LocalizationTests` scans Core's `LocalizedStringResource(…)` calls and holds their keys and English to the catalog); `just build` to compile the catalog into the app |
| `project.yml`, or `Config/Debug.xcconfig` | `just generate && just build` |
| A test under `LaunchUITests/`, or launch behavior | `just uitest` |
| The Release configuration, or anything only a Release launch shows | `just smoke` |
| Behavior only the running app shows (a view's wiring, an OS integration, a log line) | `just run`, then `just logs` — no gate asserts it, so the PR carries the evidence instead (the `running-the-app` skill) |
| A shell script under `scripts/` (including the sourced `scripts/guard/*.sh`), or `.githooks/pre-commit` | `just lint`, then `just test-scripts` |
| `scripts/verify-hooks.sh` | `just lint`, then `just test-scripts`; `just verify-hooks` for the check itself |
| A harness check under `scripts/checks/` (including the sourced `scripts/checks/lib.sh`) | `just lint`, then `just test-scripts`; `just check-harness` for the checks themselves |
| A `just` recipe name, a workflow's `uses:`, `permissions:`, `concurrency:`, or `run:` shell, a Dependabot or Renovate commit prefix or cooldown, a skill's frontmatter, the Skills table, the `## Product` section, `.claude/settings.json`'s `permissions` rules, the Core import ban list (`.swiftlint.yml`'s `no_ui_import_in_core` or `ArchitectureBoundaryTests.forbiddenModules`), the gates `just check` or `ci.yml` runs, or a label an issue form, workflow, or bot config applies | `just check-harness` |
| A skill under `.agents/skills/` | `just agents-sync`, then `just agents-check` and `just check-harness`; `just test-scripts` too when the skill ships scripts (it runs their `scripts/tests/` unittest suite) |
| A workflow under `.github/workflows/` | `just lint`, then `just check-harness` |
| Markdown | `just lint` (its `typos` spell-check) |
| `mise.toml` | `mise install`, then `just check` |
| `.github/labels.yml`, or an issue form under `.github/ISSUE_TEMPLATE/` | `just lint` (its `typos` spell-check), then `just check-harness` (every applied label declared, once); `scripts/tests/sync-labels_test.sh` for `scripts/sync-labels.sh` itself |
| `.github/rulesets/main.json`, or `scripts/apply-ruleset.sh` | `scripts/tests/apply-ruleset_test.sh`; `just check-harness` for `main.json` (`scripts/checks/ruleset-contexts.sh` reads it) |

## Architecture

```
App/                        # Thin shell: @main entry point + resources, NO logic.
                            #   The composition root: builds TownsfolkPlatform adapters
                            #   and hands them to Core view models
Packages/TownsfolkKit/
├── Sources/TownsfolkCore/      # Domain logic + view models + the ports (protocols) OS
│                           #   code is reached through — platform-agnostic, no
│                           #   SwiftUI/AppKit/UIKit/Cocoa/ApplicationServices/
│                           #   Carbon/ServiceManagement import (enforced by lint
│                           #   and test), coverage-gated at 80% of lines
│                           #   and 75% of functions
├── Sources/TownsfolkUI/        # SwiftUI views — thin, delegate to Core view models
├── Sources/TownsfolkPlatform/  # OS-integration adapters behind Core ports (AppKit and
│                           #   friends) — translation only, no domain logic, and
│                           #   deliberately outside the coverage floor
├── Tests/TownsfolkTestSupport/ # Test code both test targets share: each port's fake and
│                           #   its contract function — a library target no product
│                           #   exports and no shipped module imports (enforced by
│                           #   test), outside the coverage floor
├── Tests/TownsfolkCoreTests/   # Swift Testing suites — CI-run, coverage-gated
└── Tests/TownsfolkPlatformTests/
                            # Adapter tests against the real OS — opt-in and human-run
                            #   (`just test-local`), reported as skipped everywhere else
LaunchUITests/              # XCUITest launch guarantee (XCTest by necessity)
Config/Debug.xcconfig       # Debug-only build settings project.yml cannot express:
                            #   the optional `#include?` of a gitignored
                            #   Config/Local.xcconfig (a local signing identity)
```

- New logic goes in `TownsfolkCore` with tests; views only render Core state
- The dependency direction is one-way: Core ← UI and Core ← Platform, both ← App.
  `TownsfolkUI` and `TownsfolkPlatform` are siblings and never import each other
- OS integration goes in `TownsfolkPlatform` as an adapter behind a `Sendable` port Core
  declares; a Core test substitutes a fake for that port, and `App/` picks the real one.
  Adapters translate and never decide — a decision belongs in Core, which is why
  Platform stays outside the coverage floor (`scripts/coverage.sh` measures Core only).
  The worked example is `FrontmostAppProviding` / `WorkspaceFrontmostAppProvider`
  (`docs/architecture.md` › Ports and adapters)
- The translation an adapter does *is* checked, just not by a gate: `Tests/TownsfolkPlatformTests`
  runs it against the real OS behind the `.requiresLocalMachine` opt-in, so a human runs
  it with `just test-local` and puts the output in the PR, while `just test` and CI
  report those tests as skipped (`.claude/rules/testing.md` › Where a Test Goes)
- A fake keeps the port's promises only while something checks it against the adapter:
  each port's fake and one contract function live in `Tests/TownsfolkTestSupport`, which
  `TownsfolkCoreTests` runs against the fake (`just test`) and `TownsfolkPlatformTests` against
  the real adapter (`just test-local`) (`.claude/rules/testing.md` › One Contract Suite
  per Port). It is test code: no shipped module imports it, which
  `ArchitectureBoundaryTests` enforces
- `TownsfolkCore` never imports SwiftUI, AppKit, UIKit, Cocoa, ApplicationServices, Carbon,
  or ServiceManagement — in any spelling, including `@preconcurrency import AppKit` and
  `import struct SwiftUI.Color`. SwiftPM cannot block a
  system framework, so this is enforced twice: `.swiftlint.yml`'s `no_ui_import_in_core`
  and the `ArchitectureBoundaryTests` suite; their module lists change together, and
  `scripts/checks/core-ban-lists-agree.sh` (`just check-harness`) fails when they differ.
  `os`/`OSLog` are deliberately *not* on that list — logging is neither a UI nor an
  OS-integration framework, so Core logs directly (`docs/architecture.md` › Logging)
- Shipped code logs through `os.Logger`, declared once in `TownsfolkCore`'s `AppLog`;
  `print`, `debugPrint`, and `NSLog` are rejected under `Packages/*/Sources/` and `App/`
  by `.swiftlint.yml`'s `no_print_in_sources` (`.claude/rules/swift.md` › Logging)
- `Townsfolk.xcodeproj` is generated — edit `project.yml` instead
- Four things are contract rather than private — Core's public API, the bundle
  identifier, `UserDefaults` keys, and file formats — and each changes only as
  `docs/architecture.md` › What is contract and what is private says

## Before changing the architecture

An app cut from this template records its architecture decisions as ADRs under
`docs/architecture/` — start at its `README.md`, the index, whose statuses say what is
decided and what is only proposed. `docs/architecture.md` describes the layers every app
starts with; the ADRs record what the app decided on top of them. A change to any of
these owes an ADR, as `recording-architecture-decisions` sets out:

- a new target (`project.yml`, `Package.swift`) or a new Core port;
- the app shape — a windowed app or a menu-bar agent;
- the sandbox posture — the App Sandbox on or off, or a new entitlement;
- persistence — where and in what format the app keeps state;
- a new dependency;
- distribution — the Mac App Store, Developer ID with notarization, an in-app updater;
- `deploymentTarget` in `project.yml`, with `platforms:` in `Package.swift`;
- a TCC permission — Accessibility, Input Monitoring, Screen Recording, or any other
  privacy grant;
- a shipped language beyond English, the `defaultLocalization` the template sets.

An agent writes an ADR as Proposed; only a human accepts it. An ADR records reasoning and
grants nothing: an entitlement, a signing change, or a new dependency still needs the
sign-off "Security and human approval" asks for. The template repository ships the index
empty — its own reasoning lives in `README.md`'s Design Philosophy, and ADRs belong to
the apps cut from it.

## Skills

Each skill owns one kind of change. Load the one whose subject you are working on.

Skills are authored under `.agents/skills/` — the path Codex CLI reads — and mirrored
into `.claude/skills/`, the only path Claude Code reads. Claude Code is therefore the
tool that sees the generated copy rather than the authored one:

- Edit a skill only under `.agents/skills/`, then run `just agents-sync` and commit
  both trees together. Never hand-edit `.claude/skills/`, and never edit only one side;
  `just agents-check` reports any drift (`scripts/sync-agents.sh`).
- The mirror is a real, committed, byte-identical copy, never a symlink: Codex follows
  a linked directory into its subdirectories and registers a nested
  `references/SKILL.md` as a skill of its own. `.gitattributes` marks it
  `linguist-generated`, so GitHub collapses it in pull request diffs.
- `.claude/rules/` and `.claude/settings.json` are Claude Code-only and stay where they
  are; they are not mirrored.

| Skill | Load it when you are working on |
|---|---|
| `smart-commit` | committing and pushing changes: grouping them into Conventional Commits, excluding sensitive files |
| `create-pr` | opening or updating a pull request: the `just check` pre-check, title, template, and checklist |
| `tdd` | a behavior change in `TownsfolkCore`: writing a failing Swift Testing test before the implementation |
| `designing-errors` | an `Error` type, a `throws`/`throws(E)` signature, a `do`/`catch`, or cancellation: Core error enums, typed throws, no user data in errors or logs, `CancellationError`, and mapping `OSStatus`/`NSError`/`AXError` in an adapter |
| `changing-gates` | a file that enforces rather than implements: `.swiftlint.yml`, `.swiftformat`, `Package.swift`'s `strictSettings`, `mise.toml`, `.githooks/pre-commit`, `scripts/lint.sh`, `scripts/coverage.sh`, the `scripts/guard/` commit-time guard, or a workflow — and which gate would catch a change |
| `triaging-issues` | filing or triaging an issue: the labels in `.github/labels.yml` (`just labels`), priority tiers, the `Depends on #N` convention, and routing a request from daily use (file, park as `on hold`, or drop) |
| `authoring-skills` | adding, editing, or reviewing a skill: authoring under `.agents/skills/`, the `just agents-sync` mirror, frontmatter, layout, and size limits |
| `updating-docs` | deciding whether a change owes a documentation update and which surface it lands on: `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `docs/*.md`, a skill, or a `///` comment |
| `recording-architecture-decisions` | the ADR tree under `docs/architecture/`: whether a change owes an ADR (a target or port, app shape, sandbox posture, persistence, a dependency, distribution, `deploymentTarget`, a TCC permission), an ADR's statuses, amending versus superseding, and fact discipline — every external claim with a URL and a checked date |
| `writing-repo-scripts` | writing or testing a shell script under `scripts/`, `.githooks/pre-commit`, or `scripts/tests/`: why bash, refusing or skipping outside a git checkout, the stderr contract by example, and `scripts/tests/lib.sh` |
| `running-the-app` | seeing a change work in the real app: `just run` and confirming the running process is the fresh build, reading `just logs`, screenshotting a window, a throwaway XCUITest, the human hand-off for a TCC prompt, and the evidence a PR then carries |
| `integrating-system-apis` | calling a macOS system API from `TownsfolkPlatform`: choosing the mechanism (`CGEventTap`, `AXObserver`, a Carbon hotkey), a C callback's refcon and teardown under Swift 6 strict concurrency, TCC-gated permissions (Accessibility, Input Monitoring, Screen Recording), and what can be tested where |
| `designing-core-logic` | shaping logic in `TownsfolkCore`: injecting time (`Clock`, a `() -> Date`), `Locale`, and a `RandomNumberGenerator`; one `Tuning` type for tunables; action-shaped `@Observable` view models; and the patterns deliberately not adopted |
| `designing-ui` | how a screen looks: HIG-based craft rules (system text styles, semantic and accent colors, light and dark, contrast, SF Symbols, window sizing, menu commands and shortcuts, motion, copy) and the app's design lock, recorded as an ADR under `docs/architecture/` |
| `building-swiftui-screens` | a view in `TownsfolkUI`: a thin renderer over a `TownsfolkCore` `@Observable` view model (how it holds its model, what `body` may contain), `#Preview` per state, accessibility identifiers and labels, Reduce Motion, keyboard reachability, and verifying a screen |
| `starting-an-app` | turning this template into a new app: `scripts/bootstrap.sh`'s rename, what the new repository keeps, its `just labels` and `just ruleset` setup, choosing the app shape (windowed or menu-bar agent), and deciding the sandbox posture |
| `shipping-issues` | shipping the open issue backlog: ranking issues by `priority: P0`-`P3`, implementing the top one, reviewing it with `/code-review`, and taking its PR through CI to merge |
| `steering-the-roadmap` | the app's direction in `docs/architecture/roadmap.md`: its Now / Next / Later horizons, who changes it and when, how the backlog and parked `on hold` issues feed it, and answering "what is next?" before `shipping-issues` |
| `localizing-the-app` | a string a person reads: the String Catalog `Localizable.xcstrings` in `TownsfolkCore`, `defaultLocalization`, Core view models returning `LocalizedStringResource` (`bundle: .module`), `Text(verbatim:)` in `TownsfolkUI`, keeping the catalog and `LocalizationTests` in step, `xcodebuild -exportLocalizations`, plurals, and what adding a language involves |
| `merging-dependency-prs` | landing open Dependabot (SwiftPM, GitHub Actions) and Renovate (`mise.toml`) PRs: the security checklist, one human approval for a listed batch of passing PRs, and a combined branch for conflicting bumps |

### Rules

The files under `.claude/rules/` load by path: each applies while you touch a file
matching its `paths:` globs.

| Rule | Loads when you touch |
|---|---|
| `.claude/rules/project.md` | `project.yml`, `Config/*.xcconfig`, `Packages/**/Package.swift`, `Packages/**/Package.resolved`, `mise.toml`, `.swiftlint.yml`, `.swiftformat`, `scripts/coverage.sh` |
| `.claude/rules/docs.md` | `docs/**/*.md`, `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md` |
| `.claude/rules/swift.md` | `Packages/**/*.swift`, `App/**/*.swift` |
| `.claude/rules/testing.md` | `Packages/**/Tests/**`, `LaunchUITests/**` |

### Sub-agents

`.claude/agents/` defines three named sub-agent tiers a skill or session can hand a
step to by name (for example `subagent_type: executor`), each pinned to a model alias
(`opus`/`sonnet`, never a dated model ID, so the definitions do not go stale) and an
effort level:

| Agent | Model / effort | Takes |
|---|---|---|
| `executor` | `opus` / low | a settled spec with a clear pass/fail: implementation, tests, getting a check green, bulk edits, research that only collects |
| `architect` | `opus` / high | complex multi-file implementation, design judgment, review and bug finding, synthesis, a spec that still has holes |
| `worker` | `sonnet` / medium | single-shot, tool-free writing or checking from a complete brief |

These are Claude Code-only: like `.claude/rules/`, they are not mirrored, and Codex CLI
reads nothing under `.claude/agents/`. Under Codex CLI, a step a skill hands to one of
these agents runs inline in the main session instead.

## Security and human approval

Only what is mechanically decidable is blocked at commit time; whether a commit
*should* contain what it contains stays in PR review. See `scripts/guard/` for exactly
what is checked: the pre-commit hook's "Staged guard" section (`scripts/check-staged.sh`)
refuses a secret-shaped staged path or credential-shaped staged content.

Never read a secret-shaped file, even to check it: `.env`, `.env.*`, or `.envrc.*`
(the `.example`/`.sample`/`.template` samples excepted), anything under a `secrets/`
directory, `*.p12`, `*.pfx`, `*.p8`, `*.provisionprofile`, `*.mobileprovision`,
`*.keychain`/`*.keychain-db`, `*key*.pem`, `private-key.*`, `.netrc`,
`credentials.json`, `secrets.json`, and `Config/Local.xcconfig`. This is the same list
`scripts/guard/paths.sh` refuses to commit, so the read rule and the commit guard
agree (the guard also refuses `.claude/settings.local.json`, which is per-user
settings rather than a secret, so reading it is fine and only committing it is not);
if a task seems to need one, ask the human for the non-secret fact instead.

Get a human's sign-off before acting on any of these. No file in this repository
blocks them mechanically today — this section is the rule itself, not a description
of a check that enforces it.

- Touching `App/Townsfolk.entitlements`, a signing identity — including the Debug
  signing `Config/Debug.xcconfig` and `project.yml` set up — or any signing,
  notarization, or release secret. Creating your own `Config/Local.xcconfig` is not
  such a change: it is gitignored, never committed, and changes nobody else's build.
- Creating or pushing a release tag.
- Editing `.claude/settings.local.json`, or a user-level settings file such as
  `~/.claude/settings.json`: an agent adding an `allow` rule there widens its own
  permissions, and neither file is committed, so no review ever sees it. The committed
  `.claude/settings.json` is reviewed in its pull request like any other file.
- Adding a new package dependency — see the dependency policy in
  `.claude/rules/project.md`.
- Weakening any gate: lowering the coverage floor, disabling or relaxing a SwiftLint
  rule, or widening a workflow's `permissions:`. If a gate looks wrong, say so and let
  a human decide. In this repository that also means any of these, when used to make
  a failing check pass:
  - `// swiftlint:disable` (including `:next` and `:this`) or `// swiftformat:disable`,
    or adding a path to `.swiftlint.yml`'s or `.swiftformat`'s excludes
  - `@unchecked Sendable` or `nonisolated(unsafe)` to silence a concurrency diagnostic
  - `.disabled(…)` or `withKnownIssue` on a failing test
  - excluding a file or target from coverage (`scripts/coverage.sh`)
  - deleting an assertion, or loosening one (`#expect`, `#require`) until it passes
  - `continue-on-error` on a CI job or step, or `git commit --no-verify`
- Working around a denied command. When a command is denied — by
  `.claude/settings.json`, a hook, or a human — re-spelling it (`git -C . …`,
  `bash -c '…'`, bundled short flags such as `-anm`, an alias or script wrapper) is
  forbidden. Stop and ask.
- Any write to a remote: `git push`, `gh pr create`, or any other remote write that
  is not performed by a script this repository ships. `scripts/sync-labels.sh`
  (`just labels`) is such a script for labels: it only ever creates or updates a
  label `.github/labels.yml` declares, via `gh label create --force`, and never
  deletes one — but running it against the live repository still needs sign-off
  before its first run there, the same as any other remote write. `scripts/apply-ruleset.sh`
  (`just ruleset`) is the same kind of script for branch protection: it only ever
  creates or updates the ruleset named "main" from `.github/rulesets/main.json`,
  needs repository admin permissions to succeed, and still needs sign-off before
  its first run against the live repository.

Standing exceptions: invoking one of these skills is the sign-off for the remote
writes that skill exists to make, for that invocation only.

- `smart-commit`, when asked to push: pushing the commits it made to the current
  branch.
- `create-pr`: pushing the current branch and creating or updating its pull request.
- `shipping-issues`: the writes its `SKILL.md` lists — priority and `blocked:` labels
  on open issues, branches and pushes, the pull request, merging it once CI passes,
  the follow-up issues and comments it files, and removing the branches and worktrees
  it created.

None of them covers anything else in the list above: a force push or other history
rewrite, `--no-verify`, weakening a gate, entitlements or signing, a release tag, a
new dependency, `just labels`, or `just ruleset`. A skill that reaches one of those
stops and asks.

### What no local gate sees

Every local layer can be skipped, so these reach `main` only if CI or GitHub stops them
(see "Enforcement layers" for the gaps each one leaves):

- `git commit --no-verify`, a clone where `just install` never ran, or a commit made
  outside this checkout's hooks — the pre-commit hook and staged guard never run.
- An edit made through GitHub's web UI or API, which touches no local hook.
- A secret inside a file whose path and content pattern the guard does not know.
- Any tool other than Claude Code: `.claude/settings.json` binds nothing else.

### GitHub settings a new repository must enable

"Use this template" copies files, not settings, so a repository's admin turns these on
once under Settings › Advanced Security (Code security on older UIs):

- **Secret scanning** and **Push protection** — the server-side layer for secrets that
  the staged guard misses or a bypass skips; push protection blocks a detected secret
  at `git push`.
- **Private vulnerability reporting** — `SECURITY.md` sends reporters to a private
  security advisory, which this setting enables.
- **Dependabot alerts** — `.github/dependabot.yml` configures version updates; alerts
  for known-vulnerable dependencies are a separate switch.
- The `main` ruleset, applied by `just ruleset`. `.github/rulesets/main.json`
  deliberately lists no `bypass_actors`: a bypass lets an admin, or an agent acting
  with an admin's token, merge without the PR and green checks the ruleset exists to
  require, and an emergency change can still go through a PR.

## Repository scripts

Every script under `scripts/` follows these rules, whoever writes it
(`scripts/tests/lib.sh`, `scripts/checks/lib.sh`, and the `scripts/guard/*.sh`
libraries are sourced, so they carry no shebang or `set` line of their own). The
reasons behind them, with worked examples, are in the `writing-repo-scripts` skill:

- `#!/usr/bin/env bash` and `set -euo pipefail`, and bash 3.2-compatible (macOS
  `/bin/bash`): no associative arrays, no `mapfile`/`readarray`, no `${var,,}`, and no
  `"${arr[@]}"` on a possibly empty array under `set -u` (use `${arr[@]+"${arr[@]}"}`).
  Under `pipefail`, never pipe into a reader that exits early (`grep -q`, `head`): feed
  it a here-string, `grep -qxF -- "${x}" <<<"${list}"`.
- `shellcheck`-clean — `scripts/lint.sh` checks every tracked `*.sh`
  outside the generated `.claude/skills/` mirror.
- Pinned tools are called by bare name; the caller provides PATH (`mise exec -- …`
  locally and in `just` recipes, `jdx/mise-action` in CI). Beyond that, assume only
  `git` and POSIX utilities, and no GNU- or BSD-only flag (`sed -i`, `readlink -f`,
  `mktemp -t`) — the scripts run on macOS and on CI's Ubuntu. A script whose job is
  a GitHub write (`scripts/sync-labels.sh`, `scripts/apply-ruleset.sh`) may also
  depend on `gh`: like `git`, it is assumed on PATH rather than routed through
  `mise exec --`, since it is not a mise tool (see `mise.toml`) — its tests stub it
  out, so `just check` never needs the real binary.
- Failure contract: the first stderr line is `ERR_<STAGE>_<WHAT>: <what failed>`, then
  `Expected:`, `Actual:`, and `Next:` lines (the next safe command); exit 1. List the
  codes in the script's header comment. Never print a secret value.
- Never assume the checkout is the only repository on the machine. A script that
  enumerates or rewrites tracked files refuses to run outside a git work tree (the
  `scripts/bootstrap.sh` pattern); a check that is meaningless outside one skips with a
  one-line notice instead. Each script's header states which it does.
- Every script directly under `scripts/` has a test file `scripts/tests/<script-name>_test.sh`
  built on `scripts/tests/lib.sh`, and `scripts/tests/run.sh` (`just test-scripts`,
  part of `just check` and CI's lint job) runs them all — concurrently, so a test file
  must share no state with any other: its own throwaway repository or temp directory,
  its own stubs, and only read-only use of the checkout. The runner itself is covered
  by `scripts/tests/run_test.sh`. A test works in a throwaway
  repository or temp directory, never the real checkout, and fakes external commands
  with `stub_command`. A sourced library under `scripts/guard/` gets its own test file
  too, `scripts/tests/guard-<library>_test.sh` (`guard-paths_test.sh`,
  `guard-credentials_test.sh`). The harness checks under `scripts/checks/`, their
  runner `run-all.sh`, and their sourced `lib.sh` share one test file,
  `scripts/tests/checks_test.sh`, which builds a fixture tree per failure mode and
  points each check at it with `--root`. Known exceptions, each with its reason:
  `bootstrap.sh` (exercised end to end by CI's `bootstrap-smoke` job); `coverage.sh`,
  `smoke_launch.sh`, and `package_dmg.sh` (need Xcode and a build; exercised by the
  `test`, `app`, and `release` jobs) — `coverage.sh` still has a partial test file,
  `scripts/tests/coverage_test.sh`, which stubs `swift` to cover its rejection of the
  removed environment override and its line- and function-floor comparisons, but not
  a real coverage run.
  `bootstrap.sh` also predates the failure contract and does not follow it yet, and
  neither does `coverage.sh`'s below-the-line-floor failure (its function-floor
  failure, `ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR`, does).

## Enforcement layers

The rules in this file are enforced by these layers, from mechanical to procedural:

| Layer | Fires on | Applies to | Holds |
|---|---|---|---|
| `.githooks/pre-commit` | `git commit` | anyone who ran `just install` | `scripts/lint.sh --staged-tree` — `swiftformat --lint` and `swiftlint --strict` on the staged Swift files |
| `.swiftlint.yml`'s `no_ui_import_in_core` custom rule and `ArchitectureBoundaryTests` (`Packages/TownsfolkKit/Tests/TownsfolkCoreTests/`) | the lint rule: `git commit` (via the hook's `swiftlint --strict`), `just lint`, and CI's `lint` job; the test: `just test` and CI's `test` job | every author | `TownsfolkCore` imports none of SwiftUI, AppKit, UIKit, Cocoa, ApplicationServices, Carbon, or ServiceManagement, including attributed and kind-qualified imports — enforced twice, so removing either mechanism leaves the other. The test alone also holds the sibling boundary: `TownsfolkUI` and `TownsfolkPlatform` never import each other |
| `.swiftlint.yml`'s `no_print_in_sources` custom rule | `git commit` (via the hook's `swiftlint --strict`), `just lint`, and CI's `lint` job | every author | no `print(`, `debugPrint(`, or `NSLog(` call site under `Packages/*/Sources/` or `App/` — shipped code logs through `TownsfolkCore`'s `AppLog` (`os.Logger`), whose output survives an `open`-launched `.app` and is what `just logs` streams. A mention inside a comment or a string literal does not count, and test targets are exempt |
| `scripts/verify-hooks.sh` (`just install`'s last step, and `just check`'s first) | `just install` and `just check` | anyone who runs either | git resolves the hooks directory to `.githooks/` and `.githooks/pre-commit` is executable — skips under CI or the `ALLOW_MISSING_GIT_HOOKS` opt-out |
| `scripts/check-staged.sh` (the hook's "Staged guard" section; the rules live in `scripts/guard/`) | `git commit` when any change is staged, with or without a Swift file | anyone who ran `just install` | no obviously secret-shaped path (`.env*`, `.envrc.*`, `secrets/`, signing material, `Config/Local.xcconfig`, `.claude/settings.local.json`) or credential-shaped content (private-key header, GitHub token, AWS access key id, AWS secret access key next to its variable name, Anthropic or OpenAI API key, Slack token, Google API key, Stripe live key, JWT) lands in a commit; staged deletions are never inspected |
| `scripts/sync-agents.sh --check` (the hook's "Skills mirror" section, `just lint`, and CI's `lint` job) | `git commit` when a staged path is under `.agents/skills/` or `.claude/skills/`; unconditionally on `just lint` and CI | every author | `.agents/skills/` and `.claude/skills/` stay byte-identical |
| `scripts/checks/run-all.sh` (`just check-harness`, part of `just check` before `just test`) | `just check-harness`, `just check`, and CI's `lint` job | every author | the harness's claims about itself stay true — every `just <recipe>` in this file exists, every workflow has a top-level `permissions:` and every non-local `uses:` (workflows and composite actions) is pinned to a full SHA with a `# v…` comment, no workflow grants a `write` scope or a `read-all`/`write-all` shorthand at the top level (a write goes on the job that needs it, and no job takes a shorthand), every workflow triggered on `pull_request` declares a top-level `concurrency:`, and every declared group varies per run, is unique to its workflow unless it names `github.workflow`, and never cancels in progress on a `push` except through a `github.event_name` expression, every `run:` step (composite actions included) resolves to `shell: bash` (`-eo pipefail`) or opens with a `set` carrying `-e` and `pipefail`, every Dependabot entry's and Renovate's commit prefix is set to a type the PR-title check's `types` accepts and their release cooldowns are set and agree, every skill's frontmatter is exactly a matching `name` and a `description`, no `SKILL.md` sits below a skill's top directory and every skill's `description` is printable ASCII, at most 1,024 characters, and free of unquoted values Codex CLI's YAML parser rejects, the Skills table matches `.agents/skills/`, every `Bash(just <recipe>…)` rule in `.claude/settings.json` names a recipe the justfile defines, every required status-check context in `.github/rulesets/main.json` matches a job `name:` (or id) in a workflow triggered on `pull_request`, `.swiftlint.yml`'s `no_ui_import_in_core` regex and `ArchitectureBoundaryTests.forbiddenModules` ban the same modules, the gates `just check` runs and the `run:` steps of `.github/workflows/ci.yml` match in both directions apart from the reasoned exception list in `scripts/checks/just-check-matches-ci.sh`, every label an issue form, a workflow, Dependabot (including its implied `dependencies` label), Renovate, or `scripts/label-pr.sh`'s type-to-label mapping applies is declared in `.github/labels.yml` and no label is declared there twice, and the `## Product` section above stays a `TODO:` skeleton here while `project.yml` still names the template's app-name placeholder and holds no `TODO:` marker once `scripts/bootstrap.sh` has renamed this into an app |
| `.claude/settings.json` — its only two top-level keys, `permissions` and `hooks` | every tool call Claude Code makes in this checkout | Claude Code only — Codex CLI and a human read nothing here | the routine local loop runs without a prompt: the `just` recipes that read, build, or test; `swift`, `xcodebuild`, `xcrun`, `xcodegen`, and the pinned lint and format tools, directly or through `mise exec --`; local `git` short of a push; read-only `gh` (`gh issue view`/`list`, `gh pr view`/`list`/`checks`/`diff`, `gh run view`/`list`, and the other list, view, and `GET` calls); read-only search tools; web search; and fetches from the stack's documentation domains. Everything that writes beyond the working tree is deliberately absent from `allow` — `just labels`, `just ruleset`, `just release-prep`, `just reset-permissions`, `just install` (it writes `core.hooksPath` and installs tools), `just clean` (it deletes the generated project and the build artifacts), `git push`, `gh pr create`, `gh pr merge`, `gh issue create` — so it still stops for the sign-off "Security and human approval" asks for, and `ask` pins the ones a broader rule would otherwise cover or an auto-approving session might wave through: `just labels`, `just ruleset`, `just release-prep`, `just reset-permissions`, `just clean`, `xcrun notarytool`/`altool`, `gh release create`, `gh repo edit`/`delete`, `gh issue delete`, and adding or updating a package with `swift package`; `just logs` is absent for a different reason, that it streams until Ctrl-C and would hang an unattended call. `deny` refuses `git commit --no-verify`/`-n`, a force push, and an edit to `App/*.entitlements`; JSON carries no comments, so read the deny list as five groups — `--no-verify`, `-n`, `--force`/`-f`, `--force-with-lease` with and without `=<ref>`, and a `+refspec` push, each written in the leading, trailing, and mid-command position. It is a prompt policy, not a boundary: a deny rule matches the command text Claude Code writes, so another spelling — `git -C . push --force`, `bash -c '…'`, or a bundled short flag such as `git commit -anm "…"`, which no text rule can decompose — is not stopped by it, and none of this constrains a human at a shell. `hooks` holds one `PostToolUse` hook, `scripts/format-edited-file.sh`, that runs `swiftformat` on the one `.swift` file an `Edit`/`Write`/`MultiEdit` touched inside the checkout (any other path is skipped) and reports a swiftformat failure back to the agent (exit 2) instead of hiding it, a convenience that formats an agent's edit on this host only — the git hook, not it, is the gate. The file registers no plugin marketplace and enables no plugin: skills ship in-repo under `.agents/skills/` |
| CI's `lint`, `test`, and `app` jobs (`.github/workflows/ci.yml`) | push to `main` and every pull request | everyone | the full gate: `scripts/lint.sh` (format, lint, shellcheck, actionlint, typos, the skills-mirror check), the script tests (`scripts/tests/run.sh`), the harness checks (`scripts/checks/run-all.sh`), tests with the coverage floor, build, UI test, and Release smoke |
| This file | read at session start | every agent | everything else — the reasons behind the rules above |

These gaps are deliberate. Closing one means adding a mechanism that enforces it —
a hook, a harness check, or a CI job — and then updating its row in the table above and
removing or narrowing its bullet here:

- **`git commit --no-verify` bypasses the hook**, and nothing in this repository blocks
  it for every author. `.claude/settings.json`'s `deny` list refuses the usual spellings
  on Claude Code alone, and only as written — `git -C . commit --no-verify` or the same
  command inside `bash -c` is not matched. "Never bypass the hooks" therefore still holds
  as an instruction, and CI is the backstop — except for the staged guard, which no CI
  job reruns over a pull request's diff: GitHub push protection and secret scanning are
  the server-side layer for secrets, and `.github/workflows/gitleaks.yml` scans the full
  git history weekly with a pinned, checksum-verified gitleaks, so a secret that slipped
  past both is found after the fact rather than never.
- **Hooks are absent on a bare clone until `just install` runs**, because
  `core.hooksPath` is set by that recipe. `scripts/verify-hooks.sh` narrows this: it
  fails loudly at `just install` and `just check` time when git does not resolve the
  hooks directory to `.githooks/` or `.githooks/pre-commit` is not executable, so a
  clone whose hook silently failed to install no longer looks identical to one that
  succeeded. It does not close the gap — a contributor who runs neither `just install`
  nor `just check` still commits without hooks — so CI stays the backstop.
  `ALLOW_MISSING_GIT_HOOKS=1` opts out for an environment that genuinely cannot have
  git hooks (e.g. a read-only or sandboxed checkout); every failure names it.
- **Whether `main`'s ruleset is actually in force is invisible from the checkout.**
  The intended ruleset — PR required, checks green, no force-push or deletion — is
  defined as code in `.github/rulesets/main.json`; `just ruleset`
  (`scripts/apply-ruleset.sh`) creates or updates it via the GitHub API for whoever
  runs it as a repository admin. Nothing in the checkout verifies that it was
  actually applied to the live repository — that is visible only via
  `gh api repos/{owner}/{repo}/rulesets`, never from a git checkout. "Use this
  template" does not copy rulesets, so every repository created from this template
  still needs its own admin to run `just ruleset` once.
- **Everything in `.claude/settings.json` applies to Claude Code only.** The
  `PostToolUse` swiftformat hook formats the Swift file an agent edited on that one host; the git
  hook, not this hook, is the real gate. The `permissions` block decides which commands
  that host runs without stopping to ask, so it shapes where a human is consulted rather
  than what is possible: Codex CLI, another agent, and a human at a shell are bound by
  the instructions in this file and by the gates above, not by that file.
- **Nothing runs `Tests/TownsfolkPlatformTests` for you.** A CI runner has no logged-in GUI
  session and cannot be granted Accessibility, Input Monitoring, or Screen Recording, so
  those tests carry `.requiresLocalMachine` and are reported as skipped in `just test`
  and in CI. That is deliberate — a skip is visible where a missing test is not — and it
  leaves the run itself procedural: a change to an adapter is expected to come with
  `just test-local` output in the PR, and review is what notices when it does not.

## Review Checklist

Before submitting a PR:

1. `just check` passes (every step of the justfile's `check` recipe)
2. New public APIs have `///` doc comments explaining *why*
3. Tests cover the new functionality (happy path AND error path); a change under
   `Sources/TownsfolkPlatform/` also carries `just test-local` output in the PR, since no
   gate runs those tests
4. No new dependencies without justification (see .claude/rules/project.md)
5. User-facing changes have a `CHANGELOG.md` entry under `[Unreleased]`
6. Commits and the PR title follow Conventional Commits (English)

## Important Reminders

- All code, docs, commits, and PRs must be written in English. The one exception is a
  translated value in a `*.xcstrings` String Catalog — the entry for a language other
  than `en`; its key, its `comment`, and its English stay English (`localizing-the-app`)
- Do what has been asked; nothing more, nothing less
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing an existing file to creating a new one
- NEVER proactively create documentation files unless explicitly requested
- NEVER lower the coverage floor or disable safety lint rules to make a check pass
- A comment carries only what the code cannot: a non-obvious why, a trap the next edit
  would spring, an external constraint. Default to none, and keep the rest to a line or
  two — restating the code, or narrating how it came to be, is what the code and git
  already do. A `///` on public API is its contract and stays (`.claude/rules/swift.md`)
- A problem you find outside the task is recorded, not fixed: file it as an issue with
  what `triaging-issues` asks of a body — a type label, a `path:line`, and an observable
  close condition — or, where filing is not yours to do (it is a remote write; see
  "Security and human approval"), list it in the pull request description. Never widen
  the pull request to fix it
- Keep `.githooks/pre-commit` to what is mechanically decidable (lint, the skills
  mirror, the staged guard); a judgement call — a relaxed config, a deleted workflow, a
  lowered threshold — is weighed in PR review, not blocked by the hook.
  `changing-gates` › `.githooks/pre-commit` records why
