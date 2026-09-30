# C callbacks under Swift 6

Every snippet below was compiled in a clone of this repository, as files under
`Packages/TownsfolkKit/Sources/`, with `swift build` (Swift 6 language mode, every warning an
error — `Package.swift`'s `strictSettings`), `swiftlint --strict`, and
`swiftformat --lint`. They are the shape that passes all three, which is not the shape
most sample code on the internet uses. What each API does is Apple's to document and is
linked, not restated (links checked 2026-09-28); what is written out here is the shape
this repository chose and why.

## The port, in Core

The adapter is written against this, and writing it first is what stops the OS type
leaking. Both methods are `@MainActor` because every mechanism behind them is
run-loop-bound; saying so here means no adapter has to argue for it.

```swift
/// A key press, reduced to the value Core reasons about.
public struct KeyPress: Equatable, Sendable {
    public let keyCode: UInt16
    /// The modifier flags, as the raw value of `CGEventFlags`.
    public let modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// `notTrusted` is the one the OS does not tell you about: `CGEvent.tapCreate` answers
/// `nil` for a missing Input Monitoring grant exactly as it does for a bad argument.
public enum KeyPressObservingError: Error, Equatable {
    case notTrusted
    case tapCreationFailed
}

public protocol KeyPressObserving: Sendable {
    @MainActor
    func start(reporting report: @escaping @MainActor (KeyPress) -> Void) throws

    @MainActor
    func stop()
}
```

## The event tap, end to end

```swift
import CoreGraphics
import TownsfolkCore

/// `@convention(c)` gives the callback no captured context, so everything it needs
/// arrives through `refcon` — and everything it hands on must already be a value,
/// because the `CGEvent` itself may not cross an isolation boundary.
///
/// It runs on the thread whose run loop the tap's source was added to. `start()` adds
/// it to `CFRunLoopGetMain()`, which is what makes `MainActor.assumeIsolated` below a
/// statement of fact rather than a wish.
private let keyPressTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let tap = Unmanaged<KeyPressEventTap>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // The system switches a tap off when its callback is too slow, and when the
        // user does something the OS treats as a reason to. Neither is an error and
        // neither arrives twice: re-enable, or the app goes deaf for the rest of its run.
        MainActor.assumeIsolated { tap.reEnable() }

    case .keyDown:
        let press = KeyPress(
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: event.flags.rawValue,
        )
        MainActor.assumeIsolated { tap.report(press) }

    default:
        break
    }
    // Listen-only: the event is handed back untouched. A tap that filters returns nil
    // to swallow it instead.
    return Unmanaged.passUnretained(event)
}

/// A `CGEventTap` adapter for ``TownsfolkCore/KeyPressObserving``.
@MainActor
public final class KeyPressEventTap: KeyPressObserving {
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callbackContext: UnsafeMutableRawPointer?
    private var reportPress: (@MainActor (KeyPress) -> Void)?

    public init() {
        // Nothing is installed until start(): a tap is a resource, not a constructor.
    }

    /// Installs the tap. Requires the Input Monitoring grant; without it
    /// `CGEvent.tapCreate` simply answers `nil`.
    public func start(reporting report: @escaping @MainActor (KeyPress) -> Void) throws {
        guard machPort == nil else {
            return
        }
        // passRetained, balanced by exactly one release on every path out: the OS holds
        // this pointer, and ARC cannot see through it. The price is that `self` is kept
        // alive while the tap is installed, so `deinit` is never the teardown hook —
        // `stop()` is.
        let context = Unmanaged.passRetained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: keyPressTapCallback,
            userInfo: context,
        ) else {
            Unmanaged<KeyPressEventTap>.fromOpaque(context).release()
            throw KeyPressObservingError.notTrusted
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        machPort = port
        runLoopSource = source
        callbackContext = context
        reportPress = report
    }

    /// Disable, invalidate, remove the source, then release the retained context last —
    /// the one order that never leaves a live callback pointing at freed memory.
    public func stop() {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        machPort = nil
        runLoopSource = nil
        reportPress = nil
        if let context = callbackContext {
            Unmanaged<KeyPressEventTap>.fromOpaque(context).release()
            callbackContext = nil
        }
    }

    func reEnable() {
        guard let machPort else {
            return
        }
        CGEvent.tapEnable(tap: machPort, enable: true)
    }

    func report(_ press: KeyPress) {
        reportPress?(press)
    }
}
```

Three things in there are the whole lesson.

**The refcon round-trip.** What each call does is [`Unmanaged`](https://developer.apple.com/documentation/swift/unmanaged)'s
documentation (checked 2026-09-28). The decision is `passRetained` in, `takeUnretainedValue()` in the
callback, one `release()` out. Count the paths out
of `start()`: the `tapCreate` failure releases before throwing, and `stop()` releases on
success. Miss one and the adapter leaks forever — and because the object is retained, no
`deinit` will ever fire to tell you.

`passUnretained` is the alternative, and it is only safe when the owner's lifetime is
structurally guaranteed to outlive the tap (an `App/`-level singleton, say). Prefer
`passRetained`: the leak it risks is visible in Instruments, while the dangling pointer
the other risks is a crash in someone else's process.

**The re-enable.** [`tapDisabledByTimeout`](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout)
and [`tapDisabledByUserInput`](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbyuserinput) (checked 2026-09-28)
arrive as event *types* through the same callback, not as errors, and an app that ignores
them silently stops receiving anything. This repository re-enables on both —
and if timeouts repeat, the real fix is that the callback does too much: translate and
hop, never work.

**The teardown order.** Disable the tap first so no new callback starts; invalidate the
Mach port; remove the source from the run loop; release the refcon last, because the
callback that may still be unwinding reads through it. `deinit` cannot do this — the
refcon retain keeps the object alive — so `stop()` is called from wherever the feature is
switched off, and it is written to be safe to call twice.

## When `MainActor.assumeIsolated` is a fact, and when it is a lie

[`MainActor.assumeIsolated`](https://developer.apple.com/documentation/swift/mainactor/assumeisolated(_:file:line:)) traps when
the caller is not already on the main actor (checked 2026-09-28). It is legitimate here for one concrete reason: the callback runs on the thread
whose run loop owns the source, and `start()` added that source to `CFRunLoopGetMain()`.
Change that line to a source on a private thread and every `assumeIsolated` in the file
becomes a crash waiting for the first event.

So the rule is narrow: **assume only what the setup code in the same file guarantees.**

| Situation | Use |
|---|---|
| Source added to `CFRunLoopGetMain()`, callback does main-actor work | `MainActor.assumeIsolated { … }` |
| Source on a private thread, or the thread is not knowable | `Task { @MainActor in … }`, with a value captured |
| The callback must return something to the OS (a filtered `CGEvent`) | Neither — decide synchronously; a `Task` runs after the return |

`Task { @MainActor in … }` is the honest hop, and it is not free: the work happens later,
which for an event tap means after the event has already been delivered. For a
run-loop-bound callback that only reports, `assumeIsolated` is both correct and simpler.

Either way the value rule holds. Both of these are rejected by the compiler, with
`error: sending 'event' risks causing data races`:

```swift
MainActor.assumeIsolated { tap.inspect(event) }   // ✗ CGEvent is not Sendable
Task { @MainActor in tap.inspect(event) }         // ✗ same
```

Build the `KeyPress` first, then hop with it.

## `AXObserver`: same shape, different teardown

The API is [`AXObserver`](https://developer.apple.com/documentation/applicationservices/axobserver) (checked 2026-09-28).

```swift
private let focusedWindowCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else {
        return
    }
    let watcher = Unmanaged<FocusedWindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated { watcher.report(name) }
}

public func start(watching pid: pid_t) throws {
    var created: AXObserver?
    guard AXObserverCreate(pid, focusedWindowCallback, &created) == .success,
          let createdObserver = created
    else {
        throw KeyPressObservingError.tapCreationFailed
    }
    let element = AXUIElementCreateApplication(pid)
    let context = Unmanaged.passRetained(self).toOpaque()
    let added = AXObserverAddNotification(
        createdObserver,
        element,
        kAXFocusedWindowChangedNotification as CFString,
        context,
    )
    guard added == .success else {
        Unmanaged<FocusedWindowWatcher>.fromOpaque(context).release()
        throw KeyPressObservingError.notTrusted
    }
    CFRunLoopAddSource(
        CFRunLoopGetMain(),
        AXObserverGetRunLoopSource(createdObserver),
        .defaultMode,
    )
    observer = createdObserver
    observedElement = element
    callbackContext = context
}
```

Teardown needs the element you registered with, so store it: `AXObserverRemoveNotification`
takes the same `(observer, element, notification)` triple, and it goes *before*
`CFRunLoopRemoveSource`, which goes before the `release()`. `AXUIElement` and `AXObserver`
are both non-`Sendable`; they live in the `@MainActor` class and never leave it. Note also
what the API returns on a missing grant: `AXError.apiDisabled` or `.notImplemented`,
never an exception.

## Carbon hotkey: no run-loop source at all

```swift
private let hotkeyHandler: EventHandlerUPP = { _, event, refcon in
    guard let event, let refcon else {
        return OSStatus(eventNotHandledErr)
    }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier,
    )
    guard status == noErr else {
        return status
    }
    let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(refcon).takeUnretainedValue()
    let pressed = identifier.id
    MainActor.assumeIsolated { registrar.fire(pressed) }
    return noErr
}
```

`InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &spec, context, &installed)`
then `RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &registered)`,
with the refcon released on either failure. Teardown is `UnregisterEventHotKey` then
`RemoveEventHandler` then `release()`. There is no run-loop source to add or remove —
the application event target dispatches on the main thread, which is this callback's
licence for `assumeIsolated`.

Two Carbon-specific traps: `modifiers` is a Carbon mask (`cmdKey`, `optionKey`, `shiftKey`,
`controlKey`), not `CGEventFlags`, and an `EventHotKeyID`'s `signature` is a four-character
`OSType` you pick once (`private static let signature: OSType = 0x4D59_4150`) — writing it
as `OSType(0x4D59_4150)` trips SwiftLint's `no_magic_numbers`, while the typed `let` does
not.

## `@preconcurrency import`, and when it is honest

Some C globals import as `var` and Swift 6 rejects reading them:

```
error: reference to var 'kAXTrustedCheckOptionPrompt' is not concurrency-safe
because it involves shared mutable state
```

`@preconcurrency import ApplicationServices` silences it for the whole file
([SE-0337](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0337-support-incremental-migration-to-concurrency-checking.md), checked 2026-09-28). That is
legitimate exactly when the declaration is immutable in fact and only `var` in the
header — a `CFString` constant the framework initializes once at load, like this one. It
is *not* a licence to reach for the attribute whenever a framework complains: it downgrades
every concurrency diagnostic from that import in that file, so keep such a file small and
say in a comment which declaration forced it.

Do not replace it with `nonisolated(unsafe)` on a local copy: that asserts the same thing
with less scope and no record of which framework it was about.

## Non-`Sendable` CF types

`CGEvent`, `AXUIElement`, `AXObserver`, `CFMachPort`, and `CFRunLoopSource` are all
non-`Sendable`, as this repository's toolchain confirms — each of them in a
`Task.detached` is a compile error. The order of preference:

1. **Do not move it.** Keep it in the `@MainActor` adapter and expose values. This is the
   answer for almost every adapter here.
2. **Move it once, with `sending`.** When one isolation domain genuinely hands ownership
   to another, `func handOff(_ element: sending AXUIElement)` compiles and is checked
   ([SE-0430](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md), checked 2026-09-28):
   the compiler proves the caller kept no reference.
3. **A wrapper with `@unchecked Sendable`** — last, rarely, and only with a comment that
   proves the invariant, which `.claude/rules/swift.md` requires. In an adapter that
   proof is usually unwritable, because it would be a claim about a framework's threading
   that Apple does not document. If you cannot write the proof, the design is wrong, not
   the compiler.

## SwiftLint rules that reject the obvious shape

With `opt_in_rules: all`, several rules hit exactly the code an adapter wants to write.
Fixes, not suppressions:

| Rule | What it rejects | Write instead |
|---|---|---|
| `strict_fileprivate` | `fileprivate func report(…)` for the file-scope callback to call | plain internal `func` — same module, same file, no attribute |
| `conditional_returns_on_newline` | `guard let refcon else { return … }` | the `return` on its own line |
| `variable_shadowing` | `let refcon = …` next to a `refcon` property | a distinct name (`callbackContext`) |
| `no_empty_block` | `public init() {}` | a one-line comment inside saying why it is empty |
| `type_contents_order` | an initializer above an instance property | properties, then `init`, then methods |
| `missing_docs` | any undocumented `public` declaration | a `///` saying *why* |
| `no_magic_numbers` | `OSType(0x4D59_4150)` | `private static let signature: OSType = 0x4D59_4150` |
| `vertical_whitespace_between_cases` | packed `switch` cases | a blank line between them |

Run `just fix` first — it formats and applies what `swiftlint --fix` can — then `just lint`
reports what still needs a hand edit.
