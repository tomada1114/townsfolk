import Foundation
import Testing
import TownsfolkCore

@Suite("App recovery")
@MainActor
struct AppRecoveryTests {
    @Test
    func `the factory rebuilds all store-bound models after a move and after a failed deletion`(
    ) async throws {
        try await withStore { store, directory in
            let suite = "AppReopenTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            SettingsStore(defaults: defaults).displayName = try DisplayName("Tomo")
            let factory = AppSessionFactory(directory: directory, defaults: defaults)
            let model = AppModel(
                availability: AvailabilityViewModel(provider: ModelFixtures.fake()),
                settings: SettingsViewModel(defaults: defaults),
                factory: factory.open,
            )
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            await model.open()
            let oldTimeline = try #require(model.session?.timeline)
            #expect(model.route == .town)
            // Failed-delete recovery: reopening the same persisted town.
            await model.reopen()
            #expect(model.route == .town)
            #expect(model.session?.timeline !== oldTimeline)
            let current = try #require(model.session)
            try await current.store.deleteEverything()
            await model.reopen()
            #expect(model.route == .founding)
            #expect(model.town == nil)
            #expect(factory.opens == 3)
        }
    }

    @Test
    func `reopening during cancellation cannot restart the previous engine`() async throws {
        try await withApp { app, store in
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            var opens = 0
            let model = AppModel(
                availability: app.model.availability,
                settings: app.model.settings,
            ) {
                opens += 1
                if opens > 1 {
                    throw TownStoreError.cannotOpen(code: 14)
                }
                return AppHarness.session(store: store, defaults: app.defaults, probe: app.probe)
            }
            await model.open()
            await model.appActivityChanged(isActive: true)
            await app.probe.clock.waitForSleepers(count: 1)
            app.probe.holdsCancellation = true
            let inactive = Task { await model.appActivityChanged(isActive: false) }
            await waitUntil { app.probe.isCancelling }
            let reopening = Task { await model.reopen() }
            await waitUntil { model.isReopening }
            await model.appActivityChanged(isActive: true)
            app.probe.finishCancellation()
            await inactive.value
            await reopening.value
            #expect(app.probe.starts == 1)
            #expect(model.route == .storeUnavailable)
            #expect(!model.isEngineRunning)
            #expect(model.session == nil)
        }
    }

    @Test
    func `a store-open failure retains the root without founding or an engine`() async throws {
        try await withApp { app, _ in
            var opens = 0
            let model = AppModel(
                availability: app.model.availability,
                settings: app.model.settings,
            ) {
                opens += 1
                throw TownStoreError.newerSchema(found: 100, supported: 1)
            }
            await model.open()
            await model.open()
            await model.appActivityChanged(isActive: true)
            #expect(model.route == .storeUnavailable)
            #expect(model.session == nil)
            #expect(model.town == nil)
            #expect(!model.isEngineRunning)
            #expect(opens == 1)
            await model.reopen()
            #expect(opens == 2)
            #expect(model.route == .storeUnavailable)
        }
    }
}
