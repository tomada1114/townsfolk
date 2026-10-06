---
name: designing-core-logic
description: >
  Covers how logic in TownsfolkCore is shaped: time, the current date, Locale, and
  randomness injected rather than read (Clock, any Clock<Duration>, Date.now,
  Locale.current, SystemRandomNumberGenerator), tunable numbers gathered in one Tuning
  type, action-shaped methods on @MainActor @Observable view models, and the patterns
  this template deliberately does not adopt. Use when adding a type, a view model, a
  timer, a debounce, a delay, a formatted string, a threshold, or anything random to
  TownsfolkCore, or when reaching for a repository, a coordinator, a use-case class, or an
  event bus.
---

# Designing Core Logic

**Owns:** how a type or view model in `TownsfolkCore` is shaped so its logic stays
deterministic under `swift test` — what it is handed rather than reads, where tunable
numbers live, what its entry points look like, and which patterns are not adopted.
**Does not own:** the test-first loop itself (`tdd`); an OS integration behind a port
(`integrating-system-apis`, `docs/architecture.md` › Ports and adapters); recording a
decision to adopt a new pattern (`docs/architecture.md` › Townsfolk on these layers,
`updating-docs`); the module
boundaries and import rules (`AGENTS.md` › Architecture, `.claude/rules/swift.md`).

## Why this exists

The 80% coverage floor on `TownsfolkCore` only means something if a test can reach every
branch without waiting, without depending on the machine's clock, language, or luck.
Anything Core would read from the world — the time, the locale, a random number — is
therefore an input, the same way window presence reaches Core as values from an
`any WindowPresenceProviding` instead of Core watching `NSWindow` itself.

These are standard-library and Foundation values, not OS integrations, so they are
injected as plain parameters. They do not need a port in `TownsfolkPlatform`; add a port
only when the answer really comes from an OS framework Core may not import.

## Inject time

- **Waiting** (a delay, a debounce, a timeout, a periodic tick): take a clock, not
  `Task.sleep(for:)` against the real one. `platforms: [.macOS("27.0")]` in
  `Packages/TownsfolkKit/Package.swift` makes `Clock`, `ContinuousClock`, and
  `SuspendingClock` available without an availability check.

  ```swift
  @MainActor @Observable
  public final class AutosaveViewModel {
      private let clock: any Clock<Duration>
      private let tuning: Tuning

      public init(clock: any Clock<Duration> = ContinuousClock(), tuning: Tuning = .default) {
          self.clock = clock
          self.tuning = tuning
      }

      public func textChanged() async throws {
          try await clock.sleep(for: tuning.autosaveDelay)
          // ...
      }
  }
  ```

  Use a generic `C: Clock` parameter instead of `any Clock<Duration>` only when a
  profiler shows the existential matters; the existential keeps the type's signature
  readable.
- **"Now"** (a timestamp, "is this older than a day", a date to format): take
  `now: @Sendable () -> Date` defaulting to `{ Date.now }`, or accept the `Date` as an
  argument to the method that needs it. A pure function over a value type
  should take the `Date` as an argument; a long-lived view model takes the closure.
  Never call `Date()` or `Date.now` inside a branch.
- **Calendar and time zone** travel with "now": take a `Calendar` (which carries its
  `timeZone`) rather than reading `Calendar.current`, because "today" depends on it.
- **Tests:** pass a fixed date, `{ Date(timeIntervalSince1970: 1_700_000_000) }`, and a
  `Calendar(identifier: .gregorian)` with an explicit `TimeZone(identifier: "UTC")`.
  For a clock, the test target defines its own manually advanced `Clock` (the standard
  library ships none); keep it in `Tests/TownsfolkCoreTests/`, never in `Sources/`. Passing
  a zero `Duration` through `Tuning` is often enough and needs no fake clock at all.

## Inject locale

