import Testing
import TownsfolkCore

@Suite("App opening cancellation")
@MainActor
struct AppCancellationTests {
    @Test
    func `cancelled opening is not a store failure and can be opened again`() async throws {
        try await withApp { app, _ in
            let opening = Task { await app.model.open() }
            opening.cancel()
            await opening.value
            #expect(app.model.route == .opening)
            #expect(app.model.session == nil)
            #expect(!app.model.isEngineRunning)
            await app.model.open()
            #expect(app.model.route == .firstRun)
        }
    }

    @Test
    func `reappearing window resumes its retained session without rebuilding`() async throws {
        try await withApp { app, store in
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            await app.model.open()
            let retained = app.model.session?.timeline
            await app.model.appActivityChanged(isActive: true)
            await app.probe.clock.waitForSleepers(count: 1)
            await app.model.windowClosed()
            await app.model.open()
            await app.model.appActivityChanged(isActive: true)
            #expect(app.model.session?.timeline === retained)
            #expect(app.model.isEngineRunning)
            await app.probe.clock.waitForSleepers(count: 1)
            #expect(app.probe.starts == 2)
            await app.model.windowClosed()
        }
    }

    @Test
    func `activity arriving after the window closed cannot restart the engine`() async throws {
        try await withApp { app, store in
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            await app.model.open()
            await app.model.appActivityChanged(isActive: true)
            await app.probe.clock.waitForSleepers(count: 1)
            await app.model.windowClosed()
            await app.model.appActivityChanged(isActive: true)
            #expect(!app.model.isEngineRunning)
            #expect(app.probe.starts == 1)
        }
    }
}
