---
name: integrating-system-apis
description: >
  Covers calling a macOS system API from TownsfolkPlatform under Swift 6 strict concurrency:
  where the port, the adapter, the fake, and the local-machine test go; a C callback
  carrying self through a refcon with Unmanaged; MainActor.assumeIsolated versus a Task
  hop; @preconcurrency import; non-Sendable CF types; teardown order. Use when adding a
  CGEventTap, an AXObserver or other Accessibility (AXUIElement) code, a Carbon
  RegisterEventHotKey hotkey, a CFRunLoop source, or any CGEvent work; when a TCC-gated
  permission (Accessibility, Input Monitoring, Screen Recording) is involved -
  AXIsProcessTrustedWithOptions, a prompt that never calls back, a grant lost on every
  rebuild; when "sending value of non-Sendable type" or a capturing C function pointer
  blocks the build; or when tempted by @unchecked Sendable or nonisolated(unsafe).
---

# Integrating System APIs

**Owns:** calling a macOS system API from `TownsfolkPlatform` — which mechanism, how its C
callback survives Swift 6, how a TCC grant behaves, and what may be tested where.
**Does not own:** whether the app may be sandboxed at all or what shape it takes
(`starting-an-app`); the red-green loop for the Core decision the port serves (`tdd`);
running and watching the built app (`running-the-app`); changing a lint rule or the
coverage floor that pushes work into Core (`changing-gates`).

## The shape, before any OS code

Every integration is the same five pieces, and the window-presence port is one of each to
copy — `docs/architecture.md` › "Ports and adapters" is the full description:

| Piece | Where | Worked example |
|---|---|---|
| Port: a `Sendable` protocol, value types in and out | `Packages/TownsfolkKit/Sources/TownsfolkCore/` | `Presence/WindowPresenceProviding.swift` |
| Adapter: the OS framework import, translation only | `Packages/TownsfolkKit/Sources/TownsfolkPlatform/` | `WindowPresenceProvider.swift` |
| Fake: a real implementation answering from test data | `Tests/TownsfolkTestSupport/` | `FakeWindowPresenceProvider.swift` |
| Local-machine test: the adapter against the real OS | `Tests/TownsfolkPlatformTests/` | `WindowPresenceProviderTests.swift` |
| Contract: the port's promises, run against the fake and the adapter | `Tests/TownsfolkTestSupport/` | `WindowPresenceProvidingContract.swift` |

Write the port first. Its signature is where you decide what the OS type collapses into,
and an adapter written before its port almost always leaks one: `CGEvent`, `AXUIElement`,
`NSRunningApplication`, `EventHotKeyRef`, and `CFMachPort` are all non-`Sendable`, all
banned from `TownsfolkCore` by `.swiftlint.yml`'s `no_ui_import_in_core` and
`ArchitectureBoundaryTests`, and all better as a `struct` Core owns.

Put the isolation in the port too. Nearly every OS mechanism here is bound to one run
loop, so declaring the port's methods `@MainActor` states that once, instead of leaving
each adapter to justify an `assumeIsolated` of its own.

## Choosing the mechanism

Pick the cheapest mechanism that answers the question, because the cost is the grant the
user has to give and the support burden of the ones who will not.

The table is this repository's choice of mechanism; each API's behavior is Apple's, so
follow its link rather than a paraphrase here (links checked 2026-09-28).

