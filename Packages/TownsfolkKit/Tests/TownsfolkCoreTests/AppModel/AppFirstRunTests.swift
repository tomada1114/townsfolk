import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("App first-run integration")
@MainActor
struct AppFirstRunTests {
    @Test
    func `losing availability preserves typed input and returning restores the same screen`(
    ) async throws {
        try await withApp { app, _ in
            await app.model.open()
            let firstRun = try #require(app.model.session?.firstRun)
            firstRun.nameEdited("Tomo")
            app.provider.availability = .modelNotReady
            await app.model.appActivityChanged(isActive: true)
            #expect(app.model.route == .unavailable)
            app.provider.availability = .available
            await app.model.appActivityChanged(isActive: true)
            #expect(app.model.route == .firstRun)
            #expect(app.model.session?.firstRun === firstRun)
            #expect(firstRun.nameField == "Tomo")
            #expect(!app.model.isEngineRunning)
        }
    }

    @Test
    func `an interrupted founding launch skips name entry`() async throws {
        try await withApp(displayName: "Tomo") { app, _ in
            await app.model.open()
            #expect(app.model.route == .founding)
            #expect(app.model.session?.firstRun.founding?.displayName.value == "Tomo")
            #expect(!app.model.isEngineRunning)
        }
    }

    @Test
    func `a founded town stays on S3 until announced, then its first scene and engine appear`(
    ) async throws {
        try await withApp { app, store in
            let model = try foundingRoot(app: app, store: store)
            await model.open()
            let firstRun = try #require(model.session?.firstRun)
            await model.appActivityChanged(isActive: true)
            firstRun.nameEdited("Tomo")
            firstRun.continuePressed()
            await model.stateChanged()
            let founding = try #require(firstRun.founding)
            try await founding.run()
            await model.stateChanged()
            #expect(model.route == .founding)
            #expect(!model.isEngineRunning)
            founding.announcementPosted()
            await model.stateChanged()
            #expect(model.route == .town)
            #expect(model.windowTitle == "Maplewood")
            #expect(model.settings.displayName?.value == "Tomo")
            #expect(model.session?.timeline.yourName == "Tomo")
            try await assertFirstScene(store)
            await app.probe.clock.waitForSleepers(count: 1)
            #expect(model.isEngineRunning)
            await model.windowClosed()
        }
    }

    @Test
    func `founding resumes automatically when its unavailable model returns`() async throws {
        try await withApp { app, store in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let model = try foundingRoot(app: app, store: store, fake: fake)
            await model.open()
            let firstRun = try #require(model.session?.firstRun)
            firstRun.nameEdited("Tomo")
            firstRun.continuePressed()
            let founding = try #require(firstRun.founding)
            fake.availability = .modelNotReady
            try await founding.run()
            await model.stateChanged()
            #expect(model.route == .unavailable)
            #expect(founding.phase == .unavailable(.modelNotReady))
            fake.availability = .available
            await model.appActivityChanged(isActive: true)
            #expect(model.route == .founding)
            #expect(founding.phase == .founding)
            #expect(founding.attempt == 1)
            try await founding.run()
            founding.announcementPosted()
            await model.stateChanged()
            #expect(model.route == .town)
            await model.windowClosed()
        }
    }

    private func assertFirstScene(_ store: TownStore) async throws {
        let page = try await store.page(before: nil, limit: 20)
        #expect(page.entries.contains { entry in
            if case let .event(event) = entry {
                return event.description == "You moved to Maplewood."
            }
            return false
        })
        #expect(try await !store.recentPosts(before: EngineFixtures.noon, limit: 10).isEmpty)
    }
}
