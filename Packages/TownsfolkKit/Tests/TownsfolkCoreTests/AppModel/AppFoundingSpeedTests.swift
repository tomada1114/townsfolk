import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("App founding speed reconciliation")
@MainActor
struct AppFoundingSpeedTests {
    @Test
    func `a speed chosen during held founding is applied before the engine resumes`() async throws {
        try await withApp { app, store in
            let provider = FirstRunFixtures.heldFake(FoundingFixtures.happyPath)
            let founding = try FirstRunFixtures.founding(
                provider,
                store: store,
                name: FirstRunFixtures.tomo(),
            )
            let model = try root(
                app: app,
                store: store,
                provider: provider,
                founding: founding,
                expected: FoundingFixtures.now.addingTimeInterval(60),
            )
            try await verifySpeedChange(
                app: app, store: store, provider: provider, model: model, founding: founding,
            )
        }
    }

    @Test
    func `unchanged speed keeps the founding schedule when the engine resumes`() async throws {
        try await withApp { app, store in
            let provider = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let founding = try FirstRunFixtures.founding(
                provider, store: store, name: FirstRunFixtures.tomo(),
            )
            let model = try root(
                app: app,
                store: store,
                provider: provider,
                founding: founding,
                expected: FoundingFixtures.now.addingTimeInterval(180),
            )
            await model.open()
            await model.appActivityChanged(isActive: true)
            let firstRun = try #require(model.session?.firstRun)
            firstRun.nameEdited("Tomo")
            firstRun.continuePressed()
            await model.stateChanged()
            try await founding.run()
            let captured = try #require(await store.schedule())
            founding.announcementPosted()
            await model.stateChanged()
            #expect(try await store.schedule() == captured)
            await app.probe.clock.waitForSleepers(count: 1)
            await model.windowClosed()
        }
    }

    @Test(arguments: [false, true], [false, true])
    func `speed chosen on S2 preserves founding capture despite delayed observation`(
        changeAgainOnS3: Bool,
        deferSpeedObservation: Bool,
    ) async throws {
        try await withApp { app, store in
            try await verifyCapturedSpeed(
                app: app,
                store: store,
                changeAgainOnS3: changeAgainOnS3,
                deferSpeedObservation: deferSpeedObservation,
            )
        }
    }

