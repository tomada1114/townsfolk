import Foundation
import Testing
import TownsfolkCore

/// A step that fails part-way leaves every table exactly as before and announces
/// nothing (REQ-004, REQ-008; `docs/architecture.md` › Quality targets).
@Suite("TownStore transactions")
struct TownStoreTransactionTests {
    /// SQLITE_CONSTRAINT_FOREIGNKEY: a row points at one the store does not hold.
    static let foreignKey = TownStoreError.statementFailed(code: 787)
    /// SQLITE_CONSTRAINT_PRIMARYKEY.
    static let primaryKey = TownStoreError.statementFailed(code: 1_555)

    /// Asserts that `step` throws `expected`, that a snapshot of every table is unchanged,
    /// and that the first change announced afterwards is a later, successful step's.
    private static func expectRolledBack(
        _ store: TownStore,
        in directory: TownDirectory,
        throwing expected: TownStoreError,
        _ step: () async throws -> Void,
    ) async throws {
        let raw = try directory.raw()
        let before = try raw.snapshot()
        let changes = await store.changes()
        await #expect(throws: expected) {
            try await step()
        }
        #expect(try raw.snapshot() == before)
        let marker = try YourPostDraft(time: StoreFixtures.minutes(999)).make()
        try await store.storeYourPost(marker)
        #expect(await firstChange(changes) == .yourPostStored(marker.id))
    }

    /// Brings the founded town to 42 posts, the last one yours with one response owed.
    private static func fortyTwoPosts(
        in store: TownStore,
    ) async throws -> Schedule.PendingResponse {
        for minute in 10 ..< 49 {
            let post = try YourPostDraft(time: StoreFixtures.minutes(minute)).make()
            try await store.storeYourPost(post)
        }
        let yours = try YourPostDraft(time: StoreFixtures.minutes(60)).make()
        try await store.storeYourPost(yours)
        let owed = Schedule.PendingResponse(post: yours.id, dueAt: StoreFixtures.minutes(65))
        try await store.updatePendingResponses(adding: [owed])
        return owed
    }

    // MARK: Founding

    @Test
    func `a founding whose first scene replies to an unknown post keeps nothing`() async throws {
        try await withStore { store, directory in
            var founding = try StoreFixtures.founding()
            let speaker = try #require(founding.residents.first).id
            let stray = try ResidentPostDraft(author: speaker, replyTarget: Post.ID()).make()
            founding.firstScene.posts.append(stray)
            try await Self.expectRolledBack(store, in: directory, throwing: Self.foreignKey) {
                try await store.found(founding)
            }
            #expect(try await store.town() == nil)
        }
    }

    @Test
    func `a second founding over a stored town is refused`() async throws {
        try await withFoundedStore { store, _, directory in
            let again = try StoreFixtures.founding()
            try await Self.expectRolledBack(store, in: directory, throwing: Self.primaryKey) {
                try await store.found(again)
            }
        }
    }

    // MARK: A scene

    @Test
    func `a scene whose second post replies to an unknown post keeps nothing`() async throws {
        try await withFoundedStore { store, founding, directory in
            let owed = try await Self.fortyTwoPosts(in: store)
            let raw = try directory.raw()
            #expect(try raw.count("posts") == 42)
            let tags = try raw.count("post_topic_tags")
            let speaker = try #require(founding.residents.first).id
            let scene = SceneID()
            let first = try ResidentPostDraft(author: speaker, topicTags: ["bread"], scene: scene)
                .make()
            let second = try ResidentPostDraft(
                author: speaker,
                replyTarget: Post.ID(),
                scene: scene,
            )
            .make()
            let step = try TownStore.SceneStep(
                posts: [first, second],
                interests: [InterestDraft(term: "Rust", sources: [owed.post]).make()],
                deliveredResponse: owed,
                nextOrdinarySceneDue: StoreFixtures.minutes(70),
            )
            try await Self.expectRolledBack(store, in: directory, throwing: Self.foreignKey) {
                try await store.storeScene(step)
            }
            // The 42, plus the post expectRolledBack stores after the failure.
            #expect(try raw.count("posts") == 43)
            #expect(try raw.count("post_topic_tags") == tags)
            #expect(try await store.schedule()?.nextOrdinarySceneDue == StoreFixtures.firstDue)
            #expect(try await store.schedule()?.pendingResponses == [owed])
        }
    }

    @Test
    func `a scene whose second post cannot be stored keeps its first`() async throws {
        try await withFoundedStore { store, founding, directory in
            let speaker = try #require(founding.residents.first).id
            let first = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(3))
                .make()
            let far = try ResidentPostDraft(
                author: speaker,
                time: Date(timeIntervalSince1970: 1e300),
            ).make()
            try await Self.expectRolledBack(store, in: directory, throwing: .dateOutOfRange) {
                try await store.storeScene(TownStore.SceneStep(posts: [first, far]))
            }
            #expect(try await store.post(first.id) == nil)
        }
    }

    // MARK: Single-value steps

    @Test
    func `a skipped turn before founding is refused`() async throws {
        try await withStore { store, directory in
            try await Self.expectRolledBack(store, in: directory, throwing: .notFound) {
                try await store.setNextOrdinarySceneDue(StoreFixtures.minutes(6))
            }
        }
    }

    @Test
    func `last ran before founding is refused`() async throws {
        try await withStore { store, directory in
            try await Self.expectRolledBack(store, in: directory, throwing: .notFound) {
                try await store.setLastRan(StoreFixtures.minutes(6))
            }
        }
    }

    @Test
    func `your post replying to an unknown post is refused`() async throws {
        try await withFoundedStore { store, _, directory in
            let yours = try YourPostDraft(replyTarget: Post.ID()).make()
            try await Self.expectRolledBack(store, in: directory, throwing: Self.foreignKey) {
                try await store.storeYourPost(yours)
            }
        }
    }

    @Test
    func `responses added for an unknown post undo the drop made with them`() async throws {
        try await withFoundedStore { store, _, directory in
            let yours = try YourPostDraft(time: StoreFixtures.minutes(2)).make()
            try await store.storeYourPost(yours)
            let owed = Schedule.PendingResponse(post: yours.id, dueAt: StoreFixtures.minutes(9))
            try await store.updatePendingResponses(adding: [owed])
            let stray = Schedule.PendingResponse(post: Post.ID(), dueAt: StoreFixtures.minutes(9))
            try await Self.expectRolledBack(store, in: directory, throwing: Self.foreignKey) {
                try await store.updatePendingResponses(adding: [stray], droppingFor: [yours.id])
            }
            #expect(try await store.schedule()?.pendingResponses == [owed])
        }
    }

    // MARK: Events and moves

    @Test
    func `an event about an unknown resident is refused`() async throws {
        try await withFoundedStore { store, _, directory in
            let event = try EventDraft(relatedResident: Resident.ID()).make()
            try await Self.expectRolledBack(store, in: directory, throwing: Self.foreignKey) {
                try await store.startEvent(event)
            }
        }
    }

    @Test
    func `ending an event not stored is refused`() async throws {
        try await withFoundedStore { store, _, directory in
            try await Self.expectRolledBack(store, in: directory, throwing: .notFound) {
                try await store.endEvent(TownEvent.ID())
            }
        }
    }

    @Test
    func `a newcomer with an interest not stored keeps neither them nor their event`() async throws {
        try await withFoundedStore { store, _, directory in
            let newcomer = try ResidentDraft(name: "Sora", interests: [Interest.ID()]).make()
            let moveIn = try EventDraft(
                kind: .moveIn,
                description: "Sora moved in.",
                relatedResident: newcomer.id,
            ).make()
            try await Self.expectRolledBack(store, in: directory, throwing: Self.foreignKey) {
                try await store.recordMove(TownStore.MoveStep(resident: newcomer, event: moveIn))
            }
            #expect(try await store.residents().count == 3)
        }
    }

    // MARK: Exclusion

    @Test
    func `excluding a post not stored is refused`() async throws {
        try await withFoundedStore { store, _, directory in
            try await Self.expectRolledBack(store, in: directory, throwing: .notFound) {
                try await store.excludePost(Post.ID())
            }
        }
    }

    @Test
    func `excluding an interest not stored is refused`() async throws {
        try await withFoundedStore { store, _, directory in
            try await Self.expectRolledBack(store, in: directory, throwing: .notFound) {
                try await store.excludeInterest(Interest.ID())
            }
        }
    }

    // MARK: No user text in errors

    @Test
    func `a failed step's error never carries the text it was storing`() async throws {
        try await withFoundedStore { store, founding, _ in
            let sentinel = "SENTINEL-7f3a private words"
            let yours = try YourPostDraft(text: sentinel, replyTarget: Post.ID()).make()
            let speaker = try #require(founding.residents.first).id
            let theirs = try ResidentPostDraft(
                author: speaker,
                text: sentinel,
                replyTarget: Post.ID(),
            )
            .make()
            let errors = try await [
                #require(throws: TownStoreError.self) { try await store.storeYourPost(yours) },
                #require(throws: TownStoreError.self) {
                    try await store.storeScene(TownStore.SceneStep(posts: [theirs]))
                },
            ]
            for error in errors {
                #expect(error == Self.foreignKey)
                #expect(!String(describing: error).contains("SENTINEL"))
                #expect(!String(reflecting: error).contains("SENTINEL"))
            }
        }
    }
}
