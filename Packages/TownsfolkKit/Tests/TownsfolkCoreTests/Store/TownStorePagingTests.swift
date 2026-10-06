import Foundation
import Testing
import TownsfolkCore

/// The timeline paged newest first by a keyset cursor (REQ-005, REQ-006).
@Suite("TownStore paging")
struct TownStorePagingTests {
    /// What a page orders by: the entry's time, then its id as stored.
    private struct Key: Comparable {
        let time: Date
        let id: String

        init(_ entry: TimelineEntry) {
            switch entry {
            case let .event(event):
                time = event.startsAt
                id = event.id.rawValue.uuidString

            case let .post(post):
                time = post.happenedAt
                id = post.id.rawValue.uuidString
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.time, lhs.id) < (rhs.time, rhs.id)
        }
    }

    private static func isStrictlyNewestFirst(_ entries: [TimelineEntry]) -> Bool {
        zip(entries, entries.dropFirst()).allSatisfy { Key($0) > Key($1) }
    }

    /// Stores one post of yours at each of `times`, in order.
    private static func storePosts(at times: [Date], in store: TownStore) async throws -> [Post] {
        var posts: [Post] = []
        for time in times {
            let post = try YourPostDraft(time: time).make()
            try await store.storeYourPost(post)
            posts.append(post)
        }
        return posts
    }

    @Test
    func `an empty log is one empty page with no older cursor`() async throws {
        try await withStore { store, _ in
            let page = try await store.page(before: nil, limit: 50)
            #expect(page.entries.isEmpty)
            #expect(page.older == nil)
        }
    }

    @Test
    func `a log of 120 posts pages as 50, 50, and 20, newest first, each exactly once`(
    ) async throws {
        try await withStore { store, _ in
            let tenOClock = StoreFixtures.date("2026-10-01T10:00:00Z")
            let times = (0 ..< 119).map(StoreFixtures.minutes) + [tenOClock]
            let posts = try await Self.storePosts(at: times, in: store)

            let first = try await store.page(before: nil, limit: 50)
            let afterFirst: TimelineCursor = try #require(first.older)
            let second = try await store.page(before: afterFirst, limit: 50)
            let afterSecond: TimelineCursor = try #require(second.older)
            let third = try await store.page(before: afterSecond, limit: 50)

            #expect([first, second, third].map(\.entries.count) == [50, 50, 20])
            #expect(third.older == nil)
            let entries = first.entries + second.entries + third.entries
            #expect(Self.isStrictlyNewestFirst(entries))
            #expect(Set(entries.map(Key.init).map(\.id)) ==
                Set(posts.map(\.id.rawValue.uuidString)))
        }
    }

    @Test
    func `posts sharing a time are split across pages by id, neither skipped nor repeated`(
    ) async throws {
        try await withStore { store, _ in
            let tenOClock = StoreFixtures.date("2026-10-01T10:00:00Z")
            let posts = try await Self.storePosts(
                at: [StoreFixtures.morning, tenOClock, tenOClock],
                in: store,
            )
            let tied = posts.dropFirst()
                .sorted { $0.id.rawValue.uuidString > $1.id.rawValue.uuidString }

            let first = try await store.page(before: nil, limit: 1)
            let afterFirst: TimelineCursor = try #require(first.older)
            let second = try await store.page(before: afterFirst, limit: 1)
            let afterSecond: TimelineCursor = try #require(second.older)
            let third = try await store.page(before: afterSecond, limit: 1)
            #expect(first.entries == [.post(tied[0])])
            #expect(second.entries == [.post(tied[1])])
            #expect(third.entries == [.post(posts[0])])
            #expect(third.older == nil)
        }
    }

    @Test(arguments: [(2, 2, false), (3, 2, true), (1, 5, false)])
    func `a page reports an older entry exactly when one remains`(
        stored: Int,
        limit: Int,
        hasOlder: Bool,
    ) async throws {
        try await withStore { store, _ in
            _ = try await Self.storePosts(at: (0 ..< stored).map(StoreFixtures.minutes), in: store)
            let page = try await store.page(before: nil, limit: limit)
            #expect(page.entries.count == min(stored, limit))
            #expect((page.older != nil) == hasOlder)
        }
    }

    @Test
    func `the largest limit returns every entry and no older cursor`() async throws {
        try await withStore { store, _ in
            let posts = try await Self.storePosts(at: [StoreFixtures.morning], in: store)
            let page = try await store.page(before: nil, limit: .max)
            #expect(page.entries == posts.map(TimelineEntry.post))
            #expect(page.older == nil)
        }
    }

    @Test
    func `posts and events page together by time, then id`() async throws {
        try await withFoundedStore { store, founding, _ in
            let rain = try EventDraft(time: StoreFixtures.minutes(1)).make()
            try await store.startEvent(rain)
            let later = try YourPostDraft(time: StoreFixtures.minutes(2)).make()
            try await store.storeYourPost(later)

            let page = try await store.page(before: nil, limit: 10)
            let posts = founding.firstScene.posts
            let atOneMinute: [TimelineEntry] = [.post(posts[1]), .event(rain)]
                .sorted { Key($0) > Key($1) }
            let atMorning: [TimelineEntry] = [.post(posts[0]), .event(founding.foundingEvent)]
                .sorted { Key($0) > Key($1) }
            #expect(page.entries == [.post(later)] + atOneMinute + atMorning)
            #expect(page.older == nil)
        }
    }

    @Test
    func `an excluded post still shows on the timeline`() async throws {
        try await withFoundedStore { store, founding, _ in
            let post = try #require(founding.firstScene.posts.last)
            try await store.excludePost(post.id)
            let page = try await store.page(before: nil, limit: 1)
            #expect(page.entries == [.post(post)])
        }
    }

    @Test
    func `the page query walks the time indexes and never sorts in a temporary B-tree`(
    ) async throws {
        try await withStore { store, _ in
            let plan = try await store.timelinePagePlan()
            #expect(plan
                .contains { $0.contains("SEARCH posts USING COVERING INDEX posts_happened_at") })
            #expect(plan
                .contains { $0.contains("SEARCH events USING COVERING INDEX events_starts_at") })
            #expect(!plan.contains { $0.contains("TEMP B-TREE") }, "\(plan)")
            #expect(!plan.contains { $0.hasPrefix("SCAN") }, "\(plan)")
        }
    }

    @Test(arguments: [0, -1])
    func `a limit below one is refused`(limit: Int) async throws {
        try await withStore { store, _ in
            await #expect(throws: TownStoreError.invalidLimit(limit)) {
                try await store.page(before: nil, limit: limit)
            }
        }
    }
}
