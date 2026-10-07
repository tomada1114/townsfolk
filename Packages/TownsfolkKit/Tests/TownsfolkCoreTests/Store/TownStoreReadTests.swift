import Foundation
import Testing
import TownsfolkCore

/// The reads a scene is built from (REQ-007), and what a stored row that no longer reads
/// back as a Core value does.
@Suite("TownStore reads")
struct TownStoreReadTests {
    /// 2026-10-02T09:00:00Z, the moment the recent window is asked for.
    static let asked = StoreFixtures.date("2026-10-02T09:00:00Z")

    // MARK: The recent window

    @Test
    func `the recent window holds the last 24 hours up to the date asked, newest first`(
    ) async throws {
        try await withStore { store, _ in
            let inside = try YourPostDraft(time: StoreFixtures.date("2026-10-01T09:00:01Z")).make()
            let outside = try YourPostDraft(time: StoreFixtures.date("2026-10-01T08:59:59Z")).make()
            let atTheDate = try YourPostDraft(time: Self.asked).make()
            let after = try YourPostDraft(time: StoreFixtures.date("2026-10-02T09:00:01Z")).make()
            for post in [inside, outside, atTheDate, after] {
                try await store.storeYourPost(post)
            }
            #expect(try await store.recentPosts(before: Self.asked, limit: 10) == [
                atTheDate,
                inside,
            ])
        }
    }

    @Test
    func `the recent window takes at most the limit, newest first`() async throws {
        try await withStore { store, _ in
            var posts: [Post] = []
            for minute in 0 ..< 5 {
                let post = try YourPostDraft(time: StoreFixtures.minutes(minute)).make()
                try await store.storeYourPost(post)
                posts.append(post)
            }
            let recent = try await store.recentPosts(before: StoreFixtures.minutes(10), limit: 2)
            #expect(recent == [posts[4], posts[3]])
        }
    }

    @Test
    func `an excluded post is left out of the recent window`() async throws {
        try await withFoundedStore { store, founding, _ in
            let posts = founding.firstScene.posts
            try await store.excludePost(posts[1].id)
            let recent = try await store.recentPosts(before: StoreFixtures.minutes(10), limit: 10)
            #expect(recent == [posts[0]])
        }
    }

    @Test
    func `the window's length comes from Tuning`() async throws {
        try await withTownDirectory { directory in
            var tuning = Tuning.default
            tuning.generation.recentContextWindow = .seconds(90)
            let store = try TownStore(directory: directory.town, tuning: tuning)
            let old = try YourPostDraft(time: StoreFixtures.minutes(0)).make()
            let fresh = try YourPostDraft(time: StoreFixtures.minutes(1)).make()
            try await store.storeYourPost(old)
            try await store.storeYourPost(fresh)
            #expect(try await store
                .recentPosts(before: StoreFixtures.minutes(2), limit: 10) == [fresh])
        }
    }

    @Test(arguments: [0, -3])
    func `a recent window below one post is refused`(limit: Int) async throws {
        try await withStore { store, _ in
            await #expect(throws: TownStoreError.invalidLimit(limit)) {
                try await store.recentPosts(before: Self.asked, limit: limit)
            }
        }
    }

    // MARK: Interests

    @Test
    func `topics still going are the recent window's tags, newest first, each once`(
    ) async throws {
        try await withFoundedStore { store, founding, _ in
            let speaker = try #require(founding.residents.first).id
            let tagged = { (iso: String, tags: [String]) throws -> Post in
                try ResidentPostDraft(
                    author: speaker,
                    time: StoreFixtures.date(iso),
                    topicTags: tags,
                ).make()
            }
            try await store.storeScene(TownStore.SceneStep(posts: [
                tagged("2026-10-01T08:59:59Z", ["old news"]),
                tagged("2026-10-02T08:00:00Z", ["the flood", "bakery"]),
                tagged("2026-10-02T08:30:00Z", ["festival"]),
                tagged("2026-10-02T09:00:01Z", ["tomorrow"]),
            ]))
            #expect(try await store.recentTopicTags(before: Self.asked) == [
                "festival",
                "the flood",
                "bakery",
            ])
        }
    }

    @Test
    func `interests read most recently mentioned first`() async throws {
        try await withFoundedStore { store, founding, _ in
            let speaker = try #require(founding.residents.first).id
            let older = try InterestDraft(term: "Comics", time: StoreFixtures.minutes(1)).make()
            let newer = try InterestDraft(term: "Rust", time: StoreFixtures.minutes(5)).make()
            let post = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(6)).make()
            try await store.storeScene(TownStore.SceneStep(
                posts: [post],
                interests: [older, newer],
            ))
            #expect(try await store.interests() == [newer, older])
        }
    }

    // MARK: A text that is SQL

    @Test
    func `text that reads as SQL is stored as text and the table survives`() async throws {
        try await withStore { store, directory in
            let hostile = try YourPostDraft(text: "'); DROP TABLE posts;--").make()
            try await store.storeYourPost(hostile)
            #expect(try await store.post(hostile.id) == hostile)
            #expect(try directory.raw().tableNames().contains("posts"))
        }
    }

    // MARK: Rows the store would never write

    // The raw connection leaves foreign keys off, as SQLite does by default, so it can
    // plant a row the store's own connection would refuse.

    @Test(arguments: [
        "UPDATE posts SET id = 'not-a-uuid' WHERE rowid = (SELECT min(rowid) FROM posts)",
        "UPDATE posts SET origin = 'gossip' WHERE origin IS NOT NULL",
        "UPDATE posts SET text = CAST(x'FF' AS TEXT)",
        "UPDATE posts SET scene_id = 'not-a-uuid' WHERE scene_id IS NOT NULL",
    ])
    func `a post row that cannot be read is reported as malformed`(tampering: String) async throws {
        try await withFoundedStore { store, _, directory in
            try directory.raw().execute(tampering)
            await #expect(throws: TownStoreError.malformedRow) {
                try await store.recentPosts(before: StoreFixtures.minutes(10), limit: 10)
            }
        }
    }

    @Test
    func `a post row that breaks a post's rules is reported with the rule`() async throws {
        try await withFoundedStore { store, _, directory in
            try directory.raw().execute("UPDATE posts SET text = '   '")
            await #expect(throws: TownStoreError.rejectedRow(.empty(.postText))) {
                try await store.page(before: nil, limit: 10)
            }
        }
    }

    @Test(arguments: [
        "UPDATE events SET status = 'paused'",
        "UPDATE events SET id = 'not-a-uuid'",
        "UPDATE events SET related_resident_id = 'not-a-uuid'",
    ])
    func `an event row that cannot be read is reported as malformed`(
        tampering: String,
    ) async throws {
        try await withFoundedStore { store, _, directory in
            try directory.raw().execute(tampering)
            await #expect(throws: TownStoreError.malformedRow) {
                try await store.page(before: nil, limit: 10)
            }
        }
    }

    @Test(arguments: [
        ("UPDATE town SET name = ''", TownStoreError.rejectedRow(.empty(.townName))),
        ("DELETE FROM town_places", TownStoreError.rejectedRow(.tooFew(.places, minimum: 3))),
    ])
    func `a town row that breaks the town's rules is reported with the rule`(
        tampering: String,
        expected: TownStoreError,
    ) async throws {
        try await withFoundedStore { store, _, directory in
            try directory.raw().execute(tampering)
            await #expect(throws: expected) {
                try await store.town()
            }
        }
    }

    @Test(arguments: [
        ("UPDATE residents SET name = ''", TownStoreError.rejectedRow(.empty(.residentName))),
        (
            "UPDATE resident_relationships SET description = ''",
            TownStoreError.rejectedRow(.empty(.relationshipDescription)),
        ),
        (
            "UPDATE residents SET moved_out_at = 0",
            TownStoreError.rejectedRow(.outOfOrder(.movedOutAt)),
        ),
        ("UPDATE resident_relationships SET other_resident_id = 'x'", TownStoreError.malformedRow),
    ])
    func `a resident row that cannot be read is reported`(
        tampering: String,
        expected: TownStoreError,
    ) async throws {
        try await withFoundedStore { store, _, directory in
            try directory.raw().execute(tampering)
            await #expect(throws: expected) {
                try await store.residents()
            }
        }
    }

    @Test(arguments: [
        (
            "UPDATE interests SET mentions = 0",
            TownStoreError.rejectedRow(.tooFew(.mentions, minimum: 1)),
        ),
        ("UPDATE interest_source_posts SET post_id = 'x'", TownStoreError.malformedRow),
    ])
    func `an interest row that cannot be read is reported`(
        tampering: String,
        expected: TownStoreError,
    ) async throws {
        try await withFoundedStore { store, founding, directory in
            let source = try #require(founding.firstScene.posts.first)
            let speaker = try #require(founding.residents.first).id
            let post = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(3)).make()
            let rust = try InterestDraft(term: "Rust", sources: [source.id]).make()
            try await store.storeScene(TownStore.SceneStep(posts: [post], interests: [rust]))
            try directory.raw().execute(tampering)
            await #expect(throws: expected) {
                try await store.interests()
            }
        }
    }

    @Test
    func `a schedule row that cannot be read is reported as malformed`() async throws {
        try await withFoundedStore { store, founding, directory in
            let post = try #require(founding.firstScene.posts.first)
            let owed = Schedule.PendingResponse(post: post.id, dueAt: StoreFixtures.minutes(5))
            try await store.updatePendingResponses(adding: [owed])
            try directory.raw().execute("UPDATE pending_responses SET post_id = 'x'")
            await #expect(throws: TownStoreError.malformedRow) {
                try await store.schedule()
            }
        }
    }
}
