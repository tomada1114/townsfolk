import Foundation
import Testing
import TownsfolkCore

/// Every call a store answers, by name, so a test can make each one after the store
/// closed; what each is called with does not matter by then.
enum StoreCalls {
    typealias Call = @Sendable (TownStore) async throws -> Void

    static let all: [String: Call] = [
        "endEvent": { try await $0.endEvent(TownEvent.ID()) },
        "excludeInterest": { try await $0.excludeInterest(Interest.ID()) },
        "excludePost": { try await $0.excludePost(Post.ID()) },
        "found": { try await $0.found(StoreFixtures.founding()) },
        "interests": { _ = try await $0.interests() },
        "ongoingEvents": { _ = try await $0.ongoingEvents() },
        "page": { _ = try await $0.page(before: nil, limit: 1) },
        "post": { _ = try await $0.post(Post.ID()) },
        "recentPosts": { _ = try await $0.recentPosts(before: StoreFixtures.morning, limit: 1) },
        "recordMove": { store in
            let founding = try StoreFixtures.founding()
            let resident = try #require(founding.residents.first)
            try await store.recordMove(TownStore.MoveStep(
                resident: resident,
                event: founding.foundingEvent,
            ))
        },
        "residents": { _ = try await $0.residents() },
        "schedule": { _ = try await $0.schedule() },
        "setLastRan": { try await $0.setLastRan(StoreFixtures.morning) },
        "setNextOrdinarySceneDue": { try await $0.setNextOrdinarySceneDue(StoreFixtures.morning) },
        "startEvent": { try await $0.startEvent(EventDraft().make()) },
        "storeScene": { try await $0.storeScene(StoreFixtures.founding().firstScene) },
        "storeYourPost": { try await $0.storeYourPost(YourPostDraft().make()) },
        "town": { _ = try await $0.town() },
        "updatePendingResponses": { try await $0.updatePendingResponses(adding: []) },
    ]
}

/// The store's lifecycle: the change stream, and deleting everything (REQ-008, REQ-009).
@Suite("TownStore")
struct TownStoreTests {
    // MARK: Changes

    @Test
    func `every subscriber receives every committed change`() async throws {
        try await withStore { store, _ in
            let first = await store.changes()
            let second = await store.changes()
            let founding = try StoreFixtures.founding()
            try await store.found(founding)
            try await store.setLastRan(StoreFixtures.minutes(1))
            for changes in [first, second] {
                var iterator = changes.makeAsyncIterator()
                #expect(await iterator.next() == .founded)
                #expect(await iterator.next() == .lastRanChanged)
            }
        }
    }

    @Test
    func `each step announces one change naming the step, not one per effect`() async throws {
        try await withFoundedStore { store, founding, _ in
            let changes = await store.changes()
            let speaker = try #require(founding.residents.first).id
            let post = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(2)).make()
            try await store.storeScene(TownStore.SceneStep(
                posts: [post],
                nextOrdinarySceneDue: StoreFixtures.minutes(12),
            ))
            let newcomer = try ResidentDraft(name: "Sora", movedInAt: StoreFixtures.minutes(60))
                .make()
            let moveIn = try EventDraft(
                kind: .moveIn,
                time: StoreFixtures.minutes(60),
                description: "Sora moved in.",
                relatedResident: newcomer.id,
            ).make()
            try await store.recordMove(TownStore.MoveStep(resident: newcomer, event: moveIn))
            try await store.setLastRan(StoreFixtures.minutes(61))

            var iterator = changes.makeAsyncIterator()
            #expect(await iterator.next() == .sceneStored(posts: [post.id]))
            #expect(await iterator.next() == .moveRecorded(newcomer.id))
            #expect(await iterator.next() == .lastRanChanged)
        }
    }

    @Test
    func `a subscriber that stopped listening does not stop the others`() async throws {
        try await withStore { store, _ in
            _ = await store.changes()
            let kept = await store.changes()
            let yours = try YourPostDraft().make()
            try await store.storeYourPost(yours)
            #expect(await firstChange(kept) == .yourPostStored(yours.id))
        }
    }

    // MARK: Deleting everything

    @Test
    func `deleting everything removes the Town directory and announces it last`() async throws {
        try await withFoundedStore { store, _, directory in
            #expect(FileManager.default.fileExists(atPath: directory.database.path()))
            let changes = await store.changes()
            try await store.deleteEverything()

            #expect(!FileManager.default.fileExists(atPath: directory.town.path()))
            var iterator = changes.makeAsyncIterator()
            #expect(await iterator.next() == .everythingDeleted)
            #expect(await iterator.next() == nil)
            await #expect(throws: TownStoreError.closed) {
                try await store.town()
            }
        }
    }

    @Test(arguments: StoreCalls.all.keys.sorted())
    func `every call after deleting everything throws closed`(call: String) async throws {
        let make = try #require(StoreCalls.all[call])
        try await withStore { store, _ in
            try await store.deleteEverything()
            await #expect(throws: TownStoreError.closed) {
                try await make(store)
            }
        }
    }

    @Test
    func `deleting everything twice throws closed the second time`() async throws {
        try await withStore { store, _ in
            try await store.deleteEverything()
            await #expect(throws: TownStoreError.closed) {
                try await store.deleteEverything()
            }
        }
    }

    @Test
    func `a stream asked for after deleting everything is already finished`() async throws {
        try await withStore { store, _ in
            try await store.deleteEverything()
            #expect(await firstChange(store.changes()) == nil)
        }
    }

    @Test
    func `deleting everything when the directory is already gone still closes the store`(
    ) async throws {
        try await withStore { store, directory in
            try FileManager.default.removeItem(at: directory.town)
            try await store.deleteEverything()
            await #expect(throws: TownStoreError.closed) {
                try await store.schedule()
            }
        }
    }

    @Test
    func `a Town directory that cannot be removed is reported and the store is closed anyway`(
    ) async throws {
        try await withStore { store, directory in
            let manager = FileManager.default
            try manager.setAttributes(
                [.posixPermissions: 0o555],
                ofItemAtPath: directory.root.path(),
            )
            defer { try? manager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: directory.root.path(),
            ) }

            await #expect(throws: TownStoreError.cannotDelete(code: 513)) {
                try await store.deleteEverything()
            }
            await #expect(throws: TownStoreError.closed) {
                try await store.town()
            }
        }
    }

    // MARK: Opening the same town again

    @Test
    func `a store reopened after another closed its connection reads the same town`() async throws {
        try await withTownDirectory { directory in
            let founding = try StoreFixtures.founding()
            do {
                let first = try TownStore(directory: directory.town)
                try await first.found(founding)
            }
            let second = try TownStore(directory: directory.town)
            #expect(try await second.town() == founding.town)
        }
    }
}
