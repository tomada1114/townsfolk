# ADR-0001: One window, and closing it quits

- **Status:** Accepted 2026-09-30
- **Amended:** 2026-09-30 — Open question settled: the window's size and position are
  restored across launches with no extra code. SwiftUI autosaves the `Window` scene's
  frame in the app's defaults under its id (`NSWindow Frame town`); moved and resized to
  440 × 590 pt, quit with ⌘Q, and launched again, the window reopened at the same frame
  (#7).
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

The template ships a regular windowed app: a `WindowGroup` holding `ContentView`, a Dock
tile, and a launch test that waits for a window (`docs/architecture.md` › Where new code
goes; `starting-an-app`'s `references/app-shapes.md`). Townsfolk's requirements leave
one shape inside that:

- one window at the edge of the screen, titled with the town's name, plus the standard
  Settings window (`docs/product/ux-flows.md` §1–§2);
- closing the window quits the app, because there is nothing to keep running
  (`docs/product/requirements.md` §3.7);
- no menu-bar agent and no running while the window is closed or hidden (the non-goal
  "Running while out of sight"), and no always-on-top, every-Space, or launch at login
  (the non-goal "Window extras").

## Decision drivers

- The requirements above.
- The launch guarantee the template already tests: a window appears.
- The least code in `App/`, which is wiring only.

## Considered options

1. **One `Window` scene plus the `Settings` scene** — SwiftUI's scene for a single,
   unique window.
2. **Keep the template's `WindowGroup`**, with quitting added through an app delegate.
3. **A menu-bar agent** (`MenuBarExtra`, `LSUIElement`).

## Decision

`App/TownsfolkApp.swift` declares one `Window` scene holding the town window's root view,
and one `Settings` scene. The window opens at 380 × 680 pt (`.defaultSize` on the scene)
with a minimum of 320 × 440 pt (the root view's `.frame(minWidth:minHeight:)`), per
ADR-0008. Its title is the town's name, and "Townsfolk" until a town exists. The app
keeps its Dock tile and the standard main menu; the Town menu is a `Commands` group on
the scene (ux-flows S8). `project.yml` gains no shape key.

`Window` beat `WindowGroup` because a window group lets people open more windows and
keeps the app running after its last one closes — both contrary to the requirements —
while a `Window` that is the app's primary scene quits the app when it closes, with no
delegate. The menu-bar agent is a non-goal.

## Consequences

### Positive

- Quitting on close comes from the scene: no `NSApplicationDelegateAdaptor`, and no code
  in `TownsfolkPlatform` for it.
- No File › New Window item exists to contradict "one window".
- `LaunchUITests` keeps asserting what it asserts today, that a window appears.

### Negative

- The window cannot be reopened without relaunching, since closing it quits. That is
  the intended behavior (requirements §3.7).
- If the town stops too often because work windows cover it, always-on-top and
  every-Space are the first things to revisit (the non-goal "Window extras"); either one
  amends this ADR.

### Follow-ups

- Replace the template's `WindowGroup` and example `ContentView` with the town window
  and the Settings scene — an issue in the backlog.

## Open questions

- None.

## Sources

- <https://developer.apple.com/documentation/swiftui/window> — "A scene that presents
  its content in a single, unique window."; macOS 13.0+; "If your app uses a single
  window as its primary scene, the app quits when the window closes. This behavior
  differs from an app that uses a `WindowGroup` as its primary scene, where the app
  continues to run even after closing all of its windows." — checked 2026-09-30
- <https://developer.apple.com/documentation/swiftui/windowgroup> — "people can open
  more than one window from the group simultaneously"; a window opened "by choosing
  File > New Window" — checked 2026-09-30

## Related

- [ADR-0006](0006-window-presence-port.md) — whether the town runs depends on this window
  being visible.
- [ADR-0008](0008-design-lock.md) — the window's sizes.
