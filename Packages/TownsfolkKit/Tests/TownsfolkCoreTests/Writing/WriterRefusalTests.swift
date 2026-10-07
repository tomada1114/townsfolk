import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Refusals never stall the town (REQ-007, REQ-011; `docs/architecture.md:238`): a refused
/// call is retried with the caller's next seed at most twice, then the turn is skipped;
/// your post or a name you brought up that was in the context of three refused calls in a
/// row is left out, and resident posts never are.
@Suite("SceneWriter refusals")
struct WriterRefusalTests {
    /// Stores `residentPosts` posts by Mika and Jun, your post "Learning Rust today.", and
    /// Rust sourced from it; returns your post.
    static func storeLog(
        in store: TownStore,
        cast: WritingCast,
        residentPosts: Int,
    ) async throws -> Post {
        var posts: [Post] = []
        for index in 0 ..< residentPosts {
            let speaker = index.isMultiple(of: 2) ? cast.mika : cast.jun
            try posts.append(cast.post(by: speaker, "Post \(index).", minute: index))
        }
        let yours = try YourPostDraft(time: StoreFixtures.minutes(residentPosts)).make()
        let rust = try Interest(
            id: cast.rust.id,
            term: "Rust",
            firstMentionedAt: yours.happenedAt,
            lastMentionedAt: yours.happenedAt,
            mentions: 1,
            sourcePosts: [yours.id],
        )
        try await store.storeYourPost(yours)
        try await store.storeScene(TownStore.SceneStep(posts: posts, interests: [rust]))
        return yours
    }

    static func recent(in store: TownStore) async throws -> [Post] {
        try await store.recentPosts(before: WritingFixtures.now, limit: 100)
    }

    /// One turn by Mika and Jun over `seeds`, with a fresh model answering `outcomes`.
    static func turn(
        _ writer: (FakeLanguageModelProvider) -> SceneWriter,
        cast: WritingCast,
        seeds: [SceneSeed],
        outcomes: [FakeLanguageModelProvider.Outcome],
    ) async throws -> (outcome: SceneOutcome, calls: [FakeLanguageModelProvider.Call]) {
        let fake = WritingFixtures.fake(outcomes)
        let request = try cast.request(speakers: [cast.mika, cast.jun], seeds: seeds)
        let outcome = try await writer(fake).write(request, at: WritingFixtures.now)
        return (outcome, fake.calls)
    }

    @Test
    func `three refusals make three calls, skip the turn, and leave out your post and its name`(
    ) async throws {
        try await withWritingStore { store, cast in
            _ = try await Self.storeLog(in: store, cast: cast, residentPosts: 39)
            let rain = try EventDraft().make()
            let fake = WritingFixtures
                .fake(WritingFixtures.refusals(3) + [.content(WritingFixtures.mikaSpeaks)])
            let writer = SceneWriter(model: fake, store: store)
            let request = try cast.request(
                speakers: [cast.mika, cast.jun],
                seeds: [.profile(cast.mika.id, .hobby), .topic("new bread"), .event(rain)],
            )

            let outcome = try await writer.write(request, at: WritingFixtures.now)

            #expect(outcome == .skipped(.refused))
            #expect(fake.calls.count == 3)
            #expect(fake.calls.allSatisfy { $0.prompt.contains(#"Tomo: "Learning Rust today.""#) })
            let left = try await Self.recent(in: store)
            #expect(left.count == 39)
            #expect(!left.contains { $0.author == .you })
            #expect(try await store.interests().isEmpty)
        }
    }

    @Test
    func `with one seed a refusal skips after one call`() async throws {
        try await withWritingStore { store, cast in
            let (outcome, calls) = try await Self.turn(
                { SceneWriter(model: $0, store: store) },
                cast: cast,
                seeds: [.topic("new bread")],
                outcomes: WritingFixtures.refusals(3),
            )
            #expect(outcome == .skipped(.refused))
            #expect(calls.count == 1)
        }
    }

    @Test
    func `the retries per turn come from Tuning`() async throws {
        try await withWritingStore { store, cast in
            var tuning = Tuning.default
            tuning.generation.refusalRetriesPerTurn = 1
            let (outcome, calls) = try await Self.turn(
                { SceneWriter(model: $0, store: store, tuning: tuning) },
                cast: cast,
                seeds: [.topic("a"), .topic("b"), .topic("c")],
                outcomes: WritingFixtures.refusals(3),
            )
            #expect(outcome == .skipped(.refused))
            #expect(calls.count == 2)
        }
    }

