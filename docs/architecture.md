# Architecture

This page describes the layers every app cut from this template starts with. What
Townsfolk decided on top of them — its shape, sandbox posture, persistence, dependencies,
distribution, macOS floor, and permissions — and why is
[Townsfolk on these layers](#townsfolk-on-these-layers).

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
the shell. It is always the same five pieces, and the window-presence port
([Window presence](#window-presence)) is the worked example of them to copy:

1. **The port**, in Core — a `Sendable` protocol taking and returning value types Core
   owns: `WindowPresenceProviding` in
   `Packages/TownsfolkKit/Sources/TownsfolkCore/Presence/WindowPresenceProviding.swift`,
   reporting the `WindowPresence` value beside it.
2. **The adapter**, in Platform — the OS framework import, translating the OS type into
   the Core value and doing nothing else: `WindowPresenceProvider` in
   `Packages/TownsfolkKit/Sources/TownsfolkPlatform/WindowPresenceProvider.swift`.
3. **The fake**, in `TownsfolkTestSupport` — a real implementation answering from data the
   test hands it, used by the Core tests of whatever consumes the port
   (`.claude/rules/testing.md` › Fakes, not mocks): `FakeWindowPresenceProvider` in
   `Packages/TownsfolkKit/Tests/TownsfolkTestSupport/FakeWindowPresenceProvider.swift`.
4. **The local-machine test**, in `Packages/TownsfolkKit/Tests/TownsfolkPlatformTests` — the
   adapter against the *real* OS, which the fake by construction cannot check:
   `WindowPresenceProviderTests` puts a real `NSWindow` on screen and watches the live
   window server and notification centers. Every suite there carries the
   `.requiresLocalMachine` trait, so it runs only with
   `RUN_LOCAL_MACHINE_TESTS=1` — what `just test-local` sets — and is reported as
   *skipped* under `just test` and in CI. It has to be: a runner has no logged-in GUI
   session and cannot be granted Accessibility, Input Monitoring, or Screen Recording,
   so such a test could only ever fail there. A skip is the honest outcome, and a human
   runs `just test-local` when an adapter changes and puts the output in the pull
   request (`.claude/rules/testing.md` › Where a Test Goes).
5. **The contract suite**, in `TownsfolkTestSupport` — one function over the protocol that
   checks every promise the port's `///` states, so the fake cannot quietly promise
   something the adapter does not: `WindowPresenceProvidingContract` in
   `Packages/TownsfolkKit/Tests/TownsfolkTestSupport/WindowPresenceProvidingContract.swift`.
   `WindowPresenceProvidingContractTests` in `TownsfolkCoreTests` runs it against the fake on
   every `just test` and in CI, and `WindowPresenceProviderTests` runs the same
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
`.claude/rules/swift.md` › Logging. `AppLog.presence` is the worked example: `App/`
logs every value `WindowPresenceProviding` reports, its three flags `.public` because
they are states that say nothing about the person. `AppLog.settings` shows the other
side: `SettingsViewModel` logs whether a submitted name was taken, never the name.

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

Everything above is the template's. This section is Townsfolk's own shape on it, and
[Decisions](#decisions) below records each hard-to-reverse choice behind it with its
reasons. What the app is comes from `AGENTS.md` › Product and
[`docs/product/requirements.md`](product/requirements.md), whose sections are cited as §.

### Principles

- **Rules decide; the model only writes.** Timing, speakers, seeds, events, moves,
  delays, influence, and catch-up are Core code, and the model fills in text through
  structured output (§3.11, [The on-device model](#the-on-device-model)). Rules out
  agents, tool calling, and the model choosing who speaks.
- **The log is the truth; a model session is thrown away.** Every call is rebuilt from
  the store and forgotten (§3.8, [Persistence](#persistence)). Rules out memory kept in a
  session, and state that lives only in the model's context.
- **One writer at a time.** Ordinary scenes, responses, and catch-up go through one
  engine, one call after another. Rules out parallel generation and interleaved scenes.
- **Only while seen.** The town moves only while its window is visible (§3.7,
  [Window presence](#window-presence)). Rules out background work, timers while hidden,
  and anything that calls the person back.
- **Local, and enforced.** No network entitlement ([Sandbox posture](#sandbox-posture)),
  no analytics, and no text the person or the model wrote in a log or an error. Rules out
  any feature that needs the network without a `## Product` change and a recorded
  decision first.
- **The machinery stays out of sight.** Only founding shows a wait; a failed call is a
  scene that never appears (`docs/design/ux-guidelines.md`). Rules out progress, typing,
  and "generating" states in the UI.

### Shape

| Domain | Layer | Where |
|---|---|---|
| The town engine: schedule, speakers, seeds, influence, events, moves, catch-up, whether the town runs | Core | one engine that takes one step at a time, driven by an injected clock, random number generator, and `Tuning`, which holds the requirements' † starting values (`designing-core-logic`) |
| Prompts, `@Generable` outputs, the context budget, the retry rules | Core | `import FoundationModels` ([The on-device model](#the-on-device-model)) |
| Candidate-post sentence validation | Core | `SceneValidation` uses `import NaturalLanguage` and `NLTokenizer(unit: .sentence)` ([Sentence validation](#sentence-validation)) |
| The model call, availability, token counts | Platform | an adapter behind `LanguageModelProviding` ([The on-device model](#the-on-device-model)) |
| The town's store and its migrations | Core | `TownStore` over `import SQLite3` ([Persistence](#persistence)) |
| Settings | Core | `UserDefaults` keys ([Persistence](#persistence)) |
| Window visible, app active, Mac awake | Platform | an adapter behind `WindowPresenceProviding` ([Window presence](#window-presence)) |
| Seed tables and wording, in English | Core resources | `Resources/SeedTables.json` and `Localizable.xcstrings` ([Language](#language)) |
| First run, founding, the timeline, the composer, the status line, profiles, Settings | UI | views built against the design lock ([`docs/design/design-direction.md` › Design lock](design/design-direction.md#design-lock)) |
| Scenes, menus, composition | App | one `Window` and one `Settings` scene ([App shape](#app-shape)) |

Only Core values cross a boundary: the model's output enters Core as generated content
that Core decodes into its own types, presence arrives as a stream of values, and views
read view-model state and call its actions.

### Data

Requirements §5 lists the entities: the town, residents, posts, events (moves included),
the names you brought up, the schedule, and settings. All but settings live in one
SQLite file in the app's container, and settings are `UserDefaults` keys that survive
moving away ([Persistence](#persistence)). The seed tables ship read-only with the app,
in `Resources/SeedTables.json`, loaded by `SeedTables.load()`. What a model call sees is
assembled from the store each time: the recent posts that fit the context from roughly
the last day, ongoing events, the residents involved, and the relevant names you brought
up (§3.8).

### Core flows

- **A scene.** The clock makes a scene due → the engine checks that the town runs
  (presence, the setting, model availability, the thermal state) → rules pick the seed
  and the speakers → Core builds the prompt within the budget, counting tokens through
  the port → the port runs the call → Core checks the speakers; a refusal is retried
  with a new seed up to twice, then the turn is skipped → one transaction stores the
  posts, tags, names, and the next due time → the view model reveals the posts one at a
  time, and the status line follows the tags and events.
- **Your post.** The composer validates the text, then calls its main-actor writer.
  The app's writer captures `SettingsStore.speed` before its first await and calls
  `TownEngine.submitYourPost(_:speed:)`. The engine draws without waiting for a scene
  already being written; one store transaction inserts the post, adds its one to three
  responses and prunes the oldest pending groups. The committed post change updates the
  timeline, and the engine re-arms its wait. Response dates retain the Return-time speed;
  ordinary dates follow later speed changes. Due responses precede ordinary scenes after
  the preceding scene's last post, using the same writer with the post quoted first and
  ordinary retry seeds. Success stores the scene and removes only that pending response
  atomically; alternatives keep it for later, while a left-out post loses its schedule.
  That same call extracts at most three literal names from the original user post only
  for its first successfully stored quoted response. Validation retains source spelling;
  the response transaction rechecks prior responses and merges names ignoring case,
  including excluded rows, with source links and original source timestamps. A refusal,
  ordinary fallback, cancellation, or rollback consumes no extraction opportunity.
  The response transaction rechecks the exact pending post and due time and the source's
  included flag. A response withdrawn while the model is running commits nothing and
  leaves the ordinary due time unchanged. Coming-back seeds require a prior response
  and remain eligible through 24 hours. The additive `SceneRequest.YourPostContext`
  policy defaults to `.all` for standalone writer callers; the engine chooses
  `.answeredOnly`, filtering unanswered user posts before ordering and limiting recent
  context. An explicitly quoted due-response seed is still added to its prompt.
  Legacy `TownStore.storeYourPost(_:)` writes remain supported. The engine repairs every
  eligible unscheduled post within the newest capped post set, bounded before filtering
  excluded or already answered posts so older displaced history does not return. Repair
  rechecks eligibility and the cap inside its transaction. These legacy posts carry no
  persisted speed, so repair necessarily uses the current setting; only the atomic
  posting path guarantees the speed at Return.

- **Names becoming interests.** Included names form another ordinary seed pool, with
  kinds drawn uniformly before their candidates. A successful name scene may give an
  unheld name to one actual living speaker with room below five interests. The scene
  appends only the interest association and rechecks inclusion, capacity, and the lack
  of any living holder at commit. An excluded name seed withdraws the whole held scene.
  Newcomers draw from included names with no living holder with probability 0.5. The
  selected name survives every prompt-budget reduction and becomes their sole initial
  interest in the move transaction; an excluded or newly claimed seed retries within
  the ordinary newcomer attempt limit. Past residents' holdings do not block a name.
- **A pause.** Presence reports the window hidden, or the app inactive with the setting
  off → the engine stops and records when the town last ran → presence reports the
  window visible → the engine measures the pause and writes at most five catch-up scenes,
  one by one, with times spread across it, shown under "While you were away" (§3.7).
- **Founding, and moving away.** First run, or a confirmed move that first deletes the
  store → the model invents the town, its residents, and a first scene → one transaction
  stores them all, with the next ordinary scene due one drawn interval after the first
  scene's last post → the timeline opens on "You moved to …" (§3.1, §3.9). The interval
  uses the same `ScenePace`, injected generator, and `Tuning` as later scenes, at the
  selected speed passed through `FoundingViewModel` to `Founder.found` (Normal by
  default). The last-post anchor and due time share the store's millisecond precision;
  the first engine step therefore waits for the scheduled turn.

Ordinary profile seeds include stored relationships, identified by the other resident's
ID. Casting derives these candidates from the roster rather than `ProfileAspect.allCases`,
which retains the scalar aspects used by founding. A relationship seed names the partner
and stored description; both residents speak when both still live in town. A moved-away
partner remains in the roster for naming, and refusal retries include only relationships
whose living partner is already among the speakers. Repeated links to one partner form
one candidate. For a delayed reply, these constraints are checked again after its reply
lead replaces a speaker; incompatible retries are refilled from the same eligible pools.

The public `SceneSeed.ProfileAspect.relationship(Resident.ID)` case requires exhaustive
caller switches to handle relationships. `SceneRequestError.unknownRelationship` rejects
an absent stored link; `unknownResident` also rejects a relationship partner missing from
the roster. Callers switching over request errors must handle the added case.

### Quality targets

| Target | Checked by |
|---|---|
| The timeline stays responsive past 100,000 posts | a Core test asserting that the page query uses the `happened_at` index (`EXPLAIN QUERY PLAN`), so its cost does not grow with the log |
| Refusals and failures never stall the town | Core tests with a fake model that refuses: at most 2 retries, then the turn is skipped; something refused 3 times in a row is left out |
| One generation at a time | a Core test with a fake model that records overlapping calls |
| Catch-up never floods | Core tests with a fake clock: at most 5 scenes after any pause, weeks included |
| No scene while the Mac is too hot | a Core test with the thermal state injected as serious |
| A failed step leaves nothing behind | a Core test in which a step fails mid-transaction and the store is unchanged ([Persistence](#persistence)) |
| Every stored version still opens | one migration test per schema version ([Persistence](#persistence)) |
| Nothing leaves the Mac | review: no network entitlement ([Sandbox posture](#sandbox-posture)), and nothing the person or the model wrote is logged (`.claude/rules/swift.md` › Logging) |
| The app launches without a model | `just uitest` and `just smoke` on CI, where the model is unavailable |

### Decisions

Each hard-to-reverse choice the owner made is recorded here: what was decided, why it
beat the alternatives, what is still open, and the sources it leans on, each with the
date it was checked. The kinds of change that land here are listed in `AGENTS.md` ›
"Before changing the architecture"; such a change updates its subsection in the same
pull request, and the owner's sign-off is still what "Security and human approval" asks
for. The design lock lives in
[`docs/design/design-direction.md` › Design lock](design/design-direction.md#design-lock).

#### App shape

`App/TownsfolkApp.swift` declares one `Window` scene, id `town`, holding the town
window's root view, and one `Settings` scene. The window opens at 380 × 680 pt
(`.defaultSize`) with a minimum of 320 × 440 pt (the root view's
`.frame(minWidth:minHeight:)`), and is titled with the town's name, "Townsfolk" until a
town exists. The app keeps its Dock tile and the standard main menu; the Town menu goes
in a `Commands` group on the scene (ux-flows S8). `project.yml` carries no shape key. SwiftUI
autosaves the window's frame under the scene's id (`NSWindow Frame town`), so its size
and position come back across launches with no code — checked by moving, resizing,
quitting, and relaunching, 2026-09-30 (#7).

A `Window` that is the app's primary scene quits the app when it closes, with no
delegate, and offers no File › New Window. A `WindowGroup` lets people open more windows
and keeps running after the last one closes, both contrary to §3.7; a menu-bar agent is
the non-goal "Running while out of sight". The cost is intended: a closed window cannot
be reopened without relaunching. If the town stops too often because work windows cover
it, always-on-top and every-Space are the first things to revisit (the non-goal "Window
extras").

- <https://developer.apple.com/documentation/swiftui/window> — "If your app uses a
  single window as its primary scene, the app quits when the window closes." — checked
  2026-09-30

#### Sandbox posture

`App/Townsfolk.entitlements` holds `com.apple.security.app-sandbox` and nothing else;
`project.yml` declares no `INFOPLIST_KEY_NS…UsageDescription` key, and the app asks for
no TCC permission. Without `com.apple.security.network.client` the sandbox gives the app
no outgoing connection, so "nothing leaves the Mac" (requirements §4) is enforced by the
OS, not only promised by the code. The Foundation Models documentation names no
entitlement for the on-device model; the one it mentions is for Private Cloud Compute,
which Townsfolk does not use. Keeping the sandbox also keeps the Mac App Store open.

Outside information and external integrations (both Later) would need the network client
entitlement and a `## Product` change first; screenshot input (Next) would need Screen
Recording only if it captured the screen rather than took an image the person hands it.

- <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client>
  — whether the app "may open outgoing network connections"; macOS 10.7+ — checked
  2026-09-30
- <https://developer.apple.com/documentation/foundationmodels> — no entitlement or
  Info.plist key for the on-device model — checked 2026-09-30
- <https://developer.apple.com/app-store/review/guidelines/> — guideline 2.4.5(i): Mac
  apps "must be appropriately sandboxed" — checked 2026-09-30

#### macOS floor

The floor is macOS 27.0, the OS the owner uses and the model the app is tuned against:
`deploymentTarget.macOS: "27.0"` in `project.yml` and `platforms: [.macOS("27.0")]` in
`Package.swift`, built with Xcode 27 (`.xcode-version` 27.0), with every macOS CI job on
`runs-on: xcode-27`. It states what is supported, not what an API needs: in the macOS
26.5 SDK the Foundation Models types are macOS 26.0+ and `tokenCount(for:)` 26.4+.

**CodeQL is paused.** No CodeQL workflow runs while the floor is macOS 27: CodeQL's
published support stops at macOS 26 hosts and Swift 6.3, and Xcode 27.0 compiles Swift
6.4. On `xcode-27` its build tracer cannot launch macOS 27's arm64e-only `sandbox-exec`,
so analysis ran only with SwiftPM's and the compiler's sandboxes disabled; the owner
declined to land that unsupported configuration (2026-10-06), and analyzing with a
second, older Xcode was rejected too (2026-10-03). CodeQL is not a required check, the
package has no external dependency, and the app makes no network call, so the pause
costs little; issue #54 restores `.github/workflows/codeql.yml` once CodeQL supports
both.

`xcode-27` is the only hosted image on macOS 27, and it is in Preview, outside the
Actions SLA; when GitHub ships a GA image on macOS 27, the `runs-on:` labels move to it.
Keeping CI on `macos-26` was rejected because the launch and smoke tests launch the app
and would pause until then; a 26.4 floor was rejected as support nobody exercises.
Everyone who builds the app needs Xcode 27, which runs on macOS 26.6 or later. On CI the
launch and smoke tests see the model-unavailable state (ux-flows S7), never a town.

- Unverified: whether Apple Intelligence is ever available inside a macOS virtual
  machine such as a CI runner. Nothing depends on it.
- <https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes>
  — "Xcode 27 requires a Mac running macOS Tahoe 26.6 or later."; ships the macOS 27 SDK
  — checked 2026-09-30
- <https://developer.apple.com/news/releases/> — Xcode 27 (27A266a) released 2026-09-14
  — checked 2026-09-30
- <https://github.com/actions/runner-images> — the `xcode-27` image is Preview, and a
  beta image's workflows "do not fall under the customer SLA in place for Actions";
  `macos-26` carries no Xcode 27 — checked 2026-09-30
- <https://codeql.github.com/docs/codeql-overview/system-requirements/> — supported
  hosts macOS 14, 15, and 26 — checked 2026-10-06
- <https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/> —
  Swift 5.4–6.3 — checked 2026-10-06

#### Persistence

The town lives in one SQLite database, `town.sqlite`, in a `Town` directory under the
app container's Application Support directory. `TownsfolkCore` owns it through
`import SQLite3`, the SDK's system library, which links with no extra settings. A
`TownStore` actor holds the connection and takes and returns Core value types; the
composition root hands it its directory, so a test hands it a temporary directory of
its own. There is no port: the store runs the same under `swift test`.

- **Tables** follow requirements §5, with an index on the posts' `happened_at` for
  newest-first paging past 100,000 posts.
- **Format.** Dates are integer milliseconds since 1970 UTC, so keyset comparisons are
  exact; ids are uppercase UUID text; a list inside a value is a child table ordered by
  `position`; resident reads order by `moved_in_at`, `name COLLATE BINARY`, then `id`; foreign
  keys are on and deferred to the commit; enum codes are text with no `CHECK`, so a later
  version can add one without rebuilding a table; the journal is SQLite's default rollback
  journal. `TownSchema` (`Sources/TownsfolkCore/Store/`) is the source of truth for the
  schema.
- **One transaction per step of the town** — a scene's posts, tags, names, and next due
  time and additive resident-interest associations; a new resident with its initial
  interest and move event; a founded town, written only after all of
  its generation succeeded — so a crash repeats or loses nothing.
- **Versions.** `PRAGMA user_version` holds the schema version; Core keeps an ordered
  list of migrations, run in one transaction when the store opens, each with a test that
  builds the previous version's database.
- **Moving away** closes the store and deletes the `Town` directory, the database and
  its companion files, before the next town is founded.
- **Settings are `UserDefaults` keys**, outside `Town/` so moving away keeps them, read
  and written by `SettingsStore` through an injected `UserDefaults`: see
  [What is contract and what is private](#what-is-contract-and-what-is-private).

SQLite beat SwiftData because Core's `Sendable` value types would be mapped to and from
SwiftData's model classes, and its schema and migrations would be SwiftData's rather than
the app's; it beat JSON files, where a write that spans files is not atomic and paging is
hand-written; it beat GRDB.swift on the dependency checklist's Need item, at the cost of
a few hundred lines of binding code. Under Swift 6 the actor closes its connection in an
`isolated deinit`: a plain `deinit` does not compile, because the handle is not
`Sendable` (experiment, Swift 6.3.2, 2026-09-30). If residents' long-term memory (Later)
needs text search over the log, SQLite's full-text search is the first thing to check.

- <https://www.sqlite.org/formatchng.html> — newer SQLite versions read files written by
  older ones back to 3.0.0, so an OS update strands no town — checked 2026-09-30

#### The on-device model

Core owns the conversation with the model. `TownsfolkCore` imports `FoundationModels`
(not on Core's banned imports) and declares the `@Generable` output of each call — a
scene, a founded town, a new resident, an event's description — with the code that
builds the instructions and prompts, fits them to the budget, and checks what comes back:
a scene naming a speaker who was not chosen is discarded. The schema's guides are part of
what the model is told, so they sit under the coverage floor with the prompt, defined
once rather than mirrored in an adapter.

The call itself is a port, `LanguageModelProviding` (`Sources/TownsfolkCore/Model/`),
answering availability (available, Apple Intelligence off, device not eligible, model
still downloading), the context size and a prompt's token count, and a response under a
generation schema, returned as generated content Core decodes. Its adapter,
`SystemLanguageModelProvider`, uses `SystemLanguageModel.default` with the default
guardrails, opens a fresh `LanguageModelSession` per call and drops it, and maps the
framework's errors to `ModelCallError` — refused (a guardrail violation or a refusal),
over the context size, unavailable, or other — carrying no prompt or generated text.
`FakeLanguageModelProvider` answers from scripted generated content, and
`LanguageModelProvidingContract` runs against both.

The rules around the call are Core's: retry with a new seed, leave out what keeps being
refused, retry once with half the posts after an overflow, skip a turn, one call at a
time, and no call while `ProcessInfo`'s thermal state is serious or critical (read
through an injected closure). Core's build now depends on an SDK whose API moves every
year; a model other than the system one (Later) would sit behind the same port, and
macOS 27's `LanguageModel` protocol is the first place to look.

- Observed on this Mac (2026-10-08): `SystemLanguageModelProvider.contextSize` returned
  4,096 on a Mac14,2 (Apple M2, 16 GiB RAM) running macOS 27.0 (build 26A428). The
  on-device `LanguageModelProvidingContract` passed. This is one machine's result; the
  app reads the context size at run time.
- Unverified: whether the owner's Mac gets only the smaller on-device model; read at run
  time.
- Settled: opening System Settings for ux-flows S7. Apple documents no URL that opens
  System Settings at the Apple Intelligence pane (searched 2026-09-30; the
  `x-apple.systempreferences:` pane identifiers in circulation are undocumented), so the
  Apple Intelligence off message names the pane — "Turn it on in System Settings ›
  Apple Intelligence & Siri." — and its Open System Settings button opens the app
  itself: `AvailabilityNotice.systemSettingsURL`,
  `file:///System/Applications/System%20Settings.app`, passed to SwiftUI's `openURL`.
  On macOS 27.0 that app is present with bundle id `com.apple.systempreferences`, and
  its Siri pane (`SiriPreferenceExtension.appex`) titles itself "Apple Intelligence &
  Siri" on a Mac that can run Apple Intelligence (its `SIRI_SIDEBAR_TITLE_SAE` string;
  "Siri" otherwise, where the message is never shown) — checked on this Mac 2026-10-07.
  If a later SDK or Apple page documents a URL for the pane, the button uses it and the
  message drops the location.
- The error cases the macOS 27.0 SDK declares, each with the `ModelCallError` case
  `SystemLanguageModelTranslation` maps it to (the SDK's `FoundationModels.swiftinterface`,
  Xcode 27.0 27A266a, checked 2026-10-06):
  - `LanguageModelError`: `contextSizeExceeded` → over the context size;
    `guardrailViolation` and `refusal` → refused; `rateLimited`, `unsupportedCapability`,
    `unsupportedTranscriptContent`, `unsupportedGenerationGuide`,
    `unsupportedLanguageOrLocale`, and `timeout` → other.
  - `SystemLanguageModel.Error.assetsUnavailable` → unavailable.
  - `LanguageModelSession.Error`: `concurrentRequests` and
    `transcriptMutationWhileResponding` → other.
  - `GeneratedContent.ParsingError`, `GenerationSchema.SchemaError` (`duplicateType`,
    `duplicateProperty`, `emptyTypeChoices`, `undefinedReferences`), and
    `LanguageModelSession.ToolCallError` → other.
  - `LanguageModelSession.GenerationError`, deprecated in macOS 27 in favour of the above
    but still declared: `exceededContextWindowSize` → over the context size;
    `assetsUnavailable` → unavailable; `guardrailViolation` and `refusal` → refused;
    `unsupportedGuide`, `unsupportedLanguageOrLocale`, `decodingFailure`, `rateLimited`, and
    `concurrentRequests` → other. Naming it outside a deprecated declaration is a warning,
    an error under this package's settings, so the adapter reaches it through a
    conformance declared in a deprecated extension.
  - Never thrown by this adapter, which uses neither: `PrivateCloudComputeLanguageModel.Error`
    (`networkFailure`, `quotaLimitReached`, `serviceUnavailable`) and the deprecated
    `SystemLanguageModel.Adapter.AssetError` (`invalidAsset`, `invalidAdapterName`,
    `compatibleAdapterNotFound`).
  - `CancellationError` passes through unmapped; any other error, and a case a later SDK
    adds, → other.
  - The SDK declares three unavailable reasons, `appleIntelligenceNotEnabled`,
    `modelNotReady`, and `deviceNotEligible`, mapped to Apple Intelligence off, model not
    ready, and device not eligible; a reason a later SDK adds reads as model not ready.
- <https://developer.apple.com/documentation/foundationmodels/managing-the-context-window>
  — Apple documents a context window of 4,096 tokens per session; checked 2026-09-30
- <https://developer.apple.com/documentation/foundationmodels/languagemodel> — "A
  protocol that you use to interface with a model."; macOS 27.0+ — checked 2026-09-30

#### Sentence validation

Core retains `import NaturalLanguage` for `NLTokenizer(unit: .sentence)`, because
sentence validity determines whether generated text may enter the feed. This comparison
with Foundation's `.bySentences` is reproducible with:

```swift
import Foundation
import NaturalLanguage

let text = "Dr. Sato said hi. Nice."
let range = text.startIndex ..< text.endIndex
var foundationSentenceCount = 0
text.enumerateSubstrings(in: range, options: .bySentences) { _, _, _, _ in
    foundationSentenceCount += 1
}
let tokenizer = NLTokenizer(unit: .sentence)
tokenizer.string = text
let naturalLanguageSentenceCount = tokenizer.tokens(for: range).count
print("Foundation .bySentences: \(foundationSentenceCount); NLTokenizer: \(naturalLanguageSentenceCount)")
```

On macOS 27.0 with Swift 6.4, this reports `Foundation .bySentences: 3; NLTokenizer: 2`
(checked 2026-10-08). Keep `NLTokenizer` so this valid two-sentence post is accepted.

- `Packages/TownsfolkKit/Sources/TownsfolkCore/Writing/SceneValidation.swift` — sentence
  counting with `NLTokenizer` — checked 2026-10-08
- `Packages/TownsfolkKit/Tests/TownsfolkCoreTests/Writing/WriterValidationTests.swift` — the
  accepted `Dr. Sato said hi. Nice.` regression case — checked 2026-10-08

#### Window presence

Whether the town runs is decided in Core from a stream of presence values that
`WindowPresenceProviding` reports: the town window visible (not fully occluded), the app
active, and the Mac awake. The adapter, `WindowPresenceProvider`, observes the window's
occlusion, the app becoming active and inactive, `NSWorkspace`'s sleep and wake,
screens-did-sleep and screens-did-wake, and session-did-resign-active and
session-did-become-active, reporting the window not visible while the screens sleep or
the session is inactive, and decides nothing. It finds the town window by its
`NSWindow.identifier`, which SwiftUI sets to the scene's id, so `App/` hands it the same
`"town"` (in a `just run`, `visible=true` arrived 17 ms after the window appeared, #13).
Core combines the latest presence with the "keep moving" setting and the model's
availability, stops town time, and records when it last ran, so the next start measures
the pause.

Letting views drive this through scene phase would put the rule outside the coverage
floor, and running on a timer is a non-goal. Occlusion is coarse: a sliver showing from
under another window counts as visible.

- Unverified: whether occlusion reports a locked screen (⌃⌘Q) as not visible; no
  `NSWorkspace` notification covers it. Settled by a human run: lock the screen with the
  app running and `just logs` streaming, and read `visible=` while locked.
- <https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct/visible>
  — "if not set, the entire window is occluded" — checked 2026-09-30

#### Language

English only, with no language setting (2026-10-06): `defaultLocalization: "en"`, a
String Catalog holding English alone, and one seed file, `Resources/SeedTables.json`.
An event kind's id is stored with every event, so an id is never removed or reused; its
wording may change. Adding a language is the owner's decision, recorded here first;
`localizing-the-app` lists the work it involves.

#### Distribution

This version is not distributed. The owner runs a build of this repository (`just run`);
no `v*` tag is pushed, so the release workflow never runs; no signing or notarization
secret is configured; and the app icon stays a placeholder. The release workflow and
`docs/distribution.md` stay as the template ships them, and the sandbox stays on, so
every channel stays open.

- Owner decides, at release: the Mac App Store, a signed and notarized DMG, or both —
  through a release issue the owner files, which updates this subsection.
- Owner decides, from their own use: how the app stands against the Foundation Models
  acceptable-use requirements, which prohibit a use that "Enables dependency or spiraling
  user interactions detrimental to a user's mental health".
- <https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/>
  — the prohibited use quoted above; the page shows no date — checked 2026-09-30

## What is contract and what is private

Nothing here is published, so the contract is not a package's export list. It is what
something outside the change can observe: another module of this package, a user's Mac
that ran an earlier build, or the user themselves. Four things are contract; everything
else is private.

| Contract | What depends on it | What changing it requires |
|---|---|---|
| **Core's public API** — every `public` declaration in `TownsfolkCore` | `TownsfolkUI`, `TownsfolkPlatform`, `App/`, and the tests, which all import `TownsfolkCore` as a separate module; `Package.swift` declares the library products so `App/` can link them, and nothing outside this repository does | Update every caller in the same pull request — the compiler finds them (`just build`, `just test`). A new public declaration carries a `///` saying why (the Review Checklist in `AGENTS.md`); a new port is recorded in [Decisions](#decisions) (`AGENTS.md` › "Before changing the architecture") |
| **The bundle identifier** — `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, set by `scripts/bootstrap.sh` | Everything macOS keys by it on a user's Mac: the sandbox container that holds the app's `UserDefaults` and Application Support files, and its permission (TCC) grants; the log subsystem (`AppLog.subsystem`); and `just run`, `just logs`, and `just reset-permissions`, which read it through `scripts/bundle-id.sh` | Treat it as fixed once a build has left your machine: a new identifier is a new app to macOS, so the user's settings, files, and grants stay behind under the old one. Changing it is a human's decision, recorded in [Decisions](#decisions); `project.yml` and `AppLog.subsystem` change together (`AppLogTests` fails otherwise), and a signing or entitlements change that goes with it needs the sign-off in `AGENTS.md` › "Security and human approval" |
| **`UserDefaults` keys** — each key the app stores, and the type of its value | A user's saved preferences, read back by every later version | Renaming, removing, or retyping a key silently resets the user's value, because the old one is left unread. Read the old key and migrate it in Core, with a test that starts from the old value. Choosing `UserDefaults` at all is a persistence decision ([Persistence](#persistence)) |
| **File formats** — anything the app writes and reads back in a later version: a config file, saved state, a document | Files already on a user's disk, and for a hand-edited config ("A human-editable config file" below), the user who edits it | A new version still reads the old format — a version field and a migration in Core, with a test that decodes a sample of the previous format. The format and where it lives are a persistence decision ([Persistence](#persistence)). A cache the app can rebuild from scratch is private |

The template ships no `UserDefaults` key and no file format. Townsfolk's are its town
database, `town.sqlite` ([Persistence](#persistence)), and exactly three settings keys:
`settings.displayName` (a String), `settings.speed` (`"slow"`, `"normal"`, or `"fast"`),
and `settings.keepsMovingInOtherApps` (a Bool).

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
  this package's `.macOS("27.0")`; one Swift target, no binary target, no build plugin,
  no package dependencies. It ships AppKit and SwiftUI recorder views, so it belongs to
  `TownsfolkUI` and `TownsfolkPlatform` — its types must not reach Core.

**Launch at login.** No package. `SMAppService.mainApp.register()` (ServiceManagement,
macOS 13+, below this package's macOS 27.0 floor) is the entire API, with
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
