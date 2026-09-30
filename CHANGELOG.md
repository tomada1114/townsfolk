# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/checks/labels-declared.sh` (`just check-harness`) now also reads
  `scripts/label-pr.sh`'s type-to-label mapping, so a PR type mapped to a label
  `.github/labels.yml` does not declare fails the harness instead of a live PR.
- Two harness checks, run by `just check-harness`, for workflow and dependency-bot
  hygiene. `scripts/checks/workflow-hygiene.sh` fails when a workflow grants a `write`
  scope or `read-all`/`write-all` at the top level instead of on the job, when a
  `pull_request` workflow has no `concurrency:` or a group is constant (a
  pull-request-only key such as `github.head_ref` counts as constant when the workflow
  has other triggers), shared with another workflow, or lets a push run be cancelled,
  and when a sh-family `run:` step does not resolve to `shell: bash` (`-eo pipefail`)
  or open with a `set` enabling `pipefail`. `scripts/checks/dependency-bots-agree.sh`
  fails when a Dependabot entry's or a JSON Renovate config's commit prefix is
  missing, has no type, or is not a type `check-pr-title.yml` accepts, or when their
  release cooldowns are missing or disagree; a JSON5 Renovate config gets a notice.
  Both read YAML through a new line-based `check_yaml_flatten` helper in
  `scripts/checks/lib.sh`, and a reader that fails reports `ERR_CHECK_READ_FAILED`
  (#129).
- Renovate now opens a PR when gitleaks releases a new version (a regex manager on
  `.github/workflows/gitleaks.yml`); the checksum stays a manual step, fail-closed because
  the workflow now also runs on a pull request that edits it; documented in the workflow
  and in `changing-gates`.
- A `MyAppTestSupport` target in `Packages/MyAppKit/Package.swift` for test code both
  test targets share, and one contract suite per port in it:
  `FrontmostAppProvidingContract` checks that every non-`nil` answer of a
  `FrontmostAppProviding` names the application (a non-empty `name`) across repeated
  calls. `MyAppCoreTests` runs it against `FakeFrontmostAppProvider` on every
  `just test` and in CI, and `MyAppPlatformTests` runs it against
  `WorkspaceFrontmostAppProvider` under `.requiresLocalMachine` (`just test-local`).
  The target's sources live under `Tests/MyAppTestSupport`, outside the `MyAppCore`
  coverage floors; no product exports it, and `ArchitectureBoundaryTests` fails if
  `MyAppCore`, `MyAppUI`, or `MyAppPlatform` imports it.

- `scripts/label-pr.sh`, tested by `scripts/tests/label-pr_test.sh`, now labels pull
  requests for `.github/workflows/pr-label.yml`, which runs it from a checkout of the
  base SHA. It maps every type the PR title check accepts, including `!` (`chore`,
  `deps`, and the rest were unlabeled before), removes a type label a retitle left
  stale, and never creates a label: the old colorless `gh label create` fallback is
  gone, and a label missing from `.github/labels.yml` fails the job instead.
- String Catalog localization plumbing: `Packages/MyAppKit/Package.swift` sets
  `defaultLocalization: "en"`, and `MyAppCore` ships
  `Sources/MyAppCore/Resources/Localizable.xcstrings` (English only). Core view models
  now own the wording and return `LocalizedStringResource`:
  `FrontmostAppViewModel.label` replaces `displayName` and `unavailableDisplayName`,
  and `CounterViewModel.resetTitle`, `decrementLabel`, and `incrementLabel` replace the
  view's "Reset" title and its "Decrement" and "Increment" accessibility labels. `LocalizationTests`
  scans `Sources/MyAppCore` for `LocalizedStringResource(…)` calls and fails when one
  lacks an explicit key, a `defaultValue`, or `bundle: .module`, when a declared key is
  missing from the catalog or a catalog key is declared nowhere, or when the catalog's
  English differs from the code's. A `localizing-the-app` skill holds the
  rules, `AGENTS.md`'s English-only rule gains one exception (translated values in a
  `*.xcstrings` catalog), and a shipped language beyond English is now an ADR trigger.
- A weekly `.github/workflows/gitleaks.yml` workflow that runs gitleaks 8.30.1 over
  the full git history to find leaked secrets. The release binary is pinned and its
  checksum verified, the job has `contents: read` only, and findings are redacted in
  the log. `.gitleaksignore` lists the exact fingerprints of known fake fixtures.