- Anything that formats or compares human-facing text — a number, a date, a
  case-insensitive sort, a plural — takes a `Locale` (default `.current` at the
  composition root or the initializer's default argument), and passes it on explicitly:
  `value.formatted(.number.locale(locale))`, `date.formatted(.dateTime.locale(locale))`.
- Keep the user-visible *wording* in Core where the coverage floor sees it, as a
  `LocalizedStringResource` like `SettingsViewModel.nameError`; the view only renders it.
  How one is declared and kept in the String Catalog is `localizing-the-app`.
- **Tests:** `Locale(identifier: "en_US_POSIX")` for a stable expected string, plus a
  second locale (`"de_DE"`, `"ja_JP"`) when the behavior under test *is* the
  localization.

## Inject randomness

- Take the generator as a parameter: a method that draws takes
  `using generator: inout some RandomNumberGenerator`, mirroring the standard library's
  own `shuffled(using:)` and `Int.random(in:using:)`. A `@MainActor` view model that owns
  one stores it as `private var generator: any RandomNumberGenerator`, defaulting to
  `SystemRandomNumberGenerator()`; the actor isolation already keeps it race-free.
- **Tests:** Swift's standard library has no seeded generator, so the test target
  defines one — a few lines of SplitMix64 conforming to `RandomNumberGenerator` — and
  asserts on the exact sequence a given seed produces. It lives in
  `Tests/TownsfolkCoreTests/`; shipping code never needs it.

## One `Tuning` type

- Every number someone might want to tweak — a delay, a threshold, a limit, a retry
  count — lives in one `public struct Tuning: Sendable, Equatable` in `TownsfolkCore` with a
  `` static let `default` `` (the backticks are required: `default` is a keyword), never
  as a literal scattered through method bodies.
- Types take a `Tuning` in their initializer (defaulting to `.default`), so a test
  passes a tiny delay or a low limit to reach a boundary quickly.
- Durations are `Duration`, not `TimeInterval`; counts are `Int`. A doc comment on each
  property says why it has that value.
- A domain *invariant* is not a tunable: a range that defines what a value type means
  is a parameter or a constant of that type, validated by its throwing initializer, not
  a `Tuning` entry.
  The test: would changing it be a product tweak (Tuning) or change what the type means
  (a parameter or a constant)?
- Split `Tuning` into nested structs by feature once it grows past a screenful; keep it
  one root type so there is one place to look.

## Action-shaped view models

- A view model is `@MainActor @Observable public final class`, importing `Observation`
  and, for its wording, `Foundation` (`SettingsViewModel`). It
  is the one place a view reads state from and sends intent to.
- State is `public private(set) var`; derived state is a computed property
  (`canPost`, `nameError`). A view never mutates state directly.
- Entry points are **actions named for what the user did or the app saw**:
  `postSubmitted()`, `nameSubmitted(_:)`, `speedChosen(_:)` — not setters, and not a
  generic `send(_ action:)` reducer. Each action is a method a test can call and then
  assert on the resulting state.
- An action that waits is `async` and the view calls it from `.task` or `Task { }`;
  the view model does not spawn untracked tasks from an initializer. Construction has
  no side effects (see `SettingsViewModel.init`, which reads its settings and writes
  nothing).
- Domain rules live in value types (`YourPostText`, `DisplayName`) that the view model holds and delegates
  to; the view model translates between them and what the view shows.

## Deliberately not adopted

Each row is a pattern an implementer may reach for out of habit. The template's
reasoning lives in `README.md` › Design Philosophy.

| Pattern | Why not | Reasoning |
|---|---|---|
| A third-party architecture framework (TCA, a Redux store, an MVVM kit) | Zero dependencies; `@Observable` plus actions already gives testable state | `README.md` › "Why zero dependencies?" |
| A generic `send(_ action:)` reducer on every view model | Methods are discoverable, typed, and testable one at a time | this skill |
| Use-case / interactor classes, presenters, per-layer DTOs | The view model's action *is* the use case; copies between layers add no consumer | `README.md` › "Why the Core/UI/Platform split…" |
| A repository or protocol per type "for testability" | A port exists only where an OS or I/O boundary does; a pure rule is tested directly | `docs/architecture.md` › Ports and adapters |
| A dependency-injection container or service locator | `App/` is the composition root; initializer parameters with defaults are enough | `README.md` › "Why the Core/UI/Platform split…" |
| Coordinators / routers as separate objects | SwiftUI's own navigation state, owned by a view model, suffices at this size | this skill |
| An event bus or `NotificationCenter` between Core types | Direct calls; an OS notification is observed through a port instead | `WindowPresenceProviding`'s doc comment |

Adopting one of these is the owner's decision, recorded in `docs/architecture.md` ›
Townsfolk on these layers with the problem the current shape cannot solve.
**REQUIRED:** `updating-docs`.