    private func verifyCapturedSpeed(
        app: AppHarness,
        store: TownStore,
        changeAgainOnS3: Bool,
        deferSpeedObservation: Bool,
    ) async throws {
        let provider = FoundingFixtures.fake(FoundingFixtures.happyPath)
        let founder = try founder(provider, store: store)
        var capturedSpeed: Speed?
        let firstRun = FirstRunViewModel(defaults: app.defaults) { name in
            let speed = SettingsStore(defaults: app.defaults).speed
            capturedSpeed = speed
            return FoundingViewModel(
                displayName: name,
                founder: founder,
                store: store,
                speed: speed,
                clock: EngineClock(),
            )
        }
        let expected = FoundingFixtures.now.addingTimeInterval(changeAgainOnS3 ? 1_800 : 30)
        let model = try root(
            app: app,
            store: store,
            provider: provider,
            firstRun: (model: firstRun, speed: { capturedSpeed }),
            expected: expected,
        )
        await model.open()
        await model.appActivityChanged(isActive: true)
        model.settings.speedChosen(.fast)
        if !deferSpeedObservation {
            await model.speedChanged()
        }
        firstRun.nameEdited("Tomo")
        firstRun.continuePressed()
        let founding = try #require(firstRun.founding)
        if changeAgainOnS3 {
            model.settings.speedChosen(.slow)
        }
        if deferSpeedObservation || changeAgainOnS3 {
            await model.speedChanged()
        }
        try await founding.run()
        #expect(capturedSpeed == .fast)
        #expect(try await store.schedule()?.nextOrdinarySceneDue
            == FoundingFixtures.now.addingTimeInterval(30))
        founding.announcementPosted()
        await model.stateChanged()
        #expect(try await store.schedule()?.nextOrdinarySceneDue == expected)
        await app.probe.clock.waitForSleepers(count: 1)
        await model.windowClosed()
    }

    private func verifySpeedChange(
        app: AppHarness,
        store: TownStore,
        provider: FakeLanguageModelProvider,
        model: AppModel,
        founding: FoundingViewModel,
    ) async throws {
        let expected = FoundingFixtures.now.addingTimeInterval(60)
        await model.open()
        let firstRun = try #require(model.session?.firstRun)
        await model.appActivityChanged(isActive: true)
        firstRun.nameEdited("Tomo")
        firstRun.continuePressed()
        await model.stateChanged()
        let running = Task { try await founding.run() }
        await provider.waitUntilHeld(count: 1)
        model.settings.speedChosen(.fast)
        await model.speedChanged()
        #expect(try await store.schedule() == nil)
        for _ in FoundingFixtures.happyPath {
            await provider.waitUntilHeld(count: 1)
            provider.releaseHeld()
        }
        try await running.value
        let captured = try #require(await store.schedule())
        #expect(captured.nextOrdinarySceneDue != expected)
        #expect(try await store.recentPosts(before: EngineFixtures.noon, limit: 10).first?
            .happenedAt
            == FoundingFixtures.now)
        founding.announcementPosted()
        await model.stateChanged()
        #expect(try await store.schedule()?.nextOrdinarySceneDue == expected)
        #expect(try await store.recentPosts(before: EngineFixtures.noon, limit: 10).first?
            .happenedAt
            == FoundingFixtures.now)
        await app.probe.clock.waitForSleepers(count: 1)
        #expect(app.probe.starts == 1)
        await model.windowClosed()
    }

    private func root(
        app: AppHarness,
        store: TownStore,
        provider: FakeLanguageModelProvider,
        founding: FoundingViewModel,
        expected: Date,
    ) throws -> AppModel {
        let firstRun = FirstRunViewModel(defaults: app.defaults) { _ in founding }
        return try root(
            app: app,
            store: store,
            provider: provider,
            firstRun: (model: firstRun, speed: { .normal }),
            expected: expected,
        )
    }

    private func root(
        app: AppHarness,
        store: TownStore,
        provider: FakeLanguageModelProvider,
        firstRun: (model: FirstRunViewModel, speed: @MainActor () -> Speed?),
        expected: Date,
    ) throws -> AppModel {
        let screens = AppHarness.session(store: store, defaults: app.defaults, probe: app.probe)
        let engine = try speedEngine(store: store, provider: provider, suiteName: app.suiteName)
        return AppModel(
            availability: AvailabilityViewModel(provider: provider),
            settings: app.model.settings,
        ) {
            AppTownSession(
                store: store,
                screens: AppTownSession.Screens(
                    firstRun: firstRun.model,
                    timeline: screens.timeline,
                    composer: screens.composer,
                    statusLine: screens.statusLine,
                    foundingSpeed: firstRun.speed,
                ),
                run: {
                    #expect(try await store.schedule()?.nextOrdinarySceneDue == expected)
                    try await app.probe.run()
                },
                speedChanged: { await engine.speedChanged() },
            )
        }
    }

    nonisolated func speedEngine(
        store: TownStore,
        provider: FakeLanguageModelProvider,
        suiteName: String,
    ) throws -> TownEngine {
        var tuning = Tuning.default
        tuning.pace.sceneIntervalJitter = 0
        return try TownEngine(
            parts: TownEngine.Parts(
                store: store,
                writer: SceneWriter(model: provider, store: store),
                settings: SettingsStore(defaults: #require(UserDefaults(suiteName: suiteName))),
                seedTables: SeedTables.load(),
                model: provider,
            ),
            world: TownEngine.World(
                thermalState: { .nominal },
                clock: EngineClock(),
                now: { FoundingFixtures.now },
                generator: RepeatingGenerator(value: 0),
            ),
            tuning: tuning,
        )
    }
}