    @Test
    func `a refusal moves to the next seed, and the scene names the seed it used`() async throws {
        try await withWritingStore { store, cast in
            let (outcome, calls) = try await Self.turn(
                { SceneWriter(model: $0, store: store) },
                cast: cast,
                seeds: [.topic("new bread"), .topic("the river")],
                outcomes: [.failure(.refused), .content(WritingFixtures.mikaSpeaks)],
            )
            #expect(calls.count == 2)
            #expect(calls[1].prompt.hasSuffix(#"Seed: the topic "the river", still going."#))
            #expect(outcome == .written(WrittenScene(
                seed: .topic("the river"),
                posts: [WrittenPost(speaker: cast.mika.id, text: "Rain again.", replyTarget: nil)],
                topicTags: [],
            )))
        }
    }

    @Test
    func `streaks carry across turns, and the third refusal in a row leaves your post out`(
    ) async throws {
        try await withWritingStore { store, cast in
            _ = try await Self.storeLog(in: store, cast: cast, residentPosts: 1)
            let writer = SceneWriter(
                model: WritingFixtures.fake(WritingFixtures.refusals(3)),
                store: store,
            )
            let request = try cast.request(speakers: [cast.jun], seeds: [.topic("new bread")])

            _ = try await writer.write(request, at: WritingFixtures.now)
            _ = try await writer.write(request, at: WritingFixtures.now)
            let afterTwo = try await Self.recent(in: store)
            _ = try await writer.write(request, at: WritingFixtures.now)
            let afterThree = try await Self.recent(in: store)

            #expect(afterTwo.contains { $0.author == .you })
            #expect(afterThree.map(\.author) == [.resident(cast.mika.id)])
            #expect(try await store.interests().isEmpty)
        }
    }

    @Test
    func `a written scene resets the streaks of what was in its context`() async throws {
        try await withWritingStore { store, cast in
            _ = try await Self.storeLog(in: store, cast: cast, residentPosts: 1)
            let fake = WritingFixtures.fake(
                WritingFixtures.refusals(2) + [.content(WritingFixtures.mikaSpeaks)]
                    + WritingFixtures.refusals(2),
            )
            let writer = SceneWriter(model: fake, store: store)
            let twoSeeds = try cast.request(
                speakers: [cast.mika],
                seeds: [.topic("a"), .topic("b")],
            )
            let oneSeed = try cast.request(speakers: [cast.mika], seeds: [.topic("a")])

            _ = try await writer.write(twoSeeds, at: WritingFixtures.now)
            _ = try await writer.write(oneSeed, at: WritingFixtures.now)
            _ = try await writer.write(twoSeeds, at: WritingFixtures.now)

            #expect(fake.calls.count == 5)
            #expect(try await Self.recent(in: store).contains { $0.author == .you })
            #expect(try await store.interests().map(\.term) == ["Rust"])
        }
    }

    @Test
    func `an item left out mid-turn is gone from the next seed's prompt`() async throws {
        try await withWritingStore { store, cast in
            _ = try await Self.storeLog(in: store, cast: cast, residentPosts: 1)
            var tuning = Tuning.default
            tuning.generation.refusalsBeforeLeftOut = 1
            let (_, calls) = try await Self.turn(
                { SceneWriter(model: $0, store: store, tuning: tuning) },
                cast: cast,
                seeds: [.topic("a"), .topic("b")],
                outcomes: [.failure(.refused), .content(WritingFixtures.mikaSpeaks)],
            )
            #expect(calls.count == 2)
            #expect(calls[0].prompt.contains("Learning Rust today."))
            #expect(calls[0].prompt.contains("- Rust"))
            #expect(!calls[1].prompt.contains("Rust"))
        }
    }

    @Test
    func `resident posts never carry a streak`() async throws {
        try await withWritingStore { store, cast in
            let post = try cast.post(by: cast.jun, "Bread is out.", minute: 1)
            try await store.storeScene(TownStore.SceneStep(posts: [post]))
            let writer = SceneWriter(
                model: WritingFixtures.fake(WritingFixtures.refusals(9)),
                store: store,
            )
            let request = try cast.request(
                speakers: [cast.jun],
                seeds: [.topic("a"), .topic("b"), .topic("c")],
            )

            _ = try await writer.write(request, at: WritingFixtures.now)
            _ = try await writer.write(request, at: WritingFixtures.now)

            #expect(try await Self.recent(in: store) == [post])
        }
    }
}
