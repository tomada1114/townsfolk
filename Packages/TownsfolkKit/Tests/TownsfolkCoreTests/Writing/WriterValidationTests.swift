import Foundation
import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// What comes back is checked before it becomes a scene (REQ-008–REQ-010): a speaker who
/// was not chosen, a first post not by the lead, or a post out of bounds discards the
/// scene; a bad topic tag is dropped; reply targets resolve to posts in the prompt.
@Suite("SceneWriter validation")
struct WriterValidationTests {
    /// Where a reply label should land, for the parameterized reply test.
    enum Landing: Sendable {
        case bread
        case firstOfScene
        case nowhere
    }

    /// Stores Mika's "Bread is out." — P1 in every prompt here — and returns it.
    static func storeBread(in store: TownStore, cast: WritingCast) async throws -> Post {
        let bread = try cast.post(by: cast.mika, "Bread is out.", minute: 1)
        try await store.storeScene(TownStore.SceneStep(posts: [bread]))
        return bread
    }

    /// Mika and Jun write about the rain; the model answers `content`.
    static func write(
        _ content: GeneratedContent,
        store: TownStore,
        cast: WritingCast,
    ) async throws -> SceneOutcome {
        try await write(content, store: store, cast: cast, seeds: [.topic("rain")])
    }

    /// Mika and Jun write about `seeds`; the model answers `content`.
    static func write(
        _ content: GeneratedContent,
        store: TownStore,
        cast: WritingCast,
        seeds: [SceneSeed],
    ) async throws -> SceneOutcome {
        let writer = SceneWriter(model: WritingFixtures.fake([.content(content)]), store: store)
        let request = try cast.request(speakers: [cast.mika, cast.jun], seeds: seeds)
        return try await writer.write(request, at: WritingFixtures.now)
    }

