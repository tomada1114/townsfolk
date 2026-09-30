---
paths:
  - "Packages/**/*.swift"
  - "App/**/*.swift"
---

## Design

- One logical concern per file. SwiftLint enforces its default limits under `strict: true`
  (warnings fail): a file over 400 lines (`file_length`), a function body over 50 lines
  (`function_body_length`), or more than 5 parameters (`function_parameter_count`) fails
  `just lint` — group related parameters in a struct long before that
- Value types first: reach for `struct`/`enum`; use `class` only for identity or reference semantics
- `TownsfolkCore` must never import SwiftUI, AppKit, UIKit, Cocoa, ApplicationServices, Carbon,
  or ServiceManagement — it stays platform-agnostic (enforced by `.swiftlint.yml`'s
  `no_ui_import_in_core` and `ArchitectureBoundaryTests`). `os`/`OSLog` are *not* on that
  list: logging is neither a UI nor an OS-integration framework, so Core imports it
  directly (see Logging below)
- OS integration goes in `TownsfolkPlatform`, as an adapter behind a `Sendable` port Core
  declares: value types in and out, translation only, no branching domain logic (that
  belongs in Core, where the coverage floor sees it)
- Views in `TownsfolkUI` stay thin: no business logic, delegate everything to Core view models
- `TownsfolkUI` and `TownsfolkPlatform` are siblings and never import each other; `App/` is the
  composition root that hands a `TownsfolkPlatform` adapter to a Core view model
- How Core logic is shaped (injected time, locale, and randomness; one `Tuning`; action-shaped
  view models) is the `designing-core-logic` skill
- `///` doc comments on all public API; document *why*, not what the signature already says
- A `switch` over an enum `TownsfolkCore` declares lists every case and has no `default:`
  (group cases with `case .a, .b:` instead), so adding a case is a compile error at each
  switch that must decide about it rather than a silent fall into `default`. An enum the
  SDK owns (`AXError`, an imported C enum) is the exception: map the cases you know and
  send the rest to `default:` or `@unknown default:` (the `designing-errors` skill). No
  SwiftLint rule enforces this; review does

## Access Control

- Narrowest first: `private`, then internal (the default, unwritten), then `package`,
  then `public`
- `package` (Swift 5.9+; `Packages/TownsfolkKit/Package.swift` is tools-version 6.2) is for
  a declaration another target *in* `Packages/TownsfolkKit` needs — a sibling module or a
  test target — that is not app API. It replaces `@testable import` (`testing.md` ›
  Framework and Structure). `App/` is an Xcode target outside the package and cannot
  see it: whatever `App/` calls is `public`
- `package` does not loosen the module boundaries: `TownsfolkUI` and `TownsfolkPlatform` still
  never import each other, and a view still does not mutate Core state directly

## Constants

- A view's layout numbers (spacing, font size, minimum window size): a `private enum
  Layout` at the top of that view's file — `ContentView.swift` is the worked example; a
  test's timeouts likewise (`LaunchTests.swift`'s `Timeout`)
- A number someone might tune (a delay, a threshold, a limit): Core's one `Tuning` type
  (the `designing-core-logic` skill); a domain invariant is a parameter or a `static`
  on its type (`Counter`'s default `range`), not a `Tuning` entry
- User-visible wording Core decides: a `static let` on the view model
  (`FrontmostAppViewModel.unavailableDisplayName`); the logging subsystem: `AppLog`, once
- A type holding only `static` members is a caseless `enum` (SwiftLint's
  `convenience_type`). No global `let`, and no `Constants.swift` grab bag: a constant
  lives beside the one concern that uses it

## Error Handling

- Define typed errors per module (an `enum ... : Error, Equatable` with payload), thrown with context
- NEVER `try!` or force-unwrap (`!`) in production code; `guard let`/`throws` instead
- Never swallow errors silently; if catching, handle meaningfully or rethrow
- Never use errors for control flow
- Typed vs. plain `throws`, cancellation, payload privacy, and OS-error mapping: the `designing-errors` skill

## Logging

- `os.Logger` is the only logging facility. NEVER `print`, `debugPrint`, or `NSLog`
  anywhere under `Packages/*/Sources/` or `App/`: a `.app` launched the way users launch
  it discards stdout, so those lines are lost exactly when they matter. Enforced by
  `.swiftlint.yml`'s `no_print_in_sources`; test targets are exempt
- Every logger is declared in `AppLog` (`Sources/TownsfolkCore/AppLog.swift`), never built
  inline: `subsystem` is the app's bundle identifier, spelled once as a literal there
  (`Bundle.main.bundleIdentifier` answers for the test runner under `swift test` and for
  the preview agent in a preview), and one `category` names one concern. `just logs`
  streams that subsystem; `AppLogTests` fails if it drifts from `project.yml`
- Anything user-derived carries a privacy annotation — another app's name, a window
  title, an accessibility element's label, a file path, anything typed — is `.private`.
  Only values that are safe in anyone's log, such as a state name or a count, are
  `.public`. `os.Logger` defaults interpolated strings to `.private`, so say which one
  you mean rather than relying on the default
- Level by intent: `.debug` for the development stream `just logs` shows, `.info` for a
  milestone worth keeping, `.error`/`.fault` for something that went wrong. See
  `FrontmostAppViewModel.refresh()` for the worked example

## Concurrency

- Swift 6 language mode is on: data-race safety errors are non-negotiable
- UI-facing state is `@MainActor`; keep Core types `Sendable` where they cross actors
- No `@unchecked Sendable` without a comment proving the invariant it papers over
