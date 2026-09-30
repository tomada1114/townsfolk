# TCC-gated APIs

This file records what this repository decided about TCC-gated APIs and why. What an
API returns is Apple's to document; each row links the page, checked 2026-09-28. The
decisions below all rest on one observed property: **TCC never tells the app anything**.
A denied call does not throw; it returns nothing, or nothing happens. A grant does not
arrive as a notification; the app finds out by asking again.

## Which grant, and how it is refused

| Capability | Grant | How a refusal looks in code |
|---|---|---|
| [`CGEvent.tapCreate`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) | Input Monitoring (plus Accessibility to modify events) | returns `nil` — the same as a malformed argument |
| [`AXObserver`](https://developer.apple.com/documentation/applicationservices/axobserver), [`AXUIElement`](https://developer.apple.com/documentation/applicationservices/axuielement_h) functions | Accessibility | `AXError.apiDisabled` or `.notImplemented` |
| [`ScreenCaptureKit`](https://developer.apple.com/documentation/screencapturekit), `CGWindowListCreateImage` | Screen Recording | empty or blank content, not an error |
| `RegisterEventHotKey`, `NSWorkspace` | none | — |

None of these three has an `INFOPLIST_KEY_NS…UsageDescription` — no such key exists for
them (`docs/distribution.md` › "The usage-description keys"). Other TCC-gated APIs do, and
a missing key there is worse than a denial: the system terminates the process at the
moment of the call. Add the key when the API has one.

## Checking and prompting

```swift
@preconcurrency import ApplicationServices
import MyAppCore

/// Answers whether this process holds the Accessibility grant, and asks for it.
public struct SystemAccessibilityTrust: AccessibilityTrustChecking {
    /// The key `AXIsProcessTrustedWithOptions` reads to decide whether to prompt.
    private static let promptOption = kAXTrustedCheckOptionPrompt.takeUnretainedValue()

    /// Whether the grant is held right now — cheap, and the only honest way to know,
    /// since macOS reports a new grant through no callback at all.
    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public init() {
        // Stateless: the OS holds the answer.
    }

    /// Shows the system's "open Privacy & Security" prompt.
    ///
    /// The return value is deliberately dropped: it answers for the moment *before*
    /// the user reacted, so a caller that believed it would report "not trusted"
    /// forever. Ask `isTrusted` again later instead.
    public func requestTrust() {
        _ = AXIsProcessTrustedWithOptions([Self.promptOption: true] as CFDictionary)
    }
}
```

The check without a side effect and the check that prompts are Apple's
[`AXIsProcessTrusted`](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted) and
[`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
with [`kAXTrustedCheckOptionPrompt`](https://developer.apple.com/documentation/applicationservices/kaxtrustedcheckoptionprompt)
(checked 2026-09-28). The decision here: this repository treats the prompt as spendable once
per app per user, because in practice macOS does not show it again — so it is never
spent at launch, before the user knows what the app is for. Prompt when the user first
reaches for the feature that needs it.

`@preconcurrency import` is there for `kAXTrustedCheckOptionPrompt`, which Swift 6 sees
as shared mutable state — see `c-callbacks.md` › "`@preconcurrency import`".

## The grant arrives with no callback

The user leaves the app, opens System Settings › Privacy & Security, flips a toggle, and
comes back. Nothing in the app was called. There are two workable answers, in this order:

1. **Re-check on activation.** The app becoming active is the one signal that correlates
   with the user having just done something in System Settings. In SwiftUI, that is
   `.onChange(of: scenePhase)` becoming `.active` — the same seam `FrontmostAppViewModel`
   already refreshes on.
2. **Poll, but only while blocked and only while visible.** A one-second timer running
   solely in the blocked state costs nothing and closes the case where the user grants the
   permission without leaving the app. Stop it the moment the answer turns true.

Some APIs also need re-arming after the grant, not just re-checking: an event tap created
while untrusted was never created at all, so the app must call `start()` again once
`isTrusted` turns true. Model that as "the gate turned ready → install", not as a retry
loop.

## Degraded, not broken

A missing grant is a state the user can leave, so the app stays usable and says what is
missing and what to do:

```swift
@MainActor
@Observable
public final class AccessibilityGateViewModel {
    public enum State: Equatable, Sendable {
        case unknown
        case blocked
        case ready
    }

    public private(set) var state: State = .unknown

    /// macOS shows its prompt once per app regardless, so asking again only trains the
    /// user to ignore it.
    public private(set) var hasPrompted = false

    private let trust: any AccessibilityTrustChecking

    public init(trust: any AccessibilityTrustChecking) {
        self.trust = trust
    }

    /// Call at launch and every time the app becomes active: the user grants the
    /// permission in another process, and returning to the foreground is the only
    /// signal this app gets.
    public func refresh() {
        state = trust.isTrusted ? .ready : .blocked
    }

    public func promptIfNeeded() {
        guard state == .blocked, !hasPrompted else {
            return
        }
        hasPrompted = true
        trust.requestTrust()
    }
}
```

That is the whole point of the port: `state`, `hasPrompted`, "prompt at most once", "what
the blocked screen says" are all decisions, they are all in `MyAppCore`, and a Core test
drives them with a fake whose `isTrusted` the test sets. `.claude/rules/testing.md` ›
"Fakes, not mocks" has the fake's shape; `FakeFrontmostAppProvider` in
`Tests/MyAppTestSupport` is the one to copy, and "One Contract Suite per Port" holds it
and the adapter to the same promises.

Everything else about the blocked state is product design, not code: name the permission
the way System Settings names it, and offer a button that opens the right pane rather
than prose describing where to click.

## The grant your own rebuild destroys

A Debug build is signed ad hoc (`CODE_SIGN_IDENTITY = -` in `Config/Debug.xcconfig`),
which gives it no stable identity — macOS tells one such build from the next by its code
hash, so **every rebuild is a new app** and the grant you gave a minute ago no longer
applies. Left alone, that turns every iteration on a TCC-gated feature into a trip
through System Settings, and it is the reason an agent debugging such a feature concludes
the code is broken when it is not.

The fix is a real signing identity for Debug only, kept out of the repository:
`Config/Debug.xcconfig` ends with `#include? "Local.xcconfig"`, and
`Config/Local.xcconfig` — gitignored, and refused by the commit-time guard
(`scripts/guard/paths.sh`) — sets `DEVELOPMENT_TEAM` and a generic
`CODE_SIGN_IDENTITY = Apple Development`. `docs/getting-started.md` › "Keeping Permission
Grants Across Rebuilds" is the recipe, including the two details that cost the most time
if guessed. Creating that file is explicitly *not* one of the signing changes
`AGENTS.md` › "Security and human approval" reserves for a human: it is local, it is
never committed, and it changes nobody else's build.

After switching a build between ad-hoc and real signing, macOS is holding decisions for
what it considers a different app, and System Settings shows a stale entry that grants
nothing. Clear them for this app — and only this app, whose bundle identifier is read
from `project.yml` — with `just reset-permissions`. Then `just run` and `just logs`
(`running-the-app`) to watch what the freshly prompted app actually does.

## What can be tested, and where

| Question | Where it is answered |
|---|---|
| What the app shows while blocked, when it prompts, what a press means | `Tests/MyAppCoreTests` against a fake — CI-run, inside the 80% floor |
| Does the adapter translate what the OS really returns | `Tests/MyAppPlatformTests`, `.requiresLocalMachine`, `just test-local` |
| Does the grant flow work end to end | A human, by hand. Nothing automates it |

CI cannot cross the second row: a runner has no logged-in GUI session and cannot be
granted Accessibility, Input Monitoring, or Screen Recording, so those tests are reported
as **skipped** under `just test` and in CI rather than being absent. That is deliberate —
a skip is visible where a missing test is not — and it makes the third row procedural:
a change under `Sources/MyAppPlatform/` is expected to come with `just test-local` output
in the pull request, and review is what notices when it does not (`AGENTS.md` ›
"Enforcement layers").

The consequence for design is the one this whole skill keeps returning to: **anything
behind a grant that a gate cannot reach must not be where the decisions live.** Push the
decision into Core behind the port, leave the adapter with nothing but translation, and
the part no machine can verify shrinks to the part no machine could have verified anyway.

When a local-machine test needs a grant, unwrap through
`LocalMachineTests.require(_:requires:grant:)` with `grant: true`: the OS answers nothing
rather than failing, so a bare `nil` reads as a broken adapter, and that helper's message
names the permission and where to grant it instead.
