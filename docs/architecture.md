# Architecture

This page describes the layers every app cut from this template starts with. What an
app decides on top of them — its shape, sandbox posture, persistence, dependencies,
distribution, macOS floor, and permissions — is recorded as ADRs under
[`docs/architecture/`](architecture/README.md), whose `README.md` is the index. How
Townsfolk sits on these layers is [Townsfolk on these layers](#townsfolk-on-these-layers).

## Layers

```
┌───────────────────────────────────────────────────┐
│ App/                                  (app shell) │  @main, WindowGroup — wiring
│                                                   │  only; composition root
├─────────────────────────┬─────────────────────────┤
│ TownsfolkUI     (SwiftUI)   │ TownsfolkPlatform     (OS)  │  siblings — neither one
│ thin views, no business │ adapters behind Core    │  imports the other
│ logic                   │ ports; AppKit and co.   │
├─────────────────────────┴─────────────────────────┤
│ TownsfolkCore                                 (logic) │  models, view models, ports;
│                                                   │  no UI/OS-framework import —
│                                                   │  enforced by lint and test;
│                                                   │  80% line-coverage floor,
│                                                   │  75% function-coverage floor
└───────────────────────────────────────────────────┘
```

The dependency direction is strictly one-way: `TownsfolkCore` ← `TownsfolkUI` and
`TownsfolkCore` ← `TownsfolkPlatform`, and both ← `App`.

Beside those layers sits one target that ships nothing: `TownsfolkTestSupport`
(`Packages/TownsfolkKit/Tests/TownsfolkTestSupport`), the test code both test targets share —
each port's fake and its contract function (see Ports and adapters below). It depends on
`TownsfolkCore` alone and is a library target only because SwiftPM lets no target depend on
a test target. No product exports it, so `App/` cannot link it; `ArchitectureBoundaryTests`
fails if `TownsfolkCore`, `TownsfolkUI`, or `TownsfolkPlatform` imports it; and its sources sit
under `Tests/`, outside `scripts/coverage.sh`'s `Sources/TownsfolkCore` filter, so it never
counts toward the coverage floors.

`TownsfolkCore` must stay free of UI frameworks so it also serves an iOS target
(`docs/adding-ios.md`). SwiftPM's target graph cannot stop `import SwiftUI` — a system
framework is not a package dependency — so the boundary is enforced twice, by text
match: `.swiftlint.yml`'s `no_ui_import_in_core` custom rule (the pre-commit hook,
`just lint`, CI's `lint` job) and the `ArchitectureBoundaryTests` suite in
`TownsfolkCoreTests` (`just test`, CI's `test` job). Both reject the UI frameworks
`SwiftUI`, `AppKit`, `UIKit`, and `Cocoa` (which re-exports AppKit), and the
OS-integration frameworks an adapter reaches for first — `ApplicationServices`
(accessibility), `Carbon` (hotkeys), and `ServiceManagement` (login items) — including
attributed
(`@preconcurrency import AppKit`) and kind-qualified (`import struct SwiftUI.Color`)
imports. A `//`-commented import is ignored, but one that starts a line inside a
`/* … */` block or a multi-line string literal is still flagged — delete it instead.
"Platform-agnostic" here means free of those frameworks, not buildable on Linux:
Apple-only frameworks such as Combine stay allowed, and so does Foundation — and so do
`os` and `OSLog`, deliberately, so Core can log (see Logging below).

## Ports and adapters

Code that talks to the OS — `NSWorkspace`, accessibility, a Carbon hotkey, an event tap,
an `NSPanel` overlay, a login item — lives in `TownsfolkPlatform`, never in Core, a view, or
the shell. It is always the same five pieces, and the template ships one worked example
of them to copy:

1. **The port**, in Core — a `Sendable` protocol taking and returning value types Core
   owns: `FrontmostAppProviding` in
   `Packages/TownsfolkKit/Sources/TownsfolkCore/FrontmostAppProviding.swift`.
2. **The adapter**, in Platform — the OS framework import, translating the OS type into
   the Core value and doing nothing else: `WorkspaceFrontmostAppProvider` in
   `Packages/TownsfolkKit/Sources/TownsfolkPlatform/WorkspaceFrontmostAppProvider.swift`.
3. **The fake**, in `TownsfolkTestSupport` — a real implementation answering from data the
   test hands it, used by the Core tests of whatever consumes the port
   (`.claude/rules/testing.md` › Fakes, not mocks): `FakeFrontmostAppProvider` in
   `Packages/TownsfolkKit/Tests/TownsfolkTestSupport/FakeFrontmostAppProvider.swift`.
4. **The local-machine test**, in `Packages/TownsfolkKit/Tests/TownsfolkPlatformTests` — the
   adapter against the *real* OS, which the fake by construction cannot check:
   `WorkspaceFrontmostAppProviderTests` asks the live `NSWorkspace`. Every suite there
   carries the `.requiresLocalMachine` trait, so it runs only with
   `RUN_LOCAL_MACHINE_TESTS=1` — what `just test-local` sets — and is reported as
   *skipped* under `just test` and in CI. It has to be: a runner has no logged-in GUI
   session and cannot be granted Accessibility, Input Monitoring, or Screen Recording,
   so such a test could only ever fail there. A skip is the honest outcome, and a human
   runs `just test-local` when an adapter changes and puts the output in the pull
   request (`.claude/rules/testing.md` › Where a Test Goes).
5. **The contract suite**, in `TownsfolkTestSupport` — one function over the protocol that
   checks every promise the port's `///` states, so the fake cannot quietly promise
   something the adapter does not: `FrontmostAppProvidingContract` in
   `Packages/TownsfolkKit/Tests/TownsfolkTestSupport/FrontmostAppProvidingContract.swift`.
   `FrontmostAppProvidingContractTests` in `TownsfolkCoreTests` runs it against the fake on
   every `just test` and in CI, and `WorkspaceFrontmostAppProviderTests` runs the same
   function against the adapter under `.requiresLocalMachine` (`just test-local`)
   (`.claude/rules/testing.md` › One Contract Suite per Port).

`App/` is the composition root: the only place that constructs an adapter and hands it
to a Core view model, so nothing below it knows which implementation answered. A test
substitutes the fake at that same seam.

`TownsfolkPlatform` is deliberately **outside the coverage floor** — `scripts/coverage.sh`
measures `Sources/TownsfolkCore` only. That is a constraint on adapters rather than a
licence: an adapter carries translation, so it has no branch worth a test. The moment
one needs a decision, the decision moves into Core behind the port, where the floor
sees it. What the floor cannot hold is the translation itself — whether the OS really
answers what the adapter assumes — and that is what the fourth and fifth pieces are for.

## Logging

**`TownsfolkCore` imports `os` directly, and that does not break the boundary.** The ban
list above is UI frameworks and the OS-integration frameworks an adapter reaches for;
`os` is neither. It pulls in no AppKit, it is available on every Apple platform Core is
meant to serve (`docs/adding-ios.md`), and it writes to the unified log rather than
touching the screen or the OS on Core's behalf. So logging is *not* modelled as a port:
a `LoggingPort` would buy no testability — a log line is not an outcome a test asserts —
and would cost every Core type an injected dependency it does not otherwise need. `os`
and `OSLog` are therefore absent from both halves of the ban list, `.swiftlint.yml`'s
`no_ui_import_in_core` and `ArchitectureBoundaryTests`, and a test case pins their
absence so narrowing that list later fails loudly.

Every logger lives in `AppLog` (`Packages/TownsfolkKit/Sources/TownsfolkCore/AppLog.swift`), the
one place the subsystem is spelled. It is a literal — the app's bundle identifier — and
not `Bundle.main.bundleIdentifier`, which answers for the test runner under `swift test`
and for the preview agent inside an Xcode preview; `scripts/bootstrap.sh` rewrites the
literal with the same placeholder replacement that rewrites `project.yml`, and
`AppLogTests` fails if the two disagree. `TownsfolkUI`, `TownsfolkPlatform`, and `App/` log
through the same loggers, which they already see by importing `TownsfolkCore`, so one
`just logs` stream shows the whole app.

The conventions that go with it — one category per concern, a privacy annotation on
anything user-derived, and never `print`/`debugPrint`/`NSLog` under `Sources/` or `App/`
(`.swiftlint.yml`'s `no_print_in_sources` rejects them) — are in
`.claude/rules/swift.md` › Logging. `FrontmostAppViewModel.refresh()` is the worked
example: it logs that a refresh happened `.public` and the other application's name
`.private`.

## Where new code goes

| You are adding… | It goes in… | Tested by… |
|---|---|---|
| Domain logic, state, view models | `Packages/TownsfolkKit/Sources/TownsfolkCore` | Swift Testing in `Tests/TownsfolkCoreTests` (coverage-gated) |
| Words a person reads | A Core view model returning `LocalizedStringResource`, with its key in `Packages/TownsfolkKit/Sources/TownsfolkCore/Resources/Localizable.xcstrings` (`localizing-the-app`) | The view model's tests + `LocalizationTests` in `Tests/TownsfolkCoreTests` |
| Views, view modifiers | `Packages/TownsfolkKit/Sources/TownsfolkUI` | Core view-model tests + the launch UI test |
| OS integration: AppKit, accessibility, hotkeys, login items, the file system beyond Foundation | `Packages/TownsfolkKit/Sources/TownsfolkPlatform`, as an adapter behind a Core port | Core tests through a fake of the port in `Tests/TownsfolkTestSupport` (coverage-gated), the port's contract suite against that fake, plus an opt-in local-machine test of the adapter and the same contract against it in `Tests/TownsfolkPlatformTests` — `just test-local` |
| App lifecycle, scenes, menus, wiring an adapter to a view model | `App/` | `LaunchUITests` + `just smoke` |

That last row carries one decision the table cannot: the app's *shape*. The template
ships a regular windowed app — `WindowGroup`, a Dock tile, a launch test that waits for
a window. A menu-bar agent (`LSUIElement`, `MenuBarExtra`, a launch test that waits for
a status item) changes `project.yml`, `App/TownsfolkApp.swift`, and
`LaunchUITests/LaunchTests.swift`, and nothing below them.
`.agents/skills/starting-an-app/references/app-shapes.md` gives both shapes as proven
code, including where an `NSApplicationDelegateAdaptor`'s delegate lives when
`MenuBarExtra` is not enough (`TownsfolkPlatform`, never `App/`).

Keeping logic out of views is what makes the coverage floor honest: the gate
measures the code that can regress silently, not SwiftUI layout. The same reasoning
keeps decisions out of adapters — see "Ports and adapters" above.

## Townsfolk on these layers

Everything above is the template's. This section is Townsfolk's own shape on it — the
result of the ADRs in [`docs/architecture/`](architecture/README.md), which hold the
reasons. What the app is comes from `AGENTS.md` › Product and
[`docs/product/requirements.md`](product/requirements.md), whose sections are cited as §.

### Principles

- **Rules decide; the model only writes.** Timing, speakers, seeds, events, moves,
  delays, influence, and catch-up are Core code, and the model fills in text through
  structured output (§3.11, ADR-0005). Rules out agents, tool calling, and the model
  choosing who speaks.
- **The log is the truth; a model session is thrown away.** Every call is rebuilt from
  the store and forgotten (§3.8, ADR-0004). Rules out memory kept in a session, and state
  that lives only in the model's context.
- **One writer at a time.** Ordinary scenes, responses, and catch-up go through one
  engine, one call after another. Rules out parallel generation and interleaved scenes.
- **Only while seen.** The town moves only while its window is visible (§3.7, ADR-0006).
  Rules out background work, timers while hidden, and anything that calls the person
  back.
- **Local, and enforced.** No network entitlement (ADR-0002), no analytics, and no text
  the person or the model wrote in a log or an error. Rules out any feature that needs
  the network without a new ADR.
- **The machinery stays out of sight.** Only founding shows a wait; a failed call is a
  scene that never appears (`docs/design/ux-guidelines.md`). Rules out progress, typing,
  and "generating" states in the UI.

### Shape

| Domain | Layer | Where |
|---|---|---|
| The town engine: schedule, speakers, seeds, influence, events, moves, catch-up, whether the town runs | Core | one engine that takes one step at a time, driven by an injected clock, random number generator, and `Tuning`, which holds the requirements' † starting values (`designing-core-logic`) |
| Prompts, `@Generable` outputs, the context budget, the retry rules | Core | `import FoundationModels` (ADR-0005) |
| The model call, availability, token counts | Platform | an adapter behind `LanguageModelProviding` (ADR-0005) |
| The town's store and its migrations | Core | `TownStore` over `import SQLite3` (ADR-0004) |
| Settings | Core | `UserDefaults` keys (ADR-0004) |
| Window visible, app active, Mac awake | Platform | an adapter behind `WindowPresenceProviding` (ADR-0006) |
| Seed tables and wording, in English and Japanese | Core resources | `Resources/Seeds/<language>.json` and `Localizable.xcstrings` (ADR-0007) |
| First run, founding, the timeline, the composer, the status line, profiles, Settings | UI | views built against the design lock (ADR-0008) |
| Scenes, menus, composition | App | one `Window` and one `Settings` scene (ADR-0001) |

Only Core values cross a boundary: the model's output enters Core as generated content
that Core decodes into its own types, presence arrives as a stream of values, and views
read view-model state and call its actions.

### Data

Requirements §5 lists the entities: the town, residents, posts, events (moves included),
the names you brought up, the schedule, and settings. All but settings live in one
SQLite file in the app's container, and settings are `UserDefaults` keys that survive
moving away (ADR-0004). The seed tables ship read-only with the app (ADR-0007). What a
model call sees is assembled from the store each time: the recent posts that fit the
context from roughly the last day, ongoing events, the residents involved, and the
relevant names you brought up (§3.8).

### Core flows

- **A scene.** The clock makes a scene due → the engine checks that the town runs
  (presence, the setting, model availability, the thermal state) → rules pick the seed
  and the speakers → Core builds the prompt within the budget, counting tokens through
  the port → the port runs the call → Core checks the speakers; a refusal is retried
  with a new seed up to twice, then the turn is skipped → one transaction stores the
  posts, tags, names, and the next due time → the view model reveals the posts one at a
  time, and the status line follows the tags and events.
- **Your post.** The composer hands Core the text → Core validates it and stores it at
  once → the engine schedules the responses, the first 2–10 minutes later at Normal →
  each is a scene seeded by your post (§3.5).
- **A pause.** Presence reports the window hidden, or the app inactive with the setting
  off → the engine stops and records when the town last ran → presence reports the
  window visible → the engine measures the pause and writes at most five catch-up scenes,
  one by one, with times spread across it, shown under "While you were away" (§3.7).
- **Founding, and moving away.** First run, or a confirmed move that first deletes the
  store → the model invents the town, its residents, and a first scene → one transaction
  stores them all → the timeline opens on "You moved to …" (§3.1, §3.9).

### Quality targets

| Target | Checked by |
|---|---|
| The timeline stays responsive past 100,000 posts | a Core test asserting that the page query uses the `happened_at` index (`EXPLAIN QUERY PLAN`), so its cost does not grow with the log |
| Refusals and failures never stall the town | Core tests with a fake model that refuses: at most 2 retries, then the turn is skipped; something refused 3 times in a row is left out |
| One generation at a time | a Core test with a fake model that records overlapping calls |
| Catch-up never floods | Core tests with a fake clock: at most 5 scenes after any pause, weeks included |
| No scene while the Mac is too hot | a Core test with the thermal state injected as serious |
| A failed step leaves nothing behind | a Core test in which a step fails mid-transaction and the store is unchanged (ADR-0004) |
| Every stored version still opens | one migration test per schema version (ADR-0004) |
| Nothing leaves the Mac | review: no network entitlement (ADR-0002), and nothing the person or the model wrote is logged (`.claude/rules/swift.md` › Logging) |
| The app launches without a model | `just uitest` and `just smoke` on CI, where the model is unavailable |

### Decisions

- [ADR-0001](architecture/adr/0001-app-shape.md) — one window, and closing it quits.
- [ADR-0002](architecture/adr/0002-sandbox-posture.md) — keep the App Sandbox, and add
  no entitlement.
- [ADR-0003](architecture/adr/0003-macos-27-floor.md) — macOS 27.0 as the floor.
- [ADR-0004](architecture/adr/0004-persistence-sqlite-in-core.md) — the town in one
  SQLite file owned by Core, and settings in `UserDefaults`.
- [ADR-0005](architecture/adr/0005-foundation-models-in-core.md) — Core speaks to
  Foundation Models, and the model call is a Platform adapter.
- [ADR-0006](architecture/adr/0006-window-presence-port.md) — window presence behind a
  Core port.
- [ADR-0007](architecture/adr/0007-english-and-japanese.md) — English and Japanese,
  switched inside the app.
- [ADR-0008](architecture/adr/0008-design-lock.md) — the design lock.
- [ADR-0009](architecture/adr/0009-not-distributed-yet.md) — not distributed in this
  version.

## What is contract and what is private

Nothing here is published, so the contract is not a package's export list. It is what
something outside the change can observe: another module of this package, a user's Mac
that ran an earlier build, or the user themselves. Four things are contract; everything
else is private.

| Contract | What depends on it | What changing it requires |
|---|---|---|
| **Core's public API** — every `public` declaration in `TownsfolkCore` | `TownsfolkUI`, `TownsfolkPlatform`, `App/`, and the tests, which all import `TownsfolkCore` as a separate module; `Package.swift` declares the library products so `App/` can link them, and nothing outside this repository does | Update every caller in the same pull request — the compiler finds them (`just build`, `just test`). A new public declaration carries a `///` saying why (the Review Checklist in `AGENTS.md`); a new port is an ADR (`AGENTS.md` › "Before changing the architecture") |
| **The bundle identifier** — `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, set by `scripts/bootstrap.sh` | Everything macOS keys by it on a user's Mac: the sandbox container that holds the app's `UserDefaults` and Application Support files, and its permission (TCC) grants; the log subsystem (`AppLog.subsystem`); and `just run`, `just logs`, and `just reset-permissions`, which read it through `scripts/bundle-id.sh` | Treat it as fixed once a build has left your machine: a new identifier is a new app to macOS, so the user's settings, files, and grants stay behind under the old one. Changing it is a human's decision, recorded as an ADR; `project.yml` and `AppLog.subsystem` change together (`AppLogTests` fails otherwise), and a signing or entitlements change that goes with it needs the sign-off in `AGENTS.md` › "Security and human approval" |
| **`UserDefaults` keys** — each key the app stores, and the type of its value | A user's saved preferences, read back by every later version | Renaming, removing, or retyping a key silently resets the user's value, because the old one is left unread. Read the old key and migrate it in Core, with a test that starts from the old value. Choosing `UserDefaults` at all is the persistence ADR |
| **File formats** — anything the app writes and reads back in a later version: a config file, saved state, a document | Files already on a user's disk, and for a hand-edited config ("A human-editable config file" below), the user who edits it | A new version still reads the old format — a version field and a migration in Core, with a test that decodes a sample of the previous format. The format and where it lives are the persistence ADR. A cache the app can rebuild from scratch is private |

The template ships no `UserDefaults` key and no file format. Townsfolk's are its four
settings keys and its town database, `town.sqlite`, both in
[ADR-0004](architecture/adr/0004-persistence-sqlite-in-core.md), and the `AppleLanguages`
default it writes for the menus macOS provides
([ADR-0007](architecture/adr/0007-english-and-japanese.md)).

**Private** is everything else: `internal` and `private` declarations, how an adapter
talks to the OS behind its port, view structure, file and type layout, test helpers, and
log categories and messages. Changing any of it needs only the gates that already run
(`AGENTS.md` › "Validating a change").

No gate notices a broken contract item except where one is named above — the compiler
for Core's public API, `AppLogTests` for the log subsystem. A renamed key or a changed
format passes every check and fails on the user's Mac, so review is what catches it, and
a user-visible change to any of the four owes a `CHANGELOG.md` entry.

## Recommended optional dependencies

The template ships with zero. When a real need appears, these are vetted
starting points.

### For tests and distribution

- [ViewInspector](https://github.com/nalexn/ViewInspector) — unit-test SwiftUI
  view hierarchies when view-model tests stop being enough.
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
  — pixel/structure regression tests for complex custom views.
- [Sparkle](https://sparkle-project.org/) — in-app updates once you distribute
  outside the App Store and users ask for auto-update (see docs/distribution.md).

### What a utility app reaches for first

Four needs turn up in nearly every hotkey-driven or menu-bar app, and each one's
zero-dependency answer is stated first on purpose. In this layout that answer is an
adapter in `TownsfolkPlatform` behind a Core port ("Ports and adapters" above) — usually
less code than integrating a package, and it keeps the decision in Core where the
coverage floor sees it. Reach for a package only when the "worth it when" sentence
describes your app.

Every package named below was checked against `.claude/rules/project.md`'s dependency
checklist on **2026-09-21**: license, latest release, whether the repository is
archived, the `platforms:` floor in its `Package.swift`, and whether that manifest
declares a binary target or a build plugin. Re-check before you add one — these facts
go stale, and the checklist's Need, Weight, and Advisories items are still yours to
answer for your app.

**Global hotkeys.** Carbon's `RegisterEventHotKey` is still the supported API for a
system-wide shortcut, and wrapping it costs roughly sixty lines: an adapter in
`TownsfolkPlatform` that installs one `EventHandlerUPP`, keeps an id→handler dictionary,
and hands Core a `Sendable` port. `Carbon` is one of the frameworks Core may not
import, which is why the adapter is the shape rather than a workaround. A package is
worth it when your users rebind shortcuts in the UI — the recorder control, its
conflict detection against system shortcuts, and persistence are the tedious part, not
the registration.

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — passes:
  MIT; 3.1.0 released 2026-09-11; not archived; floor `.macOS(.v10_15)`, at or below
  this package's `.macOS(.v14)`; one Swift target, no binary target, no build plugin,
  no package dependencies. It ships AppKit and SwiftUI recorder views, so it belongs to
  `TownsfolkUI` and `TownsfolkPlatform` — its types must not reach Core.

**Launch at login.** No package. `SMAppService.mainApp.register()` (ServiceManagement,
macOS 13+, below this package's macOS 14 floor) is the entire API, with
`SMAppService.mainApp.status` to read it back; it lives in a `TownsfolkPlatform` adapter
because `ServiceManagement` is also on Core's blocked-import list. Do not add
`sindresorhus/LaunchAtLogin`: that repository now redirects to `LaunchAtLogin-Legacy`
and is archived (last release v5.0.2, 2024-06-25), so it fails the checklist's
Continuity item outright. Its successor,
[LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) (MIT,
v1.1.0 released 2023-12-21, floor `.macOS(.v13)`), is a few lines around that same
call and fails the Need item instead — Foundation and one system framework already do
the job.

**A human-editable config file.** `Codable` plus `JSONEncoder`/`JSONDecoder` from
Foundation covers it: set `outputFormatting` to `[.prettyPrinted, .sortedKeys]` so the
file diffs cleanly, decode into a Core value type, and let a `TownsfolkPlatform` adapter
own the path under `~/Library/Application Support`. A package is worth it when the file
is a contract with the user rather than an implementation detail — when they are
expected to edit it by hand and want comments and trailing commas, which JSON has
neither of. That format is TOML.

- [TOMLDecoder](https://github.com/dduan/TOMLDecoder) — passes: MIT; 0.4.5 released
  2026-07-11; not archived; floor `.macOS(.v10_15)`; a pure-Swift library target with
  no binary target, and no package dependency in the default configuration (its
  benchmark, docs, and formatting dependencies sit behind `TOMLDECODER_*` environment
  opt-ins). It decodes only — rendering the file back out is yours to write, which
  usually fits, since the app writes a commented default once and the user owns it
  afterwards.
- [TOMLKit](https://github.com/LebJe/TOMLKit) reads *and* writes, but did not pass as
  checked: its manifest appends `apple/swift-docc-plugin` unconditionally, and a build
  plugin is build-time code the checklist routes to explicit human approval. Its latest
  release, 0.6.0, is also from 2024-01-03, with the last commit 2025-01-18. It wraps
  the toml++ C++ sources in a `CTOML` source target — that is not a binary target, so
  that item is fine; the build plugin and the release age are what stop it.

**Settings window.** Nothing is vetted here, and that is the finding rather than a gap
to fill later. SwiftUI's `Settings` scene (macOS 11+) already gives the ⌘, item, the
standard window, and its own scene phase; put a `TabView` in it, keep the state in a
Core view model, and persist it through a port exactly as above.
[Settings](https://github.com/sindresorhus/Settings) was checked and would pass on
license and shape (MIT, floor `.macOS(.v10_13)`, one resource-bearing target, no binary
target or build plugin), but its latest release, 3.1.1, is from 2024-05-07, and what it
buys is a toolbar-tab preferences window that the `Settings` scene now gives for free.
Add it only if you need that exact pre-Ventura look.

Before adding any dependency, apply the checklist in `.claude/rules/project.md`
(maintenance, license, transitive weight) and commit `Package.resolved` with it.