| You need | Reach for | Grant it costs |
|---|---|---|
| A system-wide hotkey | Carbon `RegisterEventHotKey` (no current Apple reference page) | none |
| Which app is frontmost, now or on switch | [`NSWorkspace`](https://developer.apple.com/documentation/appkit/nsworkspace) | none |
| Every key press, anywhere | [`CGEvent.tapCreate`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) | Input Monitoring (Accessibility too, to modify events) |
| Another app's windows, text, or UI tree | [`AXObserver`](https://developer.apple.com/documentation/applicationservices/axobserver) / [`AXUIElement`](https://developer.apple.com/documentation/applicationservices/axuielement_h) | Accessibility |
| Window contents or a screenshot | [`ScreenCaptureKit`](https://developer.apple.com/documentation/screencapturekit) | Screen Recording |

This repository prefers the Carbon hotkey: it is deprecated, and it is still the only
hotkey API this repository has found that needs no grant — that is the trade, and it is
usually the right one. An event tap that only *listens* still needs
Input Monitoring, so a hotkey implemented as a tap costs a permission the Carbon one does
not. Accessibility and Input Monitoring are never granted to a sandboxed process, so
either of them forces the app out of the sandbox and off the Mac App Store; Screen
Recording is a grant a sandboxed app can hold (`docs/distribution.md` › "Sandboxed or
not" records this; Apple's [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), checked 2026-09-28). That decision is a human's (`starting-an-app` › "Deciding the sandbox posture").

## Three rules that never bend

1. **Only values cross an isolation boundary.** Translate the `CGEvent` or `AXUIElement`
   into the port's value type *inside* the C callback, then hop with the value. Carrying
   the OS object across is a compile error under Swift 6 (`sending 'event' risks causing
   data races`), and it would be a bug even if it compiled — the OS may recycle the
   object the moment the callback returns.
2. **A refcon is a manual retain, and it is yours to release.** `Unmanaged.passRetained`
   on the way in, exactly one `release()` on every way out, including each early `throw`.
   The retained reference also means `deinit` never runs while the tap is installed, so
   teardown is an explicit `stop()`, never a deallocation.
3. **Tear down in the reverse of setup, before anything is freed.** Disable, invalidate,
   remove the run-loop source, *then* release the refcon. A source still in the run loop
   after its owner is gone is a callback into freed memory.

## Never reach for `@unchecked Sendable` or `nonisolated(unsafe)`

They are how a system-API integration goes wrong: the build turns green, the data race
stays, and the reason it was safe is written nowhere. When the compiler objects, one of
these is the actual fix — in this order:

| The compiler says | The fix |
|---|---|
| `sending '…' risks causing data races` | Map to a value type before the hop; send the value. |
| a C function pointer cannot capture context | Make the callback a file-scope `let`, pass state through the refcon. |
| `reference to var '…' is not concurrency-safe` (a C global such as `kAXTrustedCheckOptionPrompt`) | `@preconcurrency import` that framework — see the reference for when that is honest. |
| a type must be `Sendable` to be handed over once | `sending` on the parameter, which moves it instead of sharing it. |
| a type must be `Sendable` to be *shared* | It must not be shared. Pin it to one actor and expose values. |

`.claude/rules/swift.md` › Concurrency allows `@unchecked Sendable` only with a comment
proving the invariant. In an adapter that comment is nearly always unwritable, because
the invariant would be a claim about a system framework's threading that Apple does not
document.

## The references

- **REQUIRED:** [references/c-callbacks.md](references/c-callbacks.md) when writing an
  adapter's callback — the compile-proven patterns:
  the `CGEventTap` adapter end to end (refcon, re-enable after
  `kCGEventTapDisabledByTimeout`, teardown), `AXObserver` and Carbon hotkey variants,
  when `MainActor.assumeIsolated` is a fact and when it is a lie, `@preconcurrency
  import`, non-`Sendable` CF types, and the SwiftLint rules that reject the shape most
  sample code on the internet uses.
- **REQUIRED:** [references/tcc-permissions.md](references/tcc-permissions.md) when the
  API is TCC-gated — checking and prompting
  with `AXIsProcessTrustedWithOptions`, why a grant arrives with no callback and what to
  do about it, degraded-state UX, the `Info.plist` usage keys, the rebuild-loses-the-grant
  loop and its fix, and what can and cannot be tested where.

## Before you call it done

- [ ] The port takes and returns Core value types only, and `TownsfolkCore` imports no OS
      framework (`just test` runs `ArchitectureBoundaryTests`; `just lint` runs
      `no_ui_import_in_core`).
- [ ] Every `passRetained` has exactly one `release()` on every exit path, including
      throws.
- [ ] There is an explicit teardown method, it is idempotent, and it runs before the
      owner can go away.
- [ ] Every decision — what to show while ungranted, when to prompt, what a press means —
      is in Core behind the port, with a Core test against a fake.
- [ ] The adapter has a `.requiresLocalMachine` test in `Tests/TownsfolkPlatformTests`, and
      the pull request carries its `just test-local` output. No gate produces it
      (`AGENTS.md` › "Enforcement layers").
- [ ] The port's fake and its contract function live in `Tests/TownsfolkTestSupport`, and
      the contract runs against both the fake (`TownsfolkCoreTests`) and the adapter
      (`TownsfolkPlatformTests`).
- [ ] No new `@unchecked Sendable`, `nonisolated(unsafe)`, or `try!`.
