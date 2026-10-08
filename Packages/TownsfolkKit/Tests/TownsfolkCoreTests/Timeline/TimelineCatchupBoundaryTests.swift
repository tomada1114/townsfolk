import Foundation
import Testing
import TownsfolkCore

@MainActor
@Suite("Timeline catch-up boundaries")
struct TimelineCatchupBoundaryTests {
    private static func storeKnownPosts(in store: TownStore, future: Bool) async throws {
        let ids = ["FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"]
        for (index, id) in ids.enumerated() {
            let post = try Post(
                id: Post.ID(rawValue: #require(UUID(uuidString: id))),
                author: .you,
                text: "Known \(index).",
                happenedAt: StoreFixtures.minutes(future ? 6 + index : 5),
            )
            try await store.storeYourPost(post)
        }
    }

    private static func insertRecoverableRows(in raw: RawDatabase) throws {
        try raw.execute("""
        INSERT INTO events (id, kind, description, starts_at, ends_at, status)
        SELECT '00000000-0000-0000-0000-000000000001', 'rain', 'A valid delayed event.',
            starts_at + 120000, ends_at + 120000, 'ongoing' FROM events LIMIT 1;
        INSERT INTO events (id, kind, description, starts_at, ends_at, status)
        SELECT '00000000-0000-0000-0000-000000000002', '', 'A repaired delayed event.',
            starts_at + 180000, ends_at + 180000, 'ongoing' FROM events LIMIT 1;
        """)
    }

    @Test(arguments: [1, 2], [false, true])
    func `known future posts and timestamp ties do not hide a newly committed event`(
        pageSize: Int,
        future: Bool,
    ) async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            try await Self.storeKnownPosts(in: store, future: future)
            let model = try TimelineFixtures.model(store: store, clock: clock, pageSize: pageSize)
            try await whileRunning(model, on: clock) {
                let event = try TownEvent(
                    id: TownEvent
                        .ID(
                            rawValue: #require(UUID(
                                uuidString: "00000000-0000-0000-0000-000000000000",
                            )),
                        ),
                    kind: EventKindID(rawValue: "rain"),
                    description: "Rain starts now.",
                    startsAt: clock.date,
                    endsAt: StoreFixtures.minutes(10),
                )
                let next = clock.sleepsStarted + 1
                try await store.startEvent(event)
                await clock.waitForSleep(next)
                #expect(model.outline.contains("event: Rain starts now."))
                #expect(!model.outline.contains("event: You moved to Maplewood."))
                #expect(model.postTexts.allSatisfy { $0.hasPrefix("Known") })
                if future {
                    #expect(model.postTexts.isEmpty)
                }
                #expect(model.canLoadOlder)
            }
        }
    }

    @Test(arguments: [1, 2], [false, true])
    func `an event or move committed behind a newer post still arrives`(
        pageSize: Int,
        move: Bool,
    ) async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(10))
            let model = try TimelineFixtures.model(store: store, clock: clock, pageSize: pageSize)
            try await whileRunning(model, on: clock) {
                var next = clock.sleepsStarted + 1
                try await store.storeYourPost(YourPostDraft(time: StoreFixtures.minutes(8)).make())
                await clock.waitForSleep(next)
                let count = model.items.count
                next = clock.sleepsStarted + 1
                let resident = try ResidentDraft(name: "Hana", movedInAt: StoreFixtures.minutes(6))
                    .make()
                let event = try EventDraft(
                    kind: move ? .moveIn : EventKindID(rawValue: "rain"),
                    time: StoreFixtures.minutes(6),
                    description: "A delayed town event.",
                    relatedResident: move ? resident.id : nil,
                ).make()
                if move {
                    try await store.recordMove(TownStore.MoveStep(resident: resident, event: event))
                } else {
                    try await store.startEvent(event)
                }
                await clock.waitForSleep(next)
                #expect(model.outline.contains("event: A delayed town event."))
                #expect(model.items.count == count + 1)
                #expect(model.newPostCount == 0)
            }
        }
    }

    @Test(arguments: [false, true])
    func `a failed insertion read keeps its boundary until recovery or deletion`(
        delete: Bool,
    ) async throws {
        try await withFoundedStore { store, _, directory in
            let clock = ManualClock(start: StoreFixtures.minutes(10))
            let model = try TimelineFixtures.model(store: store, clock: clock, pageSize: 1)
            try await whileRunning(model, on: clock) {
                let raw = try directory.raw()
                try Self.insertRecoverableRows(in: raw)
                var next = clock.sleepsStarted + 1
                try await store.setLastRan(clock.date)
                await clock.waitForSleep(next)
                #expect(!model.outline.contains("event: A valid delayed event."))
                if delete {
                    next = clock.sleepsStarted + 1
                    try await store.deleteEverything()
                    await clock.waitForSleep(next)
                } else {
                    try raw.execute("UPDATE events SET kind = 'rain' WHERE kind = ''")
                }
                await clock.advanceAndWait(by: .seconds(60))
                if delete {
                    #expect(model.items.isEmpty)
                    #expect(!model.canLoadOlder)
                } else {
                    #expect(model.outline.contains("event: A valid delayed event."))
                    #expect(model.outline.contains("event: A repaired delayed event."))
                }
            }
        }
    }
}
