import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// The timeline following the store's committed steps while it runs.
@MainActor
@Suite("Timeline following the store")
struct TimelineFollowingTests {
    /// Runs `step` against the store and returns once the timeline has taken it in.
    private static func commit(
        on clock: ManualClock,
        _ step: () async throws -> Void,
    ) async throws {
        let next = clock.sleepsStarted + 1
        try await step()
        await clock.waitForSleep(next)
    }

    private static func missedPosts(
        in store: TownStore,
        author: Resident.ID,
        directory: TownDirectory,
        clock: ManualClock,
    ) async throws -> [Post] {
        let raw = try directory.raw()
        try raw.execute("ALTER TABLE events RENAME TO hidden_events")
        let posts = try (2 ... 4).map { minute in
            try ResidentPostDraft(
                author: author,
                time: StoreFixtures.minutes(minute),
                text: "Catch-up \(minute).",
            ).make()
        }
        try await Self.commit(on: clock) {
            try await store.storeScene(TownStore.SceneStep(posts: posts))
        }
        try raw.execute("ALTER TABLE hidden_events RENAME TO events")
        return posts
    }

    @Test
    func `a town founded while the timeline shows an empty store loads at once`() async throws {
        try await withStore { store, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(2))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                #expect(model.items.isEmpty)
                #expect(model.title == "Townsfolk")
                try await Self.commit(on: clock) { try await store.found(StoreFixtures.founding()) }
                #expect(model.title == "Maplewood")
                #expect(model.outline.last == "event: You moved to Maplewood.")
                #expect(try !model.isArrivingLive(#require(model.groups.first?.posts.first).id))
            }
        }
    }

    @Test(arguments: [1, 2])
    func `live founding loads every entry even when it spans pages`(pageSize: Int) async throws {
        try await withStore { store, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock, pageSize: pageSize)
            try await whileRunning(model, on: clock) {
                try await Self.commit(on: clock) { try await store.found(StoreFixtures.founding()) }
                #expect(model.postTexts == [
                    "Bread is out at the bakery.",
                    "Get there before eight.",
                ])
                #expect(model.outline.last == "event: You moved to Maplewood.")
            }
        }
    }

    @Test
    func `a failed initial page retries on the next clock tick without a store change`(
    ) async throws {
        try await withFoundedStore { store, _, directory in
            let raw = try directory.raw()
            try raw.execute("ALTER TABLE events RENAME TO hidden_events")
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                #expect(model.items.isEmpty)
                try raw.execute("ALTER TABLE hidden_events RENAME TO events")
                await clock.advanceAndWait(by: .seconds(60))
                #expect(model.title == "Maplewood")
                #expect(model.postTexts == [
                    "Bread is out at the bakery.",
                    "Get there before eight.",
                ])
                #expect(model.outline.last == "event: You moved to Maplewood.")
            }
        }
    }

    @Test(arguments: [1, 2], [(false, false), (false, true), (true, false), (true, true)])
    func `missed posts across pages recover on a non-scene change or clock tick`(
        pageSize: Int,
        recovery: (onTick: Bool, whileAway: Bool),
    ) async throws {
        let (onTick, whileAway) = recovery
        try await withFoundedStore { store, founding, directory in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock, pageSize: pageSize)
            try await whileRunning(model, on: clock) {
                let initialTexts = model.postTexts
                model.scrollPositionChanged(isAtTop: !whileAway)
                let posts = try await Self.missedPosts(
                    in: store, author: founding.residents[0].id, directory: directory, clock: clock,
                )
                if onTick {
                    await clock.advanceAndWait(by: .seconds(60))
                } else {
                    try await Self.commit(on: clock) { try await store.setLastRan(clock.date) }
                }
                if whileAway {
                    #expect(model.postTexts == initialTexts)
                    #expect(model.newPostCount == 3)
                    model.scrollToLatestChosen()
                    #expect(model.newPostCount == 0)
                }
                #expect(model.postTexts.count == initialTexts.count + 3)
                #expect(Array(model.postTexts.prefix(3)) == [
                    "Catch-up 4.",
                    "Catch-up 3.",
                    "Catch-up 2.",
                ])
                #expect(posts.allSatisfy { model.isArrivingLive($0.id) })
                #expect(model.canLoadOlder)
            }
        }
    }

    @Test(arguments: [1, 2])
    func `a non-scene change catches every missed event across pages`(pageSize: Int) async throws {
        try await withFoundedStore { store, _, directory in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock, pageSize: pageSize)
            try await whileRunning(model, on: clock) {
                let initialCount = model.items.count
                let raw = try directory.raw()
                try raw.execute("ALTER TABLE resident_relationships RENAME TO hidden_relationships")
                for minute in 2 ... 4 {
                    let event = try EventDraft(
                        time: StoreFixtures.minutes(minute),
                        description: "Catch-up event \(minute).",
                    ).make()
                    try await Self.commit(on: clock) { try await store.startEvent(event) }
                }
                try raw.execute("ALTER TABLE hidden_relationships RENAME TO resident_relationships")
                try await Self.commit(on: clock) { try await store.setLastRan(clock.date) }
                #expect(Array(model.outline.prefix(3)) == [
                    "event: Catch-up event 4.",
                    "event: Catch-up event 3.",
                    "event: Catch-up event 2.",
                ])
                #expect(model.items.count == initialCount + 3)
                #expect(model.canLoadOlder)
            }
        }
    }

    @Test
    func `a move recorded while the timeline runs arrives as an event row`() async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                let hana = try ResidentDraft(name: "Hana", movedInAt: StoreFixtures.minutes(4))
                    .make()
                let event = try EventDraft(
                    kind: .moveIn,
                    time: StoreFixtures.minutes(4),
                    description: "Hana moved in above the café.",
                    relatedResident: hana.id,
                ).make()
                try await Self.commit(on: clock) {
                    try await store.recordMove(TownStore.MoveStep(resident: hana, event: event))
                }
                #expect(model.outline.first == "event: Hana moved in above the café.")
                #expect(model.items.count == 3)
            }
        }
    }

    @Test
    func `a scene stored with later times waits, then appears post by post`() async throws {
        try await withFoundedStore { store, founding, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                let scene = SceneID()
                let first = try ResidentPostDraft(
                    author: founding.residents[0].id,
                    time: StoreFixtures.minutes(6),
                    text: "Rain again.",
                    scene: scene,
                ).make()
                let second = try ResidentPostDraft(
                    author: founding.residents[1].id,
                    time: StoreFixtures.minutes(7),
                    text: "Good for the river.",
                    scene: scene,
                ).make()
                try await Self.commit(on: clock) {
                    try await store.storeScene(TownStore.SceneStep(posts: [first, second]))
                }
                #expect(model.items.count == 2)
                await clock.advanceAndWait(by: .seconds(60))
                #expect(model.outline.first == "Rain again.")
                await clock.advanceAndWait(by: .seconds(60))
                #expect(model.outline.first == "Rain again. / Good for the river.")
            }
        }
    }

    @Test
    func `moving away empties the timeline`() async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                #expect(model.items.count == 2)
                try await Self.commit(on: clock) { try await store.deleteEverything() }
                #expect(model.items.isEmpty)
                #expect(model.title == "Townsfolk")
                #expect(!model.canLoadOlder)
            }
        }
    }

    @Test
    func `a store that cannot be read leaves the timeline empty`() async throws {
        try await withFoundedStore { store, _, _ in
            try await store.deleteEverything()
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                #expect(model.items.isEmpty)
                #expect(model.title == "Townsfolk")
            }
        }
    }

    @Test
    func `an older page read before moving away is dropped when it returns`() async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock, pageSize: 1)
            try await whileRunning(model, on: clock) {
                #expect(model.canLoadOlder)
                let started = model.loadGeneration
                let lateResult = try await store.page(before: nil, limit: 3)
                try await Self.commit(on: clock) { try await store.deleteEverything() }

                model.olderPageRead(lateResult, startedIn: started)
                #expect(model.items.isEmpty)
                #expect(!model.canLoadOlder)
            }
        }
    }
}