    @Test
    func `a valid scene is trimmed, and blank or long tags are dropped down to three`(
    ) async throws {
        try await withWritingStore { store, cast in
            let content = WritingFixtures.content(
                [
                    DraftPost(speaker: " Mika ", text: "  Rain again.  "),
                    DraftPost(speaker: "Jun", text: "Bring an umbrella.", replyTo: "S1"),
                ],
                tags: ["rain", "  ", TownFixtures.text(41), " umbrellas ", "town", "extra"],
            )

            let outcome = try await Self.write(content, store: store, cast: cast)

            #expect(outcome == .written(WrittenScene(
                seed: .topic("rain"),
                posts: [
                    WrittenPost(speaker: cast.mika.id, text: "Rain again.", replyTarget: nil),
                    WrittenPost(
                        speaker: cast.jun.id,
                        text: "Bring an umbrella.",
                        replyTarget: .earlierInScene(0),
                    ),
                ],
                topicTags: ["rain", "umbrellas", "town"],
            )))
        }
    }

    @Test
    func `a repeated tag is dropped in any case, the first spelling kept, before the cap`(
    ) async throws {
        try await withWritingStore { store, cast in
            let content = WritingFixtures.content(
                [DraftPost(speaker: "Mika", text: "Rain again.")],
                tags: ["Rain", "rain", " RAIN ", "town", "Town", "river"],
            )

            let outcome = try await Self.write(content, store: store, cast: cast)

            #expect(outcome == .written(WrittenScene(
                seed: .topic("rain"),
                posts: [WrittenPost(speaker: cast.mika.id, text: "Rain again.", replyTarget: nil)],
                topicTags: ["Rain", "town", "river"],
            )))
        }
    }

    @Test(arguments: ["Aki", "Sora", "mika", "Tomo", ""])
    func `a post by anyone but the speakers passed in discards the scene`(
        speaker: String,
    ) async throws {
        try await withWritingStore { store, cast in
            let content = WritingFixtures.content([
                DraftPost(speaker: "Mika", text: "Rain again."),
                DraftPost(speaker: speaker, text: "Indeed."),
            ])
            let outcome = try await Self.write(content, store: store, cast: cast)
            #expect(outcome == .skipped(.invalidSpeaker))
        }
    }

    @Test
    func `a scene answering your post with someone not chosen is discarded, nothing left out`(
    ) async throws {
        try await withWritingStore { store, cast in
            let yours = try YourPostDraft().make()
            try await store.storeYourPost(yours)
            let content = WritingFixtures.content([
                DraftPost(speaker: "Mika", text: "Rust is fun."),
                DraftPost(speaker: "Sora", text: "I miss this town."),
            ])
            let outcome = try await Self.write(
                content,
                store: store,
                cast: cast,
                seeds: [.yourPost(yours, quoted: true, leadSpeaker: cast.mika.id)],
            )
            #expect(outcome == .skipped(.invalidSpeaker))
            #expect(try await store.recentPosts(before: WritingFixtures.now, limit: 10) == [yours])
        }
    }

    @Test
    func `a first post not by the lead speaker discards the scene`() async throws {
        try await withWritingStore { store, cast in
            let yours = try YourPostDraft().make()
            let content = WritingFixtures.content([
                DraftPost(speaker: "Jun", text: "Rust, huh."),
                DraftPost(speaker: "Mika", text: "Rust is fun."),
            ])
            let outcome = try await Self.write(
                content,
                store: store,
                cast: cast,
                seeds: [.yourPost(yours, quoted: false, leadSpeaker: cast.mika.id)],
            )
            #expect(outcome == .skipped(.leadSpeakerMismatch))
        }
    }

    @Test
    func `a scene from your quoted post replies to it first, whatever the model said`(
    ) async throws {
        try await withWritingStore { store, cast in
            let bread = try await Self.storeBread(in: store, cast: cast)
            let yours = try YourPostDraft(time: StoreFixtures.minutes(2)).make()
            try await store.storeYourPost(yours)
            let content = WritingFixtures.content([
                DraftPost(speaker: "Mika", text: "Rust is fun.", replyTo: "P1"),
                DraftPost(speaker: "Jun", text: "Is it?", replyTo: "P1"),
            ])
            let outcome = try await Self.write(
                content,
                store: store,
                cast: cast,
                seeds: [.yourPost(yours, quoted: true, leadSpeaker: cast.mika.id)],
            )
            guard case let .written(scene) = outcome else {
                Issue.record("expected a scene, got \(outcome)")
                return
            }
            #expect(scene.posts.map(\.replyTarget) == [.post(yours.id), .post(bread.id)])
        }
    }

    @Test(arguments: [
        (TownFixtures.text(280), true),
        (TownFixtures.text(281), false),
        ("  \n ", false),
    ])
    func `a post's text must be 1 to 280 characters once trimmed`(
        text: String,
        kept: Bool,
    ) async throws {
        try await withWritingStore { store, cast in
            let content = WritingFixtures.content([DraftPost(speaker: "Mika", text: text)])
            let outcome = try await Self.write(content, store: store, cast: cast)
            #expect((outcome == .skipped(.invalidPosts)) == !kept)
        }
    }

    @Test(arguments: [0, 4])
    func `a scene of no post or more than three is discarded`(count: Int) async throws {
        try await withWritingStore { store, cast in
            let posts = Array(repeating: DraftPost(speaker: "Mika", text: "Hi."), count: count)
            let outcome = try await Self.write(
                WritingFixtures.content(posts),
                store: store,
                cast: cast,
            )
            #expect(outcome == .skipped(.invalidPosts))
        }
    }

    @Test(arguments: [
        ("P1", Landing.bread),
        (" p1 ", .bread),
        ("P2", .nowhere),
        ("P0", .nowhere),
        ("S1", .firstOfScene),
        ("S2", .nowhere),
        ("S0", .nowhere),
        ("the bakery", .nowhere),
    ])
    func `a second post's reply label resolves to a post in the prompt or to none`(
        label: String,
        landing: Landing,
    ) async throws {
        try await withWritingStore { store, cast in
            let bread = try await Self.storeBread(in: store, cast: cast)
            let content = WritingFixtures.content([
                DraftPost(speaker: "Mika", text: "Rain again.", replyTo: "S1"),
                DraftPost(speaker: "Jun", text: "Indeed.", replyTo: label),
            ])
            let expected: WrittenPost.ReplyTarget? = switch landing {
            case .bread:
                .post(bread.id)

            case .firstOfScene:
                .earlierInScene(0)

            case .nowhere:
                nil
            }
            let outcome = try await Self.write(content, store: store, cast: cast)
            guard case let .written(scene) = outcome else {
                Issue.record("expected a scene, got \(outcome)")
                return
            }
            #expect(scene.posts.map(\.replyTarget) == [nil, expected])
        }
    }

    @Test
    func `content that is not a scene skips the turn`() async throws {
        try await withWritingStore { store, cast in
            let content = try GeneratedContent(json: #"{"topicTags": ["rain"]}"#)
            let outcome = try await Self.write(content, store: store, cast: cast)
            #expect(outcome == .skipped(.malformedOutput))
        }
    }
}