- A function-coverage floor beside the 80% line floor on `MyAppCore`:
  `scripts/coverage.sh` (`just test`, CI's test and release jobs) also sums llvm-cov's
  function counts for `Sources/MyAppCore/` from the same export and fails below
  `readonly FUNCTION_COVERAGE_FLOOR=75` with `ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR`, so a
  Core function no test calls can no longer hide under the line floor. Measured when
  set: 19 of 23 functions (82.6%) — every named function is tested, and the four misses
  are compiler-generated autoclosures (`os.Logger` interpolations, a
  `preconditionFailure` message) that llvm-cov counts as functions. The per-file report
  now shows lines and functions, and `scripts/tests/coverage_test.sh` covers the new
  comparison.
- Three harness checks, run by `just check-harness`, for lists that were kept in sync
  by hand: `scripts/checks/core-ban-lists-agree.sh` fails when `.swiftlint.yml`'s
  `no_ui_import_in_core` regex and `ArchitectureBoundaryTests.forbiddenModules` ban
  different modules; `scripts/checks/just-check-matches-ci.sh` fails when a
  `just check` gate is not run by `.github/workflows/ci.yml` or a CI `run:` step runs
  something `just check` does not, apart from a reasoned exception list in the script
  (`verify-hooks` and `fmt` local-only; `uitest`, `smoke`, and the `bootstrap-smoke`
  job CI-only); and `scripts/checks/labels-declared.sh` fails when an issue form, a
  workflow, Dependabot (including its implied `dependencies` label), or Renovate
  applies a label `.github/labels.yml` does not declare, or when labels.yml declares a
  label twice.
- A `steering-the-roadmap` skill and a `docs/architecture/roadmap.md` skeleton, linked
  from the ADR index but not an ADR: the app's direction as Now / Next / Later outcomes
  with no dates, filled in after `AGENTS.md`'s `## Product`. The skill says who changes
  the page (the owner decides; an agent proposes in a pull request) and when, how
  closed issues and parked `on hold` issues feed it through `triaging-issues`, and that
  a roadmap line records direction and never authorizes implementation.
- `designing-ui` and `building-swiftui-screens` skills. `designing-ui` holds the macOS
  craft rules this repository adds on top of Apple's Human Interface Guidelines (each
  cited with its URL) and the per-app design lock — accent color, type, spacing,
  density, symbols, window sizing, motion, and copy style — which an app records as an
  ADR under `docs/architecture/` with the next free number (`references/design-lock.md`).
  `building-swiftui-screens` covers thin `MyAppUI` views over `MyAppCore` `@Observable`
  view models: how a view holds its model, what `body` may contain, `#Preview` per
  state, accessibility identifiers and labels, Reduce Motion, keyboard reachability, and
  verifying a screen.
- `AGENTS.md` opens with what it owns and what it leaves to skills, `.claude/rules/`,
  and gate configs, and its "Important Reminders" gain three conventions: a comment
  carries only what the code cannot, a problem found outside the task is filed as an
  issue (or listed in the pull request) rather than fixed in it, and the pre-commit
  hook stays limited to what is mechanically decidable.
- `docs/architecture.md` › "What is contract and what is private": Core's public API,
  the bundle identifier, `UserDefaults` keys, and file formats are contract, each with
  what depends on it and what changing it requires; everything else is private.

- The commit-time staged guard now also refuses `.envrc.*` (samples excepted) and
  `.claude/settings.local.json` by path, and Anthropic, OpenAI, Slack, Google API,
  Stripe live (`sk_live_`/`rk_live_`; test keys stay allowed) and JWT shapes, plus an
  AWS secret access key assigned to its variable name, by content.
- `authoring-skills` gains a Conventions section: what the `**REQUIRED:**` and
  `**BACKGROUND:**` cross-reference markers mean and when a sibling is named bare,
  that example code in a skill is a deletable illustration nothing builds or tests
  from, and that a platform skill holds only this repository's decisions and links
  Apple's documentation instead of restating it. `tdd`, `merging-dependency-prs`,
  `starting-an-app`, and `running-the-app` now mark their hand-off pointers that way.

- `authoring-skills` records where a skill lives: in `.agents/skills/` by default,
  never a committed plugin marketplace, and when a ref-pinned shared plugin is allowed.

- `changing-gates` records why `.githooks/pre-commit` stays lint-only (no
  formatting, compiling, or related tests).

- `.claude/rules/testing.md` now covers an oracle independent of the implementation,
  one contract suite per port run against both the fake and the adapter (worked through
  for `FrontmostAppProviding`), a test clock or zero `Tuning` delay instead of sleeps,
  a per-test temporary directory, plain `import MyAppCore` instead of `@testable
  import`, and when a test belongs in `LaunchUITests`. `.claude/rules/swift.md` now
  covers an exhaustive `switch` without `default:` over Core's enums, `package` access
  for cross-module internals (invisible to `App/`), and where constants live.
- The `triaging-issues` skill's "Requests from daily use" section: a friction or
  idea raised while using the app is filed now, parked as `on hold` with its reason,
  or dropped with the reason stated, and a parked issue is promoted or closed only by
  a decision.

- The `starting-an-app` skill now ends the app-shape and sandbox-posture steps by
  writing ADR 0001 (app shape) and ADR 0002 (sandbox posture), as Proposed, in the
  new app's `docs/architecture/` tree.
- `scripts/checks/ruleset-contexts.sh`, run by `just check-harness`: fails when a
  required status-check context in `.github/rulesets/main.json` matches no job `name:`
  (or id, when a job has none) in a workflow triggered on `pull_request`, so renaming a
  CI job can no longer leave a required check that never reports and blocks every PR.
  A `${{ … }}` expression in a job name matches any text; `pull_request_target` does
  not count as a pull_request trigger.
- A `merging-dependency-prs` skill for landing Dependabot (SwiftPM, GitHub Actions) and
  Renovate (`mise.toml`) PRs: a security checklist, one human approval per invocation
  for a listed batch of passing PRs, a combined branch for conflicting bumps, and
  failure modes. It points to `.claude/rules/project.md` › Toolchain Pinning for the
  bump policy rather than restating it.
- Private-repository setup steps in `README.md` "Using This Template" and the
  `starting-an-app` skill (`references/private-repository.md`): which workflows to
  delete (Scorecard, CodeQL, Dependency Review), the `release.yml` attestation step to
  remove, and the `Dependency Review` required context to drop before `just ruleset`.

