import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("App engine integration")
@MainActor
struct AppEngineIntegrationTests {
    @Test
    func `activity and availability cancel the actual engine without overlapping model calls`(
    ) async throws {
        try await withApp(displayName: "Tomo") { app, store in
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            let provider = ModelFixtures.heldFake(outcomes: [.content(WritingFixtures.mikaSpeaks)])
            let model = try makeRoot(app: app, store: store, provider: provider)
            await model.open()
            #expect(provider.calls.isEmpty)
            // Opening re-arms cadence; make a scene due to exercise cancellation now.
            try await store.setNextOrdinarySceneDue(EngineFixtures.start)
            await model.appActivityChanged(isActive: true)
            await provider.waitUntilHeld(count: 1)
            await model.appActivityChanged(isActive: true)
            #expect(provider.calls.count == 1)
            await model.appActivityChanged(isActive: false)
            #expect(provider.inFlightCount == 0)
            provider.availability = .modelNotReady
            await model.appActivityChanged(isActive: true)
            #expect(provider.calls.count == 1)
            provider.availability = .available
            await model.appActivityChanged(isActive: true)
            await provider.waitUntilHeld(count: 1)
            #expect(provider.calls.count == 2)
            #expect(provider.highestInFlight == 1)
            await model.windowClosed()
        }
    }

    @Test
    func `a settings change recomputes the actual engine's stored due time`() async throws {
        try await withApp { app, store in
            var setup = try EngineSetup.mikaAlone()
            setup.due = EngineFixtures.time("10:12:00")
            try await store.found(EngineFixtures.founding(setup))
            let model = try makeRoot(app: app, store: store, provider: app.provider)
            await model.open()
            model.settings.speedChosen(.fast)
            await model.speedChanged()
            let due = try await store.schedule()?.nextOrdinarySceneDue
            #expect(due == EngineFixtures.time("10:07:14.494"))
        }
    }

    @Test
    func `a fresh root reconciles settings persisted before the old schedule was updated`(
    ) async throws {
        try await withApp { app, store in
            let before = try await interruptedSpeedChange(app: app, store: store)
            let model = try makeRoot(app: app, store: store, provider: app.provider)
            await model.open()
            #expect(model.route == .town)
            let after = try #require(await store.schedule())
            #expect(after.nextOrdinarySceneDue == EngineFixtures.time("10:07:14.494"))
            #expect(after.pendingResponses == before.pendingResponses)
            #expect(after.lastRanAt == before.lastRanAt)
            await model.appActivityChanged(isActive: true)
            await app.probe.clock.waitForSleepers(count: 1)
            #expect(app.provider.calls.isEmpty)
            await model.windowClosed()
        }
    }

    @Test
    func `a retained session keeps its current due when the window reappears`() async throws {
        try await withApp { app, store in
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            let model = try makeRoot(app: app, store: store, provider: app.provider)
            await model.open()
            let retained = model.session?.timeline
            await model.windowClosed()
            let due = EngineFixtures.time("10:20:00")
            try await store.setNextOrdinarySceneDue(due)
            await model.open()
            #expect(model.session?.timeline === retained)
            #expect(try await store.schedule()?.nextOrdinarySceneDue == due)
            await model.windowClosed()
        }
    }

    private func interruptedSpeedChange(
        app: AppHarness,
        store: TownStore,
    ) async throws -> Schedule {
        var setup = try EngineSetup.mikaAlone()
        setup.due = EngineFixtures.time("10:12:00")
        try await store.found(EngineFixtures.founding(setup))
        let seedEngine = try actualEngine(
            store: store,
            provider: app.provider,
            suiteName: app.suiteName,
            clock: app.probe.clock,
        )
        try await seedEngine.submitYourPost(EngineResponseFixtures.post(), speed: .normal)
        try await store.setLastRan(EngineFixtures.time("09:59:00"))
        app.model.settings.speedChosen(.fast)
        let schedule = try #require(await store.schedule())
        #expect(!schedule.pendingResponses.isEmpty)
        return schedule
    }

    private func makeRoot(
        app: AppHarness,
        store: TownStore,
        provider: FakeLanguageModelProvider,
    ) throws -> AppModel {
        let screens = AppHarness.session(store: store, defaults: app.defaults, probe: app.probe)
        let engine = try actualEngine(
            store: store,
            provider: provider,
            suiteName: app.suiteName,
            clock: app.probe.clock,
        )
        return AppModel(
            availability: AvailabilityViewModel(provider: provider),
            settings: app.model.settings,
        ) {
            AppTownSession(
                store: store,
                screens: AppTownSession.Screens(
                    firstRun: screens.firstRun,
                    timeline: screens.timeline,
                    composer: screens.composer,
                    statusLine: screens.statusLine,
                ),
                run: { try await engine.run() },
                speedChanged: { await engine.speedChanged() },
            )
        }
    }

    nonisolated func actualEngine(
        store: TownStore,
        provider: FakeLanguageModelProvider,
        suiteName: String,
        clock: EngineClock,
    ) throws -> TownEngine {
        try TownEngine(
            parts: TownEngine.Parts(
                store: store,
                writer: SceneWriter(model: provider, store: store),
                settings: SettingsStore(defaults: #require(UserDefaults(suiteName: suiteName))),
                seedTables: SeedTables.load(),
                model: provider,
            ),
            world: TownEngine.World(
                thermalState: { .nominal },
                clock: clock,
                now: { EngineFixtures.start },
                generator: SplitMix64(seed: EngineSetup.seed),
            ),
        )
    }
}
