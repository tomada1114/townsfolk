import Foundation
import Testing
import TownsfolkCore

@Suite("App lifecycle")
@MainActor
struct AppLifecycleTests {
    @Test
    func `only an active available town runs, once; cancellation completes before restart`(
    ) async throws {
        try await withApp { app, store in
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            await app.model.open()
            #expect(app.model.route == .town)
            #expect(!app.model.isEngineRunning)
            await app.model.appActivityChanged(isActive: true)
            await app.probe.clock.waitForSleepers(count: 1)
            await app.model.appActivityChanged(isActive: true)
            #expect(app.probe.starts == 1)
            app.probe.holdsCancellation = true
            let inactive = Task { await app.model.appActivityChanged(isActive: false) }
            await waitUntil { app.probe.isCancelling }
            await app.model.appActivityChanged(isActive: true)
            #expect(app.probe.starts == 1)
            app.probe.finishCancellation()
            await inactive.value
            await app.probe.clock.waitForSleepers(count: 1)
            #expect(app.probe.starts == 2)
            #expect(app.probe.stops == 1)
            app.probe.holdsCancellation = false
            app.provider.availability = .modelNotReady
            await app.model.appActivityChanged(isActive: true)
            #expect(!app.model.isEngineRunning)
            #expect(app.model.route == .town)
            #expect(app.model.availability.notice != nil)
            app.provider.availability = .available
            await app.model.appActivityChanged(isActive: true)
            await app.probe.clock.waitForSleepers(count: 1)
            #expect(app.probe.starts == 3)
        }
    }

    @Test
    func `a speed change reaches the current engine once`() async throws {
        try await withApp { app, store in
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            await app.model.open()
            await app.model.appActivityChanged(isActive: true)
            await app.probe.clock.waitForSleepers(count: 1)
            #expect(app.probe.speedChanges == 1)
            app.model.settings.speedChosen(.fast)
            await app.model.speedChanged()
            await app.model.speedChanged()
            #expect(app.probe.speedChanges == 2)
            #expect(SettingsStore(defaults: app.defaults).speed == .fast)
        }
    }

    @Test
    func `an unavailable town keeps its timeline and accepts your post`() async throws {
        try await withApp(availability: .appleIntelligenceOff) { app, store in
            try await store.found(EngineFixtures.founding(EngineSetup.mikaAlone()))
            await app.model.open()
            await app.model.appActivityChanged(isActive: true)
            let session = try #require(app.model.session)
            session.composer.textChanged(to: "Good morning, neighbors.")
            #expect(session.composer.canPost)
            await session.composer.returnPressed()
            #expect(try await store.recentPosts(before: EngineFixtures.noon, limit: 10).first?.text
                == "Good morning, neighbors.")
            #expect(app.model.route == .town)
            #expect(!app.model.isEngineRunning)
        }
    }
}
