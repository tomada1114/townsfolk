import AppKit
import Foundation
import Testing
import TownsfolkCore
import TownsfolkPlatform
import TownsfolkTestSupport

/// Thrown by a wait that ran out, after it has recorded which condition never held.
private struct TimedOut: Error {}

/// Runs AppKit's event loop on the main thread of a test process, which has none.
///
/// A window's occlusion state only changes while the app takes events from the window
/// server, and a test process never calls `NSApplication.run()`. Taking them by hand from
/// inside a test does not work either: AppKit's event thread wakes the main thread with
/// `CFRunLoopStop`, and a stop that lands while the main thread idles in the outer run loop
/// Swift's async `main` runs ends that loop — and the process, with exit status 0 and no
/// test reported.
///
/// So the loop is run from a before-waiting observer on the main run loop: the first time
/// the outer loop is about to sleep, it enters `nextEvent` and never leaves. A run loop
/// nested in an observer callout, unlike one nested in a main-queue block, still drains the
/// main queue, so main-actor work — the tests themselves — keeps running inside it, and
/// every wake-up stop ends only that inner wait.
@MainActor
private enum AppKitEventLoop {
    private static var isInstalled = false
    private static var isRunning = false

    static func install() {
        guard !isInstalled else {
            return
        }
        isInstalled = true
        let observer = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0,
        ) { _, _ in
            // Added to the main run loop below, so this runs on the main thread.
            MainActor.assumeIsolated {
                run()
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .defaultMode)
    }

    private static func run() {
        guard !isRunning else {
            return
        }
        isRunning = true
        while true {
            if let event = NSApplication.shared.nextEvent(
                matching: .any,
                until: .distantFuture,
                inMode: .default,
                dequeue: true,
            ) {
                NSApplication.shared.sendEvent(event)
            }
        }
    }
}

/// Collects every value a presence stream yields, on the main actor the test reads from.
@MainActor
private final class PresenceRecorder {
    private(set) var values: [WindowPresence] = []
    private var reading: Task<Void, Never>?

    var latest: WindowPresence? {
        values.last
    }

    init(_ stream: AsyncStream<WindowPresence>) {
        reading = Task { [weak self] in
            for await presence in stream {
                self?.values.append(presence)
            }
        }
    }

    /// Cancels the reading task, which ends the observation the way a consumer that stops
    /// listening would.
    func stop() {
        reading?.cancel()
    }
}

/// Windows to watch, and waiting for the window server to catch up.
@MainActor
private enum Harness {
    private enum Timeout {
        /// How long a window-server change may take to reach the observer. A bound on
        /// failure only: a change that arrives ends the wait at once.
        static let change = Duration.seconds(changeSeconds)
        /// The interval between two looks at what has arrived.
        static let poll = Duration.milliseconds(pollMilliseconds)

        private static let changeSeconds = 5
        private static let pollMilliseconds = 20
    }

    /// Where the test window sits, in points: clear of the menu bar and the Dock.
    private enum Frame {
        static let origin = 240
        static let width = 320
        static let height = 240
    }

    static var changeTimeout: Duration {
        Timeout.change
    }

    static func uniqueIdentifier() -> String {
        "WindowPresenceProviderTests-\(UUID().uuidString)"
    }

    static func provider(for window: NSWindow) -> WindowPresenceProvider {
        WindowPresenceProvider(windowIdentifier: window.identifier?.rawValue ?? "")
    }

    /// A titled window on screen, with no open or close animation to wait out.
    static func showWindow(identifier: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: Frame.origin,
                y: Frame.origin,
                width: Frame.width,
                height: Frame.height,
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.title = "WindowPresenceProviderTests"
        window.orderFrontRegardless()
        return window
    }

    static func showWindow() -> NSWindow {
        showWindow(identifier: uniqueIdentifier())
    }

    static func observeAndDrop(_ provider: WindowPresenceProvider) {
        _ = provider.presenceUpdates()
    }

    static func waitUntilOnScreen(_ window: NSWindow) async throws {
        try await wait(until: "the test window on screen — is the screen awake and unlocked?") {
            window.occlusionState.contains(.visible)
        }
    }

    /// Waits for `condition`, failing with `description` after ``Timeout/change``.
    static func wait(until description: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + Timeout.change
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for \(description)")
                throw TimedOut()
            }
            try await Task.sleep(for: Timeout.poll)
        }
    }
}

