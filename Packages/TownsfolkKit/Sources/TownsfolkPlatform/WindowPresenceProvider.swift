import AppKit
import TownsfolkCore

/// One consumer's observers, and the two facts that arrive only as notifications.
///
/// Every observer is registered with `queue: .main`, so its block runs on the main thread;
/// that registration, in ``start()`` below, is the fact each `MainActor.assumeIsolated`
/// rests on (`integrating-system-apis` › When `MainActor.assumeIsolated` is a fact).
@MainActor
private final class PresenceObservation {
    private let windowIdentifier: NSUserInterfaceItemIdentifier
    private let continuation: AsyncStream<WindowPresence>.Continuation
    private var registrations: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var isAppActive = NSApplication.shared.isActive
    private var isMacAwake = true
    private var areScreensAwake = true
    private var isSessionActive = true

    init(
        windowIdentifier: NSUserInterfaceItemIdentifier,
        continuation: AsyncStream<WindowPresence>.Continuation,
    ) {
        self.windowIdentifier = windowIdentifier
        self.continuation = continuation
    }

    /// Registers every observer, then yields the current presence without waiting for a
    /// change.
    func start() {
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        // Any window's occlusion change, not only the town window's: the town window may
        // not exist yet, and its first occlusion change is how its appearance shows up.
        // Occlusion carries no state of its own here: report() reads it live.
        observe(app, NSWindow.didChangeOcclusionStateNotification, update: nil)
        observe(app, NSApplication.didBecomeActiveNotification) { observation in
            observation.isAppActive = true
        }
        observe(app, NSApplication.didResignActiveNotification) { observation in
            observation.isAppActive = false
        }
        observe(workspace, NSWorkspace.willSleepNotification) { observation in
            observation.isMacAwake = false
        }
        observe(workspace, NSWorkspace.didWakeNotification) { observation in
            observation.isMacAwake = true
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { observation in
            observation.areScreensAwake = false
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { observation in
            observation.areScreensAwake = true
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { observation in
            observation.isSessionActive = false
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { observation in
            observation.isSessionActive = true
        }
        report()
    }

    /// Removes every observer this observation registered. Safe to call twice: the second
    /// call finds nothing left to remove.
    func stop() {
        for registration in registrations {
            registration.center.removeObserver(registration.token)
        }
        registrations.removeAll()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        update: (@MainActor (PresenceObservation) -> Void)?,
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                update?(self)
                self.report()
            }
        }
        registrations.append((center, token))
    }

    /// Yields the three facts as they stand now. The window counts as visible only while
    /// some part of it is on screen and the screens are awake for this login session —
    /// occlusion alone is not relied on for a sleeping display or a switched-away session
    /// (ADR-0006 › Amended).
    private func report() {
        let window = NSApplication.shared.windows.first { $0.identifier == windowIdentifier }
        let isOnScreen = window?.occlusionState.contains(.visible) ?? false
        continuation.yield(WindowPresence(
            isWindowVisible: isOnScreen && areScreensAwake && isSessionActive,
            isAppActive: isAppActive,
            isMacAwake: isMacAwake,
        ))
    }
}

/// The AppKit adapter for ``TownsfolkCore/WindowPresenceProviding``: it watches one window,
/// the app, and the Mac, and reports what it sees.
///
/// Observation only, like `WorkspaceFrontmostAppProvider`: whether the town runs is the
/// engine's decision in Core (ADR-0006). The window is found by its
/// `NSWindow.identifier`, which a SwiftUI `Window` scene sets to the scene's `id`, so
/// `App/` hands over the same string it gives the scene and no view has to reach for its
/// `NSWindow` (ADR-0006 › Amended).
///
/// Each call to ``presenceUpdates()`` registers its own observers and removes them when its
/// consumer stops; ``liveObservationCount`` is what the local-machine test reads to see
/// that teardown happened.
@MainActor
public final class WindowPresenceProvider: WindowPresenceProviding {
    private let windowIdentifier: NSUserInterfaceItemIdentifier
    private var observations: [ObjectIdentifier: PresenceObservation] = [:]

    /// How many observations still hold registered observers.
    package var liveObservationCount: Int {
        observations.count
    }

    /// Watches the window whose `identifier` is `windowIdentifier` — for the town window,
    /// the `id` of its `Window` scene. A window that does not exist yet reads as not
    /// visible until it appears.
    public init(windowIdentifier: String) {
        self.windowIdentifier = NSUserInterfaceItemIdentifier(windowIdentifier)
    }

    public func presenceUpdates() -> AsyncStream<WindowPresence> {
        let (stream, continuation) = AsyncStream.makeStream(of: WindowPresence.self)
        let observation = PresenceObservation(
            windowIdentifier: windowIdentifier,
            continuation: continuation,
        )
        let key = ObjectIdentifier(observation)
        observations[key] = observation
        continuation.onTermination = { [weak self] _ in
            // Termination is reported on whichever thread cancelled the consumer, so the
            // teardown hops to the main actor the observers were registered on.
            Task { @MainActor in
                observation.stop()
                self?.observations[key] = nil
            }
        }
        observation.start()
        return stream
    }
}
