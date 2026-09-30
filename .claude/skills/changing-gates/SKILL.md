---
name: changing-gates
description: >
  Covers editing a file that enforces rather than implements: .swiftlint.yml,
  .swiftformat, Package.swift's strictSettings, mise.toml, .githooks/pre-commit,
  scripts/lint.sh, scripts/coverage.sh, the scripts/guard/ commit-time guard, or a
  .github/workflows/*.yml workflow. Use when a
  SwiftLint rule is added, disabled, or loosened, a SwiftFormat option changes, a target
  is added to Package.swift, a tool pin is added or bumped, a pre-commit section or a CI
  job or step is proposed, the coverage floor is touched, or the question is which gate
  would have caught a change - including what none of them sees.
---

# Changing Gates

**Owns:** a change to a file that enforces rather than implements — `.swiftlint.yml`,
`.swiftformat`, `Packages/TownsfolkKit/Package.swift`'s `strictSettings`, `mise.toml`,
`.githooks/pre-commit`, `scripts/lint.sh`, `scripts/coverage.sh`, the commit-time guard
under `scripts/guard/`, and `.github/workflows/*.yml` — and which gate can see a given change at all. **Does not
own:** adding a package dependency (the Dependency Policy in `.claude/rules/project.md`);
the content of a repository-specific lint rule; how a
script under `scripts/` is written (`AGENTS.md`'s "Repository scripts"); the label set
in `.github/labels.yml` (`triaging-issues`).

Never weaken a gate to make a check pass: that rule is stated in `AGENTS.md`'s
"Security and human approval" and "Important Reminders" sections, and this skill does
not restate or relax it. A change that lowers, disables, or widens a gate needs a
human's sign-off, and its PR says why the removed protection no longer applies.

## The one rule every gate change shares

A gate file may narrow _what_ a shared script looks at; it never defines a rule of its
own. `scripts/lint.sh` is the single lint script: `just lint`
(`mise exec -- scripts/lint.sh`), the pre-commit hook (`--staged-tree`), and CI's `lint`
job all call it. A new check is therefore added to `scripts/lint.sh`, never inlined as a
command into `justfile`, `.githooks/pre-commit`, or a workflow `run:` step. The same
shape holds elsewhere: CI's `test` job calls `scripts/coverage.sh` (what `just test`
runs), and the `app` job calls `just build`, `just uitest`, and `just smoke`.

A check in `scripts/lint.sh` is three edits, not one:

- the `run …` line, so the check runs and a failure is collected without stopping the
  checks after it;
- the tool in `REQUIRED_TOOLS` for its mode, so a missing tool fails as
  `ERR_LINT_TOOL_MISSING` instead of as a confusing linter error;
- the tool in `mise.toml` and in the `install_args` of ci.yml's `lint` job. That job
  runs on `ubuntu-latest` and installs only the Linux-capable subset, so a macOS-only
  tool cannot join `scripts/lint.sh` at all — it belongs in a macOS job.

`scripts/tests/run.sh` (`just test-scripts`, part of `just check` and CI's `lint` job)
is a gate on the gates: `scripts/tests/lint_test.sh` pins `scripts/lint.sh`'s argument
and tool checks, `scripts/tests/pre-commit-skills_test.sh` pins the hook's "Skills
mirror" section, and `scripts/tests/check-staged_test.sh` pins its "Staged guard"
section. A change to either file keeps its test green, and a new script under
`scripts/` gets a test as `AGENTS.md`'s "Repository scripts" requires.

## `.swiftlint.yml`

`strict: true` makes every warning an error, and `opt_in_rules: [all]` enables every
opt-in rule, so a new SwiftLint release can add rules that fire on a pin bump. Every
entry in `disabled_rules` carries a one-line trailing reason; a new entry without one
is incomplete, and removing a rule needs explicit approval
(`.claude/rules/project.md`). Prefer an inline `// swiftlint:disable:next <rule>` with
a reason when only one site needs the exception — a global disable widens the gate for
every future file. Repository-specific rules live under `custom_rules:`; there are two.

`no_ui_import_in_core` keeps `TownsfolkCore` from importing a UI or OS-integration
framework, and its module list changes together with `ArchitectureBoundaryTests`'
`forbiddenModules` in one commit; `no_print_in_sources` rejects `print(`,
`debugPrint(`, and `NSLog(` in shipped sources. Before editing either
rule, read [references/swiftlint-custom-rules.md](references/swiftlint-custom-rules.md):
the full module list and why `os`/`OSLog` stay off it, the sibling boundary held by
the test alone, and the four load-bearing parts of `no_print_in_sources` a widening
edit usually breaks.

`analyzer_rules` is deliberately absent: those run only under
`swiftlint analyze` with a compiler log, which no gate here invokes. `trailing_comma`
is set to agree with SwiftFormat; the two tools must never disagree about one file.

## `.swiftformat`

`just fmt` applies it (`swiftformat .`); `scripts/lint.sh` only checks
(`swiftformat --lint`), so a formatting change surfaces in `just lint`, the hook, and
CI, never as a silent rewrite. Changing an option reformats the whole tree: land the
option and the resulting reformat in the same commit, and check that the output still
passes `swiftlint --strict`. `--decimalgrouping 3,4` groups integers from 4 digits
(`3_600`) because SwiftLint's `number_separator` demands that; SwiftFormat's default
`3,6` left no 4- or 5-digit spelling passing both, and `scripts/tests/lint_test.sh`
fails if they drift apart again. `--swiftversion` follows the package's tools version.

## `Package.swift`'s `strictSettings`

`strictSettings` holds `.swiftLanguageMode(.v6)` and `.treatAllWarnings(as: .error)`.
It is not inherited: each target passes `swiftSettings: strictSettings` itself, so a new
target — source or test — must opt in explicitly, or it compiles without Swift 6
data-race errors and with warnings allowed. Removing an entry, or adding an
`unsafeFlags` or a per-target exception, is weakening a gate.

## `mise.toml`

It pins every CLI tool the gates call; scripts call those tools by bare name and the
caller provides PATH. Pins are not bumped by hand: Renovate opens the bump PRs after
a 7-day cooldown, and `.claude/rules/project.md`'s Toolchain Pinning is the one
statement of that policy, including why `.xcode-version` is the exception that is
hand-bumped. A SwiftLint or SwiftFormat bump PR is a gate change in its own right: new
rules or formatting may fire, and the fix is to the code or a reasoned `disabled_rules`
entry on that PR, never to skip the bump silently. The Xcode pin lives in
`.xcode-version`, not here.

## `scripts/coverage.sh`

It gates on line and function coverage of `Sources/TownsfolkCore/` only, by filtering
llvm-cov's report to that path. `TownsfolkUI` and `TownsfolkPlatform` are outside it because an adapter or a view
holds translation rather than a decision (`docs/architecture.md` › Ports and adapters) —
not because nothing links them: `TownsfolkPlatformTests` links `TownsfolkPlatform`, and its
tests are skipped unless `RUN_LOCAL_MACHINE_TESTS=1` (`just test-local`), so they add no
coverage under `just test` either way. Measuring Platform would therefore gate on
whether a human opted in, which is why the filter is a path and not a target list. The
floors are `readonly COVERAGE_FLOOR=80` (lines) and `FUNCTION_COVERAGE_FLOOR=75` in the
script and nothing else — no environment variable or flag moves either, so every change
is a reviewed diff of this file, and only ever a raise. The function floor sits lower
because llvm-cov counts compiler-generated closures (an `os.Logger` interpolation) as
functions no test evaluates; the script's header records the value it was set against. The script rejects the environment override it used to read with
`ERR_COVERAGE_OVERRIDE_REMOVED` before any test runs, rather than silently ignoring it;
`scripts/tests/coverage_test.sh` holds that. Adding a new way to set the floor from a
recipe, workflow, or hook is lowering it by another route.

## `.githooks/pre-commit`

Independent sections, each scoped by the staged paths it cares about, none exiting
early — a commit that skips one section must still reach every other. Each section
calls a shared script: "Swift lint" exports the staged Swift blobs and runs
`scripts/lint.sh --staged-tree`; "Skills mirror" exports both skill trees from the
index and runs `scripts/sync-agents.sh --check --root`; "Staged guard" runs
`scripts/check-staged.sh` on every commit that stages any change (see
`scripts/guard/` below). All three check the staged content, not the worktree. A new section is appended below the layout-rule comment, and one that
needs a scratch directory takes it from `new_temp_dir`, which registers it in
`CLEANUP_DIRS` for the one shared `EXIT` trap — a second `trap … EXIT` would replace the
first and leak its directory. The hook only reaches clones that ran `just install`
(`core.hooksPath`); `scripts/verify-hooks.sh` (`just install`'s last step, and `just
check`'s first) fails loudly when that config did not stick or `.githooks/pre-commit`
lost its executable bit, narrowing — not closing — that gap: a contributor who runs
neither still commits without the hook, so CI stays the backstop. It skips under CI or
the named `ALLOW_MISSING_GIT_HOOKS` opt-out, for an environment that genuinely cannot
have git hooks.

The hook stays lint-only by decision (#140): it never formats and re-stages, compiles,
or runs related tests. A SwiftPM build takes tens of seconds and builds the worktree
rather than the staged blobs, so it would check something other than the commit; and a
slow or noisy hook teaches `--no-verify`, which also skips the staged secret guard. CI
runs the build and tests. Do not reopen this without a new reason those costs miss.

## `scripts/guard/`

`scripts/check-staged.sh` (the hook's "Staged guard" section) classifies each staged
path with `scripts/guard/paths.sh` first, and only scans the staged blob of a path that
passes with `scripts/guard/credentials.sh`. Staged deletions are never inspected: they
cannot add a secret, and blocking one would block the commit that removes a secret.
Those two files are the list — read them for exactly what is checked:

Before adding, removing, or loosening a path or content rule, read
[references/guard-patterns.md](references/guard-patterns.md): what is blocked by path,
what by content (the category is printed, never the matched text), and what is
deliberately not blocked — including why whether a commit *should* contain what it
contains stays in PR review.

A new pattern starts from a real false negative and lands with a fixture case in
`scripts/tests/guard-paths_test.sh` or `scripts/tests/guard-credentials_test.sh`.
Fixtures are assembled at runtime from pieces that do not match on their own, so no
committed file — the tests included — is secret-shaped; GitHub push protection is the
server-side layer and would refuse such a file too. Removing a pattern or a path rule is
weakening a gate. `git commit --no-verify` skips this guard with every other hook
section, and no CI job reruns it: that gap is listed in `AGENTS.md`'s "Enforcement
layers".

## `.github/workflows/`

`ci.yml` splits into `lint` (ubuntu: `scripts/lint.sh`, then `scripts/tests/run.sh`),
`test` (macOS: `scripts/coverage.sh`), `app` (macOS: `just build`, `just uitest`,
`just smoke`), `bootstrap-smoke` (macOS: `scripts/bootstrap.sh` on a clone, then a test
and build of the renamed app), and `zizmor` (workflow security lint). Which layer holds
what is `AGENTS.md`'s "Enforcement layers" table; read it rather than re-deriving it.

Every workflow follows a set of conventions — remote `uses:` pinned to a full SHA,
a narrow top-level `permissions:`, `persist-credentials: false`, and job names kept in
step with `.github/rulesets/main.json`. Widening `permissions:` or adding a workflow
that writes needs sign-off. Before editing a workflow, read
[references/workflow-conventions.md](references/workflow-conventions.md) for the full
list and which of it `actionlint`, `zizmor`, and `just check-harness` check.

## What no gate here sees

Nothing boots the app and asserts behavior beyond two checks: `scripts/smoke_launch.sh`
(`just smoke`) builds Release, verifies the code signature, launches the binary, and
asserts only that the process stays alive; `LaunchUITests/LaunchTests.swift`
(`just uitest`) asserts that a window appears and one increment click updates the
counter. Any other UI behavior, `TownsfolkUI` and `TownsfolkPlatform` code paths (both outside
the coverage floor — an adapter's real OS call is exercised by no *gate*: it has a test,
in `Tests/TownsfolkPlatformTests`, that only a human runs with `just test-local`, because a
runner has no GUI session and no TCC grants), the signed and notarized release (built only on a tag push by `release.yml`), and
entitlements or signing settings are places a change can be wrong while every gate
passes. Debug signing is now one of those settings: `Config/Debug.xcconfig` may
`#include?` an uncommitted `Config/Local.xcconfig`, so what a developer's Debug build
is signed with is by design invisible to every gate — which is why Release reads no
xcconfig, and why `just smoke` stays the check that Release signing is intact. A gate proposed to close such a gap is a real gate change and belongs in the PR
as one.
