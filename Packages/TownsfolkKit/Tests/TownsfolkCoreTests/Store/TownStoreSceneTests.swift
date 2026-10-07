import Foundation
import Testing
import TownsfolkCore

/// Founding and scenes written, then read back unchanged (REQ-003).
@Suite("TownStore founding and scenes")
struct TownStoreSceneTests {
    private static func sortedByID(_ residents: [Resident]) -> [Resident] {
        residents.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
    }

    /// A reply to `target` and a follow-up to the reply, one scene, five and six minutes in.
    private static func conversation(
        by speaker: Resident.ID,
        replyingTo target: Post.ID,
    ) throws -> (reply: Post, followUp: Post) {
        let scene = SceneID()
        let reply = try ResidentPostDraft(
            author: speaker,
            time: StoreFixtures.minutes(5),
            text: "Rust? Brave.",
            replyTarget: target,
            topicTags: ["rust", "learning", "code"],
            scene: scene,
        ).make()
        let followUp = try ResidentPostDraft(
            author: speaker,
            time: StoreFixtures.minutes(6),
            replyTarget: reply.id,
            scene: scene,
        ).make()
        return (reply, followUp)
    }

    @Test
    func `a founded town reads back whole`() async throws {
        try await withStore { store, _ in
            let founding = try StoreFixtures.founding()
            let changes = await store.changes()
            try await store.found(founding)

            #expect(try await store.town() == founding.town)
            let residents = try await store.residents()
            #expect(Self.sortedByID(residents) == Self.sortedByID(founding.residents))
            #expect(try await store.ongoingEvents() == [founding.foundingEvent])
            #expect(try await store.schedule() == founding.schedule)
            for post in founding.firstScene.posts {
                #expect(try await store.post(post.id) == post)
            }
            #expect(await firstChange(changes) == .founded)
        }
    }

    @Test
    func `nothing is stored before founding`() async throws {
        try await withStore { store, _ in
            let town = try await store.town()
            let schedule = try await store.schedule()
            let post = try await store.post(Post.ID())
            #expect(town == nil)
            #expect(schedule == nil)
            #expect(post == nil)
            #expect(try await store.residents().isEmpty)
            #expect(try await store.ongoingEvents().isEmpty)
            #expect(try await store.interests().isEmpty)
        }
    }

    @Test
    func `a scene stores its posts with their replies, tags, and interests`() async throws {
        try await withFoundedStore { store, founding, _ in
            let yours = try YourPostDraft(time: StoreFixtures.minutes(2)).make()
            try await store.storeYourPost(yours)
            let speaker = try #require(founding.residents.first).id
            let (reply, followUp) = try Self.conversation(by: speaker, replyingTo: yours.id)
            let rust = try InterestDraft(term: "Rust", time: yours.happenedAt, sources: [yours.id])
                .make()
            let changes = await store.changes()
            try await store.storeScene(TownStore.SceneStep(
                posts: [reply, followUp],
                interests: [rust],
            ))

            #expect(try await store.post(reply.id) == reply)
            #expect(try await store.post(followUp.id) == followUp)
            #expect(try await store.interests() == [rust])
            #expect(await firstChange(changes) == .sceneStored(posts: [reply.id, followUp.id]))
        }
    }

    @Test
    func `a response scene removes the response it delivers and moves the next due time`(
    ) async throws {
        try await withFoundedStore { store, founding, _ in
            let yours = try YourPostDraft(time: StoreFixtures.minutes(2)).make()
            try await store.storeYourPost(yours)
            let owed = Schedule.PendingResponse(post: yours.id, dueAt: StoreFixtures.minutes(5))
            let later = Schedule.PendingResponse(post: yours.id, dueAt: StoreFixtures.minutes(40))
            try await store.updatePendingResponses(adding: [owed, later])
            let speaker = try #require(founding.residents.last).id
            let reply = try ResidentPostDraft(
                author: speaker,
                time: StoreFixtures.minutes(5),
                replyTarget: yours.id,
            ).make()

            try await store.storeScene(TownStore.SceneStep(
                posts: [reply],
                deliveredResponse: owed,
                nextOrdinarySceneDue: StoreFixtures.minutes(12),
            ))
            let schedule = try #require(try await store.schedule())
            #expect(schedule.pendingResponses == [later])
            #expect(schedule.nextOrdinarySceneDue == StoreFixtures.minutes(12))
        }
    }

    @Test
    func `a scene without a next due time leaves the schedule as it was`() async throws {
        try await withFoundedStore { store, founding, _ in
            let speaker = try #require(founding.residents.last).id
            let post = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(3)).make()
            try await store.storeScene(TownStore.SceneStep(posts: [post]))
            #expect(try await store.schedule() == founding.schedule)
        }
    }

    @Test
    func `a scene touching a stored interest replaces it`() async throws {
        try await withFoundedStore { store, founding, _ in
            let speaker = try #require(founding.residents.first).id
            let source = try #require(founding.firstScene.posts.first)
            let rust = try InterestDraft(term: "Rust", sources: [source.id]).make()
            let first = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(3))
                .make()
            try await store.storeScene(TownStore.SceneStep(posts: [first], interests: [rust]))

            let again = try Interest(
                id: rust.id,
                term: "Rust",
                firstMentionedAt: rust.firstMentionedAt,
                lastMentionedAt: StoreFixtures.minutes(9),
                mentions: 2,
                sourcePosts: [source.id, first.id],
            )
            let second = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(9))
                .make()
            try await store.storeScene(TownStore.SceneStep(posts: [second], interests: [again]))
            #expect(try await store.interests() == [again])
        }
    }

    @Test
    func `an excluded interest stays excluded when a scene touches it again`() async throws {
        try await withFoundedStore { store, founding, _ in
            let speaker = try #require(founding.residents.first).id
            let rust = try InterestDraft(term: "Rust").make()
            let first = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(3))
                .make()
            try await store.storeScene(TownStore.SceneStep(posts: [first], interests: [rust]))
            try await store.excludeInterest(rust.id)

            let second = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(9))
                .make()
            try await store.storeScene(TownStore.SceneStep(posts: [second], interests: [rust]))
            #expect(try await store.interests().isEmpty)
        }
    }
}
