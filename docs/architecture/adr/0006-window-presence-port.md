# ADR-0006: When the town runs — window presence behind a Core port

- **Status:** Accepted 2026-09-30
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

The town runs while its window is visible on screen — including while another app is
active and the window sits beside the work — and stops when the window is not visible
(minimized, on another Space, completely covered, the screen locked, the display asleep),
when the Mac sleeps, and when the app quits. With "Keep the town moving while I use other
apps" off, it runs only while its window is the active one. Town time stops with it, and
the pause's length sets the catch-up (requirements §3.7, §3.10).

Whether a window is visible, whether the app is active, and whether the Mac is going to
sleep are AppKit and `NSWorkspace` facts, and Core may not import AppKit.

## Decision drivers

- "Running" — visible, and active or allowed in other apps, and awake, and the model
  available — is product behavior, so it belongs in Core under the floor.
- Only translation in the adapter (`docs/architecture.md` › Ports and adapters).
- Pause arithmetic a test can drive: a pause runs between two presence changes.

## Considered options

1. **A port that reports presence as a stream of values, with Core deciding.**
2. **Let the views drive it**, with `TownsfolkUI` watching SwiftUI's scene phase and
   calling view-model actions. The rule would sit in view code outside the floor, and
   scene phase would still have to be shown to cover occlusion and sleep.
3. **Run on a timer regardless** — the non-goal "Running while out of sight".

## Decision

Core declares a `Sendable` port, provisionally `WindowPresenceProviding`, whose adapter
reports a stream of presence values: whether the town window is visible (not fully
occluded), whether the app is active, and whether the Mac is awake. The adapter in
`TownsfolkPlatform` observes the window's occlusion
(`NSWindow.didChangeOcclusionStateNotification`), the app becoming active and inactive,
and `NSWorkspace`'s sleep and wake notifications, and decides nothing. Core's engine
combines the latest presence with the setting and the model's availability, stops town
time when the town stops, and records when it last ran (ADR-0004), so the next start
measures the pause. The fake in `TownsfolkTestSupport` emits scripted presence, and one
contract suite runs against both.

With the setting off and the window still visible, the window shows that the town is
resting instead (ux-flows S1).

## Consequences

### Positive

- Every stop, start, and catch-up size is decided in Core and tested with a fake stream
  and a fake clock.
- The adapter is observation only, like the template's `WorkspaceFrontmostAppProvider`,
  which this port replaces as the worked example once the sample is removed.

### Negative

- Occlusion is coarse: a window with any part visible counts as visible, so a sliver
  showing from under another window keeps the town running.
- The adapter has to find the town window's `NSWindow`, which a SwiftUI `Window` scene
  does not hand over directly.

### Follow-ups

- The port, the adapter, the fake, and the contract suite — an issue in the backlog,
  whose pull request carries `just test-local` output.

## Open questions

- Unverified: whether occlusion alone reports a locked screen and a sleeping display as
  not visible, or the adapter also needs `NSWorkspace`'s screen-sleep and session
  notifications. The adapter's local-machine test settles it.
- Unverified: how the adapter reaches the `Window` scene's `NSWindow` — by its
  identifier, or through a view-side hook that the composition root passes along.
  Settled by the same issue.

## Sources

- <https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property>
  — "The occlusion state of the window."; macOS 10.9+ — checked 2026-09-30
- <https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification>
  — "A notification that the window object's occlusion state changed."; macOS 10.9+ —
  checked 2026-09-30
- <https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct/visible>
  — "If set, at least part of the window is visible; if not set, the entire window is
  occluded." — checked 2026-09-30

## Related

- [ADR-0001](0001-app-shape.md) — the one window this watches.
- [ADR-0004](0004-persistence-sqlite-in-core.md) — where "last ran" is kept.
- [ADR-0005](0005-foundation-models-in-core.md) — the availability "running" also needs.
