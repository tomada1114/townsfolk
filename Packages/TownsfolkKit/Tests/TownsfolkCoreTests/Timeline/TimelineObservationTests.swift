import Testing
import TownsfolkCore

@MainActor
@Suite("Timeline subscription boundary")
struct TimelineObservationTests {
    private static func event(move: Bool, resident: Resident.ID) throws -> TownEvent {
        try EventDraft(
            kind: move ? .moveIn : EventKindID(rawValue: "rain"),
            time: StoreFixtures.minutes(6),
            description: "The subscribed event.",
            relatedResident: move ? resident : nil,
        ).make()
    }

    @Test(arguments: [(1, false), (2, false), (1, true), (2, true)], [false, true])
    func `subscribed insertions survive initial page crowding and a failed boundary`(
        startup: (pageSize: Int, failed: Bool),
        move: Bool,
    ) async throws {
        try await withFoundedStore { store, founding, directory in
            try await store.storeYourPost(YourPostDraft(time: StoreFixtures.minutes(8)).make())
            try await store.storeYourPost(YourPostDraft(time: StoreFixtures.minutes(9)).make())
            let raw = try directory.raw()
            if startup.failed {
                try raw.execute("ALTER TABLE events RENAME TO hidden_events")
            }
            let observation = await store.timelineObservation()
            #expect(observation.failedBoundary == startup.failed)
            if startup.failed {
                try raw.execute("ALTER TABLE hidden_events RENAME TO events")
            }
            let resident = try ResidentDraft(name: "Hana", movedInAt: StoreFixtures.minutes(6))
                .make()
            let event = try Self.event(move: move, resident: resident.id)
            if move {
                try await store.recordMove(TownStore.MoveStep(resident: resident, event: event))
            } else {
                try await store.startEvent(event)
            }
            let change = await firstChange(observation.changes)
            #expect(change == (move ? .moveRecorded(resident.id) : .eventStarted(event.id)))
            let page = try await store.page(before: nil, limit: startup.pageSize)
            #expect(!page.entries.contains(.event(event)))
            let insertions = try await store.timelineInsertions(after: observation.cursor)
            #expect(insertions.entries.contains(.event(event)))
            #expect(insertions.entries.contains(.event(founding.foundingEvent)) == startup.failed)
        }
    }
}
