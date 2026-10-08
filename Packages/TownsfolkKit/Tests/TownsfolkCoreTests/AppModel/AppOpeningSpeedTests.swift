import Observation
import Testing
import TownsfolkCore

@MainActor
@Observable
private final class OpeningSpeedHold {
    private(set) var isHeld = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isHeld = true
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@Suite("App initial speed synchronization cancellation")
@MainActor
struct AppOpeningSpeedTests {
    @Test(arguments: [false, true])
    func `closing or cancelling during initial speed synchronization publishes no stale town`(
        cancelTask: Bool,
    ) async throws {
        try await withApp { app, store in
            try await verifyInterruptedOpen(app: app, store: store, cancelTask: cancelTask)
        }
    }

    private func verifyInterruptedOpen(
        app: AppHarness,
        store: TownStore,
        cancelTask: Bool,
    ) async throws {
        try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
        let hold = OpeningSpeedHold()
        let model = root(app: app, store: store, hold: hold)
        let opening = Task { await model.open() }
        await waitUntil { hold.isHeld || model.session != nil }
        if cancelTask {
            opening.cancel()
        } else {
            await model.windowClosed()
        }
        hold.release()
        await opening.value
        #expect(model.session == nil)
        #expect(model.town == nil)
        #expect(model.route == .opening)
        #expect(!model.isEngineRunning)
    }

    private func root(app: AppHarness, store: TownStore, hold: OpeningSpeedHold) -> AppModel {
        let screens = AppHarness.session(store: store, defaults: app.defaults, probe: app.probe)
        return AppModel(availability: app.model.availability, settings: app.model.settings) {
            AppTownSession(
                store: store,
                screens: AppTownSession.Screens(
                    firstRun: screens.firstRun,
                    timeline: screens.timeline,
                    composer: screens.composer,
                    statusLine: screens.statusLine,
                ),
                run: { try await app.probe.run() },
                speedChanged: { await hold.wait() },
            )
        }
    }
}
