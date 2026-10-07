import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// Older pages loaded by keyset as the last row appears (REQ-008).
@MainActor
@Suite("Timeline paging")
struct TimelinePagingTests {
    /// The founded town plus 998 posts, 1,000 in all: a one-post scene, 498 two-post
    /// scenes, and a newest one-post scene, a minute apart from minute 10 on. Newest
    /// first, a page of 100 therefore ends inside a two-post scene.
    private static func storeThousandPosts(
        in store: TownStore,
        founding: TownStore.FoundingStep,
    ) async throws -> [Post] {
        let authors = founding.residents.map(\.id)
        var added: [Post] = []
        func draft(_ index: Int, scene: SceneID) throws -> Post {
            try ResidentPostDraft(
                author: authors[index % authors.count],
                time: StoreFixtures.minutes(10 + index),
                text: "Post \(index).",
                scene: scene,
            ).make()
        }
        var scenes = [[0]]
        scenes += stride(from: 1, to: 997, by: 2).map { [$0, $0 + 1] }
        scenes.append([997])
        for indexes in scenes {
            let scene = SceneID()
            let posts = try indexes.map { try draft($0, scene: scene) }
            try await store.storeScene(TownStore.SceneStep(posts: posts))
            added += posts
        }
        return added
    }

    private static func postIDs(in model: TimelineViewModel) -> [Post.ID] {
        model.groups.flatMap { $0.posts.map(\.id) }
    }

    @Test
    func `loading the next page merges the scene split across the boundary`() async throws {
        try await withFoundedStore { store, founding, _ in
            let added = try await Self.storeThousandPosts(in: store, founding: founding)
            #expect(added.count == 998)
            let clock = ManualClock(start: StoreFixtures.minutes(2_000))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                #expect(Set(Self.postIDs(in: model)) == Set(added[898...].map(\.id)))
                #expect(model.groups.last?.posts.map(\.id) == [added[898].id])
                #expect(model.canLoadOlder)

                let last = try #require(model.items.last)
                await model.rowAppeared(last.id)

                let ids = Self.postIDs(in: model)
                #expect(ids.count == 200)
                #expect(Set(ids) == Set(added[798...].map(\.id)))
                let merged = model.groups.first { $0.posts.contains { $0.id == added[898].id } }
                #expect(merged?.posts.map(\.id) == [added[897].id, added[898].id])
                #expect(model.groups.last?.posts.map(\.id) == [added[798].id])
            }
        }
    }

    @Test
    func `paging to the end shows every entry exactly once, then stops asking`() async throws {
        try await withFoundedStore { store, founding, _ in
            let added = try await Self.storeThousandPosts(in: store, founding: founding)
            let clock = ManualClock(start: StoreFixtures.minutes(2_000))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                var loads = 0
                while model.canLoadOlder, loads < 20, let last = model.items.last {
                    await model.rowAppeared(last.id)
                    loads += 1
                }
                #expect(loads == 10)
                let ids = Self.postIDs(in: model)
                #expect(ids.count == 1_000)
                let expected = added.map(\.id) + founding.firstScene.posts.map(\.id)
                #expect(Set(ids) == Set(expected))
                #expect(model.outline.last == "event: You moved to Maplewood.")

                let before = model.items
                let last = try #require(model.items.last)
                await model.rowAppeared(last.id)
                #expect(model.items == before)
            }
        }
    }

    @Test
    func `a first page shorter than the page size asks for no older page`() async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(2))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                #expect(!model.canLoadOlder)
                #expect(model.items.count == 2)
            }
        }
    }

    @Test
    func `only the last loaded row loads the next page`() async throws {
        try await withFoundedStore { store, _, _ in
            try await store.storeYourPost(YourPostDraft(time: StoreFixtures.minutes(3)).make())
            let clock = ManualClock(start: StoreFixtures.minutes(4))
            let model = try Fixtures.model(store: store, clock: clock, pageSize: 2)
            try await whileRunning(model, on: clock) {
                let firstPage = [
                    "Learning Rust today.",
                    "↩ Bread is out at the bakery. | Get there before eight.",
                ]
                #expect(model.outline == firstPage)
                let first = try #require(model.items.first)
                await model.rowAppeared(first.id)
                #expect(model.outline == firstPage)
                #expect(model.canLoadOlder)

                let last = try #require(model.items.last)
                await model.rowAppeared(last.id)
                #expect(model.outline == [
                    "Learning Rust today.",
                    "Bread is out at the bakery. / Get there before eight.",
                    "event: You moved to Maplewood.",
                ])
                #expect(!model.canLoadOlder)
            }
        }
    }
}
