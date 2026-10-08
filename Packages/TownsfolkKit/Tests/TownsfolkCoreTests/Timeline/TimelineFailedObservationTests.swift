import Testing
import TownsfolkCore

@MainActor
@Suite("Timeline failed subscription recovery")
struct TimelineFailedObservationTests {
    @Test(arguments: [1, 2])
    func `failed startup boundary recovers all rows without animation and retains its change`(
        pageSize: Int,
    ) async throws {
        try await withFoundedStore { store, founding, directory in
            try await store.storeYourPost(YourPostDraft(time: StoreFixtures.minutes(8)).make())
            let raw = try directory.raw()
            try raw.execute("ALTER TABLE events RENAME TO hidden_events")
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try TimelineFixtures.model(store: store, clock: clock, pageSize: pageSize)
            try await whileRunning(model, on: clock) {
                #expect(model.items.isEmpty)
                try raw.execute("ALTER TABLE hidden_events RENAME TO events")
                let event = try EventDraft(
                    time: StoreFixtures.minutes(4), description: "A startup event.",
                ).make()
                let next = clock.sleepsStarted + 1
                try await store.startEvent(event)
                await clock.waitForSleep(next)
                #expect(model.outline.contains("event: A startup event."))
                #expect(model.outline.contains("event: You moved to Maplewood."))
                #expect(model.postTexts == [
                    "Bread is out at the bakery.",
                    "Get there before eight.",
                ])
                #expect(founding.firstScene.posts.allSatisfy { !model.isArrivingLive($0.id) })
                #expect(!model.canLoadOlder)
                await clock.advanceAndWait(by: .seconds(60))
                #expect(model.items.count == 3)
                #expect(model.newPostCount == 0)
            }
        }
    }
}