- `AGENTS.md` "Security and human approval" now forbids reading secret-shaped files
  (the list `scripts/guard/paths.sh` refuses to commit), requires sign-off before
  editing `.claude/settings.local.json`, lists what no local gate sees, and lists the
  GitHub settings a new repository must enable (secret scanning, push protection,
  private vulnerability reporting, Dependabot alerts) and why the `main` ruleset has
  no bypass actor.

- `.claude/rules/project.md`'s Toolchain Pinning is now the one statement of the
  pin-bump policy: bot PRs (Dependabot `deps:`/`ci:`, Renovate `deps:`) after a 7-day
  cooldown, and `.xcode-version` as the single hand-bumped pin with the reason and
  procedure. The `changing-gates` skill, `mise.toml`, and `check-pr-title.yml` point to
  it instead of contradicting it.
- `scripts/checks/skills-descriptions.sh` (run by `just check-harness`) fails on a
  `SKILL.md` nested below a skill's top directory (`ERR_CHECK_SKILL_NESTED`), and on a
  skill `description` over 1,024 characters, one containing a non-ASCII character, or
  an unquoted frontmatter value Codex CLI's YAML parser rejects
  (`ERR_CHECK_SKILL_DESCRIPTION`). The em-dashes in the `changing-gates`,
  `integrating-system-apis`, `shipping-issues`, and `starting-an-app` descriptions are
  now ASCII hyphens.
- A `designing-core-logic` skill: how `MyAppCore` logic is shaped — time (`Clock`,
  an injected "now"), `Locale`, and a `RandomNumberGenerator` injected with a test
  substitute for each, tunables in one `Tuning` type, action-shaped `@Observable` view
  models, and a table of patterns deliberately not adopted, pointing at `README.md`'s
  Design Philosophy and at an ADR for any app that adopts one.
- A `designing-errors` skill: error enums in `MyAppCore`, typed `throws(E)` only where
  a caller switches on the cases, no user data in error payloads or log lines,
  `CancellationError` propagated rather than swallowed, and how a `MyAppPlatform`
  adapter maps `OSStatus`, `NSError`, and `AXError` into Core errors.
- A "Removing the example code" checklist in `docs/getting-started.md` covering the
  counter and the `FrontmostApp` port/adapter (port, view model, adapter, fake,
  local-machine test, `AppLog.frontmostApp`, the `ContentView` row, the composition
  root, and the docs that cite it), linked from `README.md`, the `starting-an-app`
  skill, and `scripts/bootstrap.sh`'s next steps.