/// `WindowPresenceProvider` against a real `NSWindow`, the real window server, and the real
/// notification centers — the translation a Core test with `FakeWindowPresenceProvider`
/// cannot check.
///
/// Beside the translation tests sits the adapter half of the port's contract suite:
/// `WindowPresenceProvidingContract`, the same function `TownsfolkCoreTests` runs against
/// the fake on every `just test` (`.claude/rules/testing.md` › One Contract Suite per Port).
///
/// Serialized because each test puts a window on screen: two at once could cover each
/// other and turn an occlusion assertion into a race. Each test's window carries an
/// identifier of its own, so a window another test left behind is never the one watched.
/// It needs no TCC grant, only a logged-in GUI session with the screen awake and unlocked.
@MainActor
@Suite("WindowPresenceProvider against a real NSWindow", .requiresLocalMachine, .serialized)
struct WindowPresenceProviderTests {
    init() {
        // A test process starts with no activation policy that lets it own windows on
        // screen; an accessory app may show windows without taking a Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)
        AppKitEventLoop.install()
    }

    @Test
    func `keeps the WindowPresenceProviding contract the fake is held to`() async throws {
        let window = Harness.showWindow()
        defer { window.close() }
        try await Harness.waitUntilOnScreen(window)

        await WindowPresenceProvidingContract.check(Harness.provider(for: window))
    }

    @Test
    func `the first value reports a window on screen as visible and the Mac as awake`(
    ) async throws {
        let window = Harness.showWindow()
        defer { window.close() }
        try await Harness.waitUntilOnScreen(window)

        let first = try #require(
            await WindowPresenceProvidingContract.firstValue(
                of: Harness.provider(for: window).presenceUpdates(),
                within: Harness.changeTimeout,
            ),
        )

        #expect(first.isWindowVisible)
        #expect(first.isMacAwake)
        #expect(first.isAppActive == NSApplication.shared.isActive)
    }

    @Test
    func `miniaturizing and ordering out read as not visible, showing again as visible`(
    ) async throws {
        let window = Harness.showWindow()
        defer { window.close() }
        try await Harness.waitUntilOnScreen(window)
        let recorder = PresenceRecorder(Harness.provider(for: window).presenceUpdates())
        defer { recorder.stop() }
        try await Harness
            .wait(until: "visible true first") { recorder.latest?.isWindowVisible == true }

        window.miniaturize(nil)
        try await Harness.wait(until: "visible false after miniaturize") {
            recorder.latest?.isWindowVisible == false
        }

        window.deminiaturize(nil)
        try await Harness.wait(until: "visible true after deminiaturize") {
            recorder.latest?.isWindowVisible == true
        }

        window.orderOut(nil)
        try await Harness.wait(until: "visible false after order out") {
            recorder.latest?.isWindowVisible == false
        }

        window.orderFrontRegardless()
        try await Harness.wait(until: "visible true after showing again") {
            recorder.latest?.isWindowVisible == true
        }
    }

    @Test
    func `a window that does not exist yet reads as not visible until it appears`() async throws {
        let identifier = Harness.uniqueIdentifier()
        let recorder = PresenceRecorder(
            WindowPresenceProvider(windowIdentifier: identifier).presenceUpdates(),
        )
        defer { recorder.stop() }
        try await Harness.wait(until: "a first value") { recorder.latest != nil }
        #expect(recorder.values.first?.isWindowVisible == false)

        let window = Harness.showWindow(identifier: identifier)
        defer { window.close() }

        try await Harness.wait(until: "visible true once the window appears") {
            recorder.latest?.isWindowVisible == true
        }
    }

    @Test
    func `a consumer that stops releases every observer it registered`() async throws {
        let provider = WindowPresenceProvider(windowIdentifier: Harness.uniqueIdentifier())

        let recorder = PresenceRecorder(provider.presenceUpdates())
        try await Harness.wait(until: "a first value") { recorder.latest != nil }
        #expect(provider.liveObservationCount == 1)
        recorder.stop()
        try await Harness.wait(until: "the cancelled observation torn down") {
            provider.liveObservationCount == 0
        }

        Harness.observeAndDrop(provider)
        // Teardown hops to the main actor, which this test holds until its next await.
        #expect(provider.liveObservationCount == 1)
        try await Harness.wait(until: "the dropped observation torn down") {
            provider.liveObservationCount == 0
        }
    }
}
