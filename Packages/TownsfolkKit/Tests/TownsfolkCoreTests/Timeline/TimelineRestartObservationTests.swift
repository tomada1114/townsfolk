import Testing
import TownsfolkCore

@MainActor
@Suite("Timeline restarted subscription")
struct TimelineRestartObservationTests {
    @Test(arguments: [1, 2])
    func `restarting immediately catches an off-task backdated event`(pageSize: Int) async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(10))
            let model = try TimelineFixtures.model(store: store, clock: clock, pageSize: pageSize)
            let first = Task { await model.run() }
            await clock.waitForSleep(1)
            let initialCount = model.items.count
            let hadFounding = model.outline.contains("event: You moved to Maplewood.")
            var next = clock.sleepsStarted + 1
            try await store.storeYourPost(YourPostDraft(time: StoreFixtures.minutes(8)).make())
            await clock.waitForSleep(next)
            next = clock.sleepsStarted + 1
            try await store.storeYourPost(YourPostDraft(time: StoreFixtures.minutes(9)).make())
            await clock.waitForSleep(next)
            first.cancel()
            await first.value
            let event = try EventDraft(
                time: StoreFixtures.minutes(6), description: "An off-task event.",
            ).make()
            try await store.startEvent(event)
            next = clock.sleepsStarted + 1
            let second = Task { await model.run() }
            defer { second.cancel() }
            await clock.waitForSleep(next)
            #expect(model.outline.contains("event: An off-task event."))
            #expect(model.outline.contains("event: You moved to Maplewood.") == hadFounding)
            #expect(model.items.count == initialCount + 3)
            #expect(model.canLoadOlder)
        }
    }
}