- `just test-scripts` (and so CI's `lint` job) now runs the Python `unittest` suite
  under `.agents/skills/shipping-issues/scripts/tests/`, through the new
  `scripts/tests/skill-scripts_test.sh`, with `PYTHONDONTWRITEBYTECODE=1`.
- `AGENTS.md`'s "Security and human approval" now lists the concrete Swift and CI
  forms of weakening a gate (`// swiftlint:disable`, `// swiftformat:disable`,
  `@unchecked Sendable` / `nonisolated(unsafe)`, `.disabled`/`withKnownIssue`,
  coverage excludes, loosened assertions, `continue-on-error`) and forbids re-spelling
  a denied command (`git -C .`, `bash -c`, bundled flags): stop and ask instead.
- An Architecture Decision Record tree for apps cut from the template:
  `docs/architecture/README.md` (the index, shipped empty, with the status legend and
  how an ADR changes) and `docs/architecture/adr/template.md`. `AGENTS.md`'s new
  "Before changing the architecture" section names the changes that owe an ADR — a new
  target or port, the app shape, the sandbox posture, persistence, a new dependency,
  distribution, `deploymentTarget`, a TCC permission — and a
  `recording-architecture-decisions` skill sets out when one is owed, its statuses
  (an Accepted ADR takes small, dated "Amended" corrections; a replaced decision gets
  a new ADR and the old one becomes Superseded), and its fact discipline: every
  external claim carries a URL and a checked date. The template's own reasoning stays
  in README's Design Philosophy.
- `.claude/agents/executor.md`, `architect.md`, and `worker.md`: named Claude Code
  sub-agent tiers (Opus low, Opus high, Sonnet medium) a skill can hand a step to,
  documented in `AGENTS.md` › Sub-agents with the Codex CLI fallback of running the
  step inline.
- `blocked: external`, `on hold`, and `tracking` labels in `.github/labels.yml`,
  defined in `triaging-issues`: an issue only a person can move forward, work parked
  on purpose, and a tracking issue whose sub-issues carry the work. `shipping-issues`
  skips the first two and now drops a `tracking` issue from ranking, selection, and
  priority backfill.
- `AGENTS.md` › Security and human approval records the standing exceptions:
  invoking `smart-commit` (when asked to push), `create-pr`, or `shipping-issues` is
  the sign-off for the remote writes that skill exists to make, and for nothing else
  that section lists.
- Renovate (`.github/renovate.json`) opens update PRs for `mise.toml`'s tool pins,
  which Dependabot cannot see, with the same 7-day wait after a release
  (`minimumReleaseAge`). It is limited to the `mise` manager; SwiftPM and Actions stay
  with Dependabot. The Renovate GitHub App must be installed on the repository.
- A Claude Code permission list in `.claude/settings.json`: the `just` recipes that
  read, build, or test, `swift build`/`swift test`, and read-only `gh` now run without
  a prompt, while everything that writes beyond the working tree — `just labels`,
  `just ruleset`, `just release-prep`, `just reset-permissions`, `git push`,
  `gh pr create`, `gh pr merge`, `gh issue create` — stays behind one, as does
  `just logs`, which streams until Ctrl-C. `deny` refuses `git commit --no-verify`/`-n`,
  a force push in each of its spellings, and an edit to `App/*.entitlements`. It binds
  Claude Code alone and is a prompt policy rather than a boundary
  (`AGENTS.md` › Enforcement layers). `scripts/checks/just-recipes-exist.sh`
  (`just check-harness`) now also reads that file, so a `Bash(just <recipe>…)` rule for
  a recipe the justfile does not define fails the harness instead of silently never
  matching
- An `integrating-system-apis` skill: how a macOS system API is reached from
  `MyAppPlatform` behind a Core port — choosing the mechanism and the permission it
  costs, a `@convention(c)` callback's `Unmanaged` refcon pairing, `MainActor.assumeIsolated`
  versus a `Task` hop, `@preconcurrency import`, teardown order, re-enabling an event
  tap the system disabled, and how a TCC grant behaves (no callback, lost on every
  ad-hoc rebuild). Every Swift snippet in its references was compiled under the
  template's `strictSettings` and checked with `swiftlint --strict`
- An optional local signing identity for Debug builds: `Config/Debug.xcconfig`
  (wired in by `project.yml`'s `configFiles`) ends with
  `#include? "Local.xcconfig"`, so a gitignored `Config/Local.xcconfig` can give
  Debug builds a stable designated requirement and keep a TCC permission grant
  alive across rebuilds. Without that file the build is signed ad hoc exactly as
  before, and Release reads no xcconfig at all
  (`docs/getting-started.md` › Keeping Permission Grants Across Rebuilds)
- `just reset-permissions` (`scripts/reset-permissions.sh`): resets every recorded
  permission decision for this app, and only this app — the bundle identifier comes
  from `project.yml`, never from an argument
- The commit-time guard refuses a staged `Local.xcconfig`
  (`scripts/guard/paths.sh`)
- `AGENTS.md` gains a `## Product` section — what the app is and who for, the core
  interaction, its **Non-goals**, and where those decisions are recorded — shipped here
  as a `TODO` skeleton and filled in right after the rename (`README.md` › Using This
  Template, step 3; the `starting-an-app` skill). `scripts/checks/product-section-filled.sh`
  (`just check-harness`) holds both directions off one signal: the skeleton stays while
  `project.yml` names the template's app-name placeholder, and no `TODO` may survive
  once the rename has removed it, so a new app cannot ship agent instructions with no
  product context. CI's `bootstrap-smoke` asserts the check fires on the renamed clone
- A `running-the-app` skill: how to see a change working in the real app — `just run`
  and confirming the running process is the build you just made, reading `just logs`
  (and why `log show --last` does not show a `.debug` line), screenshotting a window or
  the screen with `screencapture`, driving a flow with a throwaway XCUITest and
  exporting its screenshot from the result bundle, starting the app in a known state
  with launch arguments or environment variables, the human hand-off for a first TCC
  prompt or a System Settings step — asked for once, up front — and the evidence a pull
  request carries when no CI job can assert the behavior
- `just release-prep <version>` (`scripts/release-prep.sh`): the edits a release needs
  before its tag exists, in one checked step — `MARKETING_VERSION` set,
  `CURRENT_PROJECT_VERSION` incremented, and `CHANGELOG.md`'s `[Unreleased]` entries
  rolled into `## [<version>] - <date>`, leaving a fresh empty `[Unreleased]`. It
  refuses a version that is not above the current one (compared component by component,
  so 1.10.0 follows 1.9.0), a dirty work tree, and an empty `[Unreleased]`; `--dry-run`
  runs every check and writes nothing. It creates no commit, tag, or push and prints
  the commands that do, ending with the tag `.github/workflows/release.yml` checks
  against `MARKETING_VERSION` (`docs/distribution.md` › Preparing the version bump)

- `.template-origin`: `scripts/bootstrap.sh` records the template commit and repository
  an app was created from, so listing the template changes the app does not have yet is
  one command — `git log --oneline "$(sed -n 1p .template-origin)"..template/main`
  (`README.md` › Keeping up with template updates)

- `MyAppPlatformTests`, an opt-in test target for the adapter tests CI cannot run: every
  suite carries the `.requiresLocalMachine` trait, so they are reported as *skipped*
  under `just test` and in CI and run only with `RUN_LOCAL_MACHINE_TESTS=1`, which the
  new `just test-local` recipe sets. `WorkspaceFrontmostAppProvider` against the real
  `NSWorkspace` is the worked example; `.claude/rules/testing.md` › Where a Test Goes
  states the split between a Core test with a fake and a local-machine test
- A logging convention: `os.Logger` through `MyAppCore`'s new `AppLog`, whose
  `subsystem` is the app's bundle identifier (the one `just logs` streams) and whose
  categories name one concern each. `MyAppCore` may `import os` — it is neither a UI nor
  an OS-integration framework, so it stays off both halves of the Core ban list
  (`docs/architecture.md` › Logging). `FrontmostAppViewModel.refresh()` is the worked
  example, logging another application's name `.private`
- `.swiftlint.yml`'s `no_print_in_sources` custom rule rejects `print(`, `debugPrint(`,
  and `NSLog(` under `Packages/*/Sources/` and `App/` (the pre-commit hook, `just lint`,
  and CI's `lint` job); comments, string literals, and test targets are exempt
- `MyAppPlatform` target: the home for OS-integration code, behind `Sendable` ports
  declared in `MyAppCore`. Ships a worked example — the `FrontmostAppProviding` port,
  its `NSWorkspace`-backed `WorkspaceFrontmostAppProvider` adapter, and the fake the
  Core tests use — and the app now shows the frontmost application's name
  (`docs/architecture.md` › Ports and adapters)
- Architecture boundary tests that `MyAppUI` and `MyAppPlatform` never import each other
- Initial template: XcodeGen-generated app shell over a local Swift package
  with a Core/UI split and a working counter placeholder
- Swift Testing suite with an enforced 80% line-coverage floor on `MyAppCore`
  (`scripts/coverage.sh`)
- XCUITest launch test and a Release-build smoke script (`scripts/smoke_launch.sh`)
- `scripts/bootstrap.sh` deterministic template initializer: renames `MyApp`
  and replaces every placeholder (`my-app`, `com.example`, `your-username`,
  `Your Name`, `you@example.com`) across tracked files
- Strict tooling from day one: Swift 6 language mode, warnings-as-errors,
  SwiftLint strict with all opt-in rules, SwiftFormat, pinned via mise
- Hardened CI: SHA-pinned actions, least-privilege permissions, zizmor,
  typos, OpenSSF Scorecard, Dependabot with cooldown, OSV scan,
  dependency review, and a template bootstrap smoke job
- Secret-gated release pipeline: DMG packaging, Developer ID signing,
  notarization, and build-provenance attestation
- `AGENTS.md` and path-scoped `.claude/rules/` for AI-assisted development
- ShellCheck joins the lint gate (`just lint` and CI) for every repo shell script
- The launch UI test writes an `.xcresult` bundle; CI uploads it when the job fails
- The release pipeline smoke-tests the signed Release app before packaging the DMG
- A repository-script contract in `AGENTS.md` (`## Repository scripts`) and a
  plain-bash test runner for `scripts/` (`scripts/tests/run.sh`, `just test-scripts`),
  run by `just check` and CI's lint job; `scripts/lint.sh` errors now carry
  `Expected:`/`Actual:`/`Next:` lines
- `AGENTS.md` gains a narrowest-check table, a skill and rule index, the actions
  that need human approval, and the enforcement layers with their known gaps
- Release runs are serialized per tag via a workflow `concurrency` group
- `.xcode-version` is the single source of truth for the CI Xcode pin;
  `just install` warns when the local Xcode differs
- CodeQL static analysis of the Swift package (weekly and on `main` pushes)
- Skills are authored once under `.agents/skills/` (read by Codex CLI) and mirrored
  byte for byte into `.claude/skills/` by `scripts/sync-agents.sh`
  (`just agents-sync`; `just agents-check` reports drift); `.gitattributes` marks the
  mirror as generated
- `ContentView` accepts an injected view model and ships `#Preview` configurations
- `just lint`, the pre-commit hook (a new "Skills mirror" section, scoped to commits
  that stage a path under `.agents/skills/` or `.claude/skills/`), and CI's lint job
  now all fail when the two skill trees drift, via `scripts/sync-agents.sh --check`
- `.github/labels.yml` declares this repository's GitHub label taxonomy as code;
  `scripts/sync-labels.sh` (`just labels`) creates or updates each label from it,
  never deleting one it does not mention, and a `.github/ISSUE_TEMPLATE/task.yml`
  form files repository chores with `chore` and an unset priority
- Two skills under `.agents/skills/`, translated to this stack: `changing-gates`
  (editing a lint, format, compiler, hook, coverage, or CI gate, and which gate sees a
  change) and `triaging-issues` (the label taxonomy in `.github/labels.yml`, priority
  tiers, and the `Depends on #N` convention)
- Two more skills under `.agents/skills/`, translated to this stack: `authoring-skills`
  (authoring a skill once under `.agents/skills/`, the `just agents-sync` mirror, and
  what no check verifies yet) and `updating-docs` (which documentation surface a change
  lands on, including `CHANGELOG.md` and `docs/`)
- `scripts/verify-hooks.sh` (`just verify-hooks`) checks that git really resolves the
  hooks directory to `.githooks/` and that `.githooks/pre-commit` is executable, run at
  the end of `just install` and as the first step of `just check`; it skips under CI or
  the named `ALLOW_MISSING_GIT_HOOKS=1` opt-out, for an environment that genuinely
  cannot have git hooks
- The pre-commit hook gains a "Staged guard" section, run on every commit that stages a
  change: `scripts/check-staged.sh` refuses a secret-shaped staged path
  (`scripts/guard/paths.sh`: `.env*` except samples, `secrets/`, `.p12`/`.pfx`/`.p8`,
  provisioning profiles, keychains, and named credential files) and credential-shaped
  staged content (`scripts/guard/credentials.sh`: a private-key header, GitHub tokens,
  AWS access key ids), never printing the matched text and never inspecting a staged
  deletion; `smart-commit` and `changing-gates` point at `scripts/guard/` instead of
  keeping their own list
- Harness-conformance checks under `scripts/checks/` (`just check-harness`, run by
  `just check` before `just test` and by CI's `lint` job): every `just <recipe>` in
  `AGENTS.md` exists, every workflow has a top-level `permissions:` and every non-local
  `uses:` in a workflow or composite action is pinned to a full SHA with a `# v…`
  comment, every `SKILL.md` frontmatter is exactly a matching `name` and a
  `description`, and `AGENTS.md`'s Skills table matches `.agents/skills/`; each failure
  mode is pinned by `scripts/tests/checks_test.sh`
- `.github/rulesets/main.json` defines the intended `main` branch ruleset (PR
  required, checks green, no force-push or deletion) as code; `scripts/apply-ruleset.sh`
  (`just ruleset`) creates or updates it via `gh` for a repository admin, mapping a
  plan-gated API refusal and any other refusal to distinct named errors
- `MyAppCore` is mechanically kept free of UI frameworks, twice: a SwiftLint custom rule
  (`no_ui_import_in_core` in `.swiftlint.yml`) and a Swift Testing suite
  (`ArchitectureBoundaryTests`) both reject `SwiftUI`, `AppKit`, `UIKit`, and `Cocoa`
  imports in `Sources/MyAppCore`, including attributed and kind-qualified spellings
- Two skills: `writing-repo-scripts` (why the repository scripts are bash, refusing or
  skipping outside a git checkout, the stderr contract by worked example, and testing
  with `scripts/tests/lib.sh`, pointing at `AGENTS.md`'s "Repository scripts" for the
  rules) and `starting-an-app` (what `scripts/bootstrap.sh` renames and how, and what a
  new app keeps, including its labels and branch ruleset)
- `just fix` formats and auto-fixes SwiftLint violations, then runs `just lint`;
  `just test-fast <filter>` runs only the matching tests, without the coverage floor
- `starting-an-app` gains an app-shapes reference
  (`.agents/skills/starting-an-app/references/app-shapes.md`, linked from
  `docs/architecture.md`): the `project.yml` key, `App/` entry point, and `LaunchTests`
  assertion a menu-bar agent (`LSUIElement`, `MenuBarExtra`) needs instead of the
  shipped windowed shape, proven against `just build`, `just uitest`, and `just smoke`,
  plus where an `NSStatusItem` delegate lives and what XCUITest can see of a status item
- `docs/distribution.md` gains a "Sandboxed or not" section: the capabilities that
  force the App Sandbox off (Accessibility API, `CGEvent` posting, global event taps,
  file access outside the container), what stays on regardless (Hardened Runtime,
  Developer ID signing, notarization), what it costs (no Mac App Store), and the
  `INFOPLIST_KEY_NS…UsageDescription` build settings a TCC-gated API needs. The
  `starting-an-app` skill makes deciding the posture an explicit, human-signed-off
  step; the shipped `App/MyApp.entitlements` stays sandboxed
- `just logs` streams this app's unified-log output — the records whose subsystem is
  the bundle identifier `project.yml` declares, read by the new
  `scripts/bundle-id.sh`, so both recipes that need it survive
  `scripts/bootstrap.sh`
- `docs/architecture.md` › "Recommended optional dependencies" gains the four needs a
  utility app hits first — global hotkeys, launch at login, a human-editable config
  file, and a settings window — each with its zero-dependency answer first and each
  candidate checked against `.claude/rules/project.md`'s checklist on a recorded date
  (`KeyboardShortcuts` and `TOMLDecoder` pass; `LaunchAtLogin`, `TOMLKit`, and
  `Settings` are recorded with the reason they do not). No dependency is added

### Changed

- The workflows now pass `scripts/checks/workflow-hygiene.sh` without widening any
  token: `pr-label.yml`'s `pull-requests: write` moves from the workflow to its one job
  (top level `{}`), `scorecard.yml`'s top-level `read-all` narrows to `contents: read`
  (its job keeps its own block), `check-pr-title.yml`, `dependency-review.yml`,
  `osv-scan.yml`, and `pr-label.yml` cancel a superseded pull request run through a
  per-ref `concurrency:` group, and `ci.yml`, `codeql.yml`, `gitleaks.yml`,
  `osv-scan.yml`, `pr-label.yml`, and `release.yml` default their `run:` steps to
  `shell: bash`, so a failing command before a `|` now fails its step. `release.yml`
  keeps its own error messages under that default: its notary-log parsing reads
  here-strings instead of `printf | grep -q`/`| awk '…exit'` pipes that could stop
  on SIGPIPE, and its MARKETING_VERSION and signing-identity lookups end in
  `|| true` so their empty-value checks still report (#129).
- `FakeFrontmostAppProvider` moved from `FrontmostAppViewModelTests.swift` to
  `Tests/MyAppTestSupport/FakeFrontmostAppProvider.swift` as a `package` type, and is now
  `Sendable` through an `OSAllocatedUnfairLock` around its call count instead of
  `@unchecked Sendable`. `FrontmostAppProviding`'s doc comment now states the clause
  the contract checks, and `WorkspaceFrontmostAppProvider` answers `nil` for an
  application whose `localizedName` is empty, as it already did for a missing one.
- `scripts/lint.sh`'s `shellcheck` and `typos` (`typos.toml`) no longer scan the
  generated `.claude/skills/` mirror, which doubled every finding in `.agents/skills/`;
  the mirror stays held byte-identical by `scripts/sync-agents.sh --check`
- The `integrating-system-apis` skill follows the platform-skill convention: its
  `SKILL.md` and both references link each Apple API they rely on (developer.apple.com,
  checked 2026-09-28) instead of restating its behavior, and word the rest as what this
  repository decided and why.
- The `changing-gates` and `smart-commit` skills are back under the 200-line `SKILL.md`
  body cap: the `.swiftlint.yml` custom-rule detail, the `scripts/guard/` pattern list,
  and the workflow conventions move to `changing-gates/references/`, and the pre-commit
  hook recovery steps to `smart-commit/references/`, each linked from the body with no
  rule dropped (#166).
- `scripts/bootstrap.sh`'s "Next steps" and `README.md`'s "Using This Template" now
  point a new app at the `docs/architecture/roadmap.md` skeleton right after its
  `## Product` section.

- `.github/dependabot.yml` groups minor and patch updates per ecosystem (SwiftPM and
  GitHub Actions), so one upstream release arrives as one PR; majors still get their
  own PR, and the 7-day cooldown is unchanged.
- `shipping-issues` is adapted to this template: its `SKILL.md` fits the
  `authoring-skills` 200-line budget (step detail moved to
  `references/implement-and-review.md` and `references/pr-ci-merge.md`), and the
  whole skill tree is English-only ASCII. Every spawn names a `.claude/agents/` tier
  (`executor`, `architect`, `worker`) instead of a bare model, a resume goes to the
  still-running agent via `SendMessage`, and Codex CLI runs each step inline. It
  reviews every branch at `/code-review medium`, watches CI in the background (or in
  the foreground under the Bash tool's 600-second cap), clears `blocked: dependency`
  right after each merge as `triaging-issues` requires, and sends back a user-facing
  change that lacks a `CHANGELOG.md` entry. `worktree_setup.sh` copies
  `Config/Local.xcconfig` into each worktree, and `preflight.sh` prefers a justfile
  recipe (`just check`) over any `package.json` or Makefile target
- `just run` relaunches the build it just made instead of activating an old process:
  `scripts/run-app.sh` quits every running instance of this app — matched by bundle
  identifier, never by process name — and waits for it to exit, bounded, reporting a
  process that outlives the wait rather than forcing it
- `MyAppCore`'s import ban list now also rejects `ApplicationServices`, `Carbon`, and
  `ServiceManagement`, in both `.swiftlint.yml`'s `no_ui_import_in_core` and
  `ArchitectureBoundaryTests`: an adapter that needs one belongs in `MyAppPlatform`
- `scripts/bootstrap.sh` now removes the template-only `bootstrap-smoke` CI job and
  its required status check, so a new app's CI and branch ruleset no longer require a
  job that cannot pass
- `just build` and `just uitest` isolate DerivedData under `build/`, so
  `just clean` now removes everything the toolchain produced
- `scripts/bootstrap.sh` resets `CHANGELOG.md` for the new project and prints a
  verify-first next-steps list
- `scripts/bootstrap.sh`'s next steps and `README.md`'s "Using This Template" add
  `just labels` for the new repository, and `just ruleset` as an optional, admin-only
  last step once the bootstrap commit is on `main`
- `just lint`, the pre-commit hook, and CI's lint job all call one script,
  `scripts/lint.sh`; `typos` is pinned in `mise.toml` and runs in `just lint`
  (CI's separate spell-check job is folded into the lint job)
- The pre-commit hook runs each check as its own section scoped by staged paths,
  with no early exit when no Swift file is staged
- `typos` also spell-checks the dot-directories (`.agents/`, `.claude/`, `.github/`,
  `.githooks/`), which it skipped by default; `.git/` is excluded
- `just test-scripts` runs `scripts/tests/run.sh` through `mise exec --`, since the
  harness-check tests call the pinned `just`; CI's lint job installs `just` too
- The coverage floor is `readonly COVERAGE_FLOOR=80` in `scripts/coverage.sh` and moves
  only by a reviewed diff: the `COVERAGE_MIN` environment override is removed, and
  setting it now fails with `ERR_COVERAGE_OVERRIDE_REMOVED` before any test runs
  (`scripts/tests/coverage_test.sh`)
- Dependency review fails a pull request that adds a dependency outside the permissive
  license allow-list in `.claude/rules/project.md` (MIT, Apache-2.0, BSD-2-Clause,
  BSD-3-Clause, ISC, 0BSD, Zlib), via the action's `allow-licenses`
- `.claude/rules/project.md` holds the review record a new SwiftPM dependency needs
  (need, continuity, license, weight, build-time code, platforms, advisories) and how to
  declare, add, and bump one without hand-editing `Package.resolved`; it now also loads
  when `Package.resolved` is touched
- `scripts/tests/run.sh` runs the script test files concurrently instead of one after
  another — each file's output is still captured and printed whole in glob order, every
  file still runs after a failure, and `ERR_TESTS_NONE`/`ERR_TESTS_FAILED` are unchanged
  — cutting `just test-scripts` from roughly 34 s to 12 s. It also parses each file
  with `bash -n` before starting it, so a file that bash 3.2 aborts on a syntax error
  while still exiting 0 is counted as failing instead of passing, and on INT or TERM it
  kills the files it started (a background job in a non-interactive shell ignores
  SIGINT) and prints every log it had not reported yet, marked `(interrupted)`, with a
  new `ERR_TESTS_INTERRUPTED`; `scripts/tests/run_test.sh` now covers the runner itself

### Removed

- The committed `.claude/settings.json` no longer registers the owner's personal
  plugin marketplace or enables a plugin from it for everyone who opens the
  repository; it keeps only `permissions` and `hooks`, and `AGENTS.md`'s Enforcement
  layers row now describes both.

### Fixed

- `scripts/bootstrap.sh` now removes `SECURITY.md`'s template-only passages (marked
  `bootstrap:template-only-begin`/`-end`), so an app repository no longer tells its
  reader what "a repository created from this template" should do; CI's
  `bootstrap-smoke` job asserts it.

- `scripts/bootstrap.sh` now runs `swiftformat` on the renamed tree, so a longer app
  name no longer leaves lines past the max width or imports out of order for the
  pre-commit hook to refuse the bootstrap commit. CI's `bootstrap-smoke` job now
  bootstraps as `ClaudeUsageBar` and runs `scripts/lint.sh` on the result.

- `.swiftformat` sets `--decimalgrouping 3,4`, so SwiftFormat groups integer literals
  from 4 digits (`3_600`, `36_000`) as SwiftLint's `number_separator` requires; before,
  no 4- or 5-digit literal passed `just lint`. A case in `scripts/tests/lint_test.sh`
  fails if the two tools disagree again (#205).

- `pr-label.yml`'s job now has `contents: read`, so its base-SHA checkout works in a
  private repository cut from the template, not only a public one (#196).

- The release workflow no longer strips `App/MyApp.entitlements` (and with it the App
  Sandbox) from an ad-hoc-signed release: it keeps the signature `xcodebuild` applied
  instead of re-signing without `--entitlements`, and a new step fails the release
  unless `codesign -d --entitlements -` shows `com.apple.security.app-sandbox`.
  `docs/distribution.md` now describes both signing paths.
- `scripts/verify-hooks.sh` now skips only when git reports "not a git repository"
  (matched under `LC_ALL=C`); any other git failure, such as a malformed config,
  fails with `ERR_HOOKS_GIT_FAILED` instead of passing silently.
- `scripts/tests/lib.sh` now unsets every exported `GIT_*` variable, not a fixed five,
  so `GIT_CONFIG_*`, `GIT_CEILING_DIRECTORIES` and the like no longer leak into fixture
  repositories; the new `scripts/tests/lib_test.sh` asserts none remain.
- Stale claims about what the harness checks: `updating-docs` now names
  `skills-index-complete.sh` and `just-recipes-exist.sh`, `authoring-skills` no longer
  quotes outdated description and body sizes, `AGENTS.md` drops pointers to tracking
  issues that do not exist and adds `just check-harness` to the `main.json` row, and
  the `check-harness` comments in `justfile` and `ci.yml` point at `scripts/checks/`
  instead of an enumeration that went stale.

- Small factual drift in the docs: removed leftover references to a Python/uv sibling
  project (`README.md`, `.swiftlint.yml`, `mise.toml`, `.claude/rules/project.md`);
  `docs/adding-ios.md` now names `os` among `MyAppCore`'s imports; `docs/distribution.md`
  no longer claims `project.yml` already sets usage-description keys; the `create-pr` and
  `smart-commit` type lists now match `check-pr-title.yml`; `running-the-app` no longer
  assumes the repository is public; `.claude/rules/testing.md` no longer claims the
  line-coverage floor notices a missed branch; `.claude/rules/swift.md` states the
  SwiftLint limits actually enforced; `.github/zizmor.yml` no longer hard-codes a use
  count; `SECURITY.md` drops response times a template cannot promise
- `ContentView`'s `−` and `+` buttons now carry the accessibility labels "Decrement"
  and "Increment", so VoiceOver no longer reads the bare glyph.

- `.claude/settings.json`'s `PostToolUse` hook now formats only the `.swift` file an
  `Edit`/`Write`/`MultiEdit` touched, through `scripts/format-edited-file.sh`, instead of
  running `swiftformat .` over the whole tree after every edit; non-Swift paths and files
  outside the checkout are skipped, and a swiftformat failure is reported to the agent
  rather than silenced.
- `just check` step lists in `README.md`, `docs/getting-started.md`, `CONTRIBUTING.md`,
  `AGENTS.md`, and the `create-pr` and `tdd` skills now match the justfile's `check`
  recipe, and every recipe shows a one-line summary in `just --list` (`[doc(...)]`).

- `scripts/bootstrap.sh` no longer rewrites the passages that explain its placeholders
  (its own header, `README.md`'s "Using This Template" paragraph, and the
  `starting-an-app` skill), which read as nonsense after the rename: lines between a keep-begin
  and a keep-end marker comment are skipped. CI's
  `bootstrap-smoke` asserts the kept passages survive and ignores them in its leftover
  check. The script's next steps now match `README.md`'s list.

- CI runs of pushes to `main` no longer cancel each other: `.github/workflows/ci.yml`
  groups push runs by commit SHA and cancels in progress only for a superseded pull
  request run, so two quick merges each finish their run.
- `shipping-issues`' `ci_watch.sh` now enforces `--timeout` on stock macOS, which has
  neither `timeout` nor `gtimeout`; the watch used to run unbounded there.
- `shipping-issues`' Python scripts no longer write `__pycache__/` into the
  `.claude/skills` mirror, which made `just agents-check` fail after a run.
- `shipping-issues`' digest reads every issue number on a `Depends on #1, #2 and #3`
  line, not only the first.
- `scripts/tests/apply-ruleset_test.sh` built its `gh` stub bodies with a heredoc inside
  a command substitution, which bash 3.2 parses wrongly at the first `)` of a `case` pattern:
  under macOS `/bin/bash` the file died with a syntax error and still exited 0, so none
  of its six cases ran and nothing reported it. The bodies are single-quoted literals now

[Unreleased]: https://github.com/your-username/my-app/commits/main
