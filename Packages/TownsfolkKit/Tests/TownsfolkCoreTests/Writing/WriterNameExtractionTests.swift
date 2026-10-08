import Foundation
import FoundationModels
import Testing
import TownsfolkCore

@Suite("Writer name extraction")
struct WriterNameExtractionTests {
    private static func literalFixture() throws -> (Post, SceneDraft) {
        let forty = String(repeating: "x", count: 40)
        let fortyOne = String(repeating: "y", count: 41)
        let post = try Post(
            id: Post.ID(),
            author: .you,
            text: "Rust, Manga, \(forty), \(fortyOne), fourth.",
            happenedAt: WritingFixtures.now,
        )
        let draft = SceneDraft(
            posts: [.init(speaker: "Jun", text: "Lovely weather.", replyTo: nil)],
            topicTags: [],
            names: ["  rust ", "RUST", "", "invented", fortyOne, "manga", forty, "fourth"],
        )
        return (post, draft)
    }

    private static func priorReply(
        to post: Post,
        by speaker: Resident.ID,
        store: TownStore,
    ) async throws {
        let answer = try Post(
            id: Post.ID(),
            author: .resident(speaker),
            text: "Fine.",
            happenedAt: WritingFixtures.now,
            replyTarget: post.id,
            origin: .response,
            sceneID: SceneID(),
        )
        try await store.storeScene(.init(posts: [answer]))
        try await store.excludePost(answer.id)
    }

    @Test
    func `names have a bounded schema and source compatible defaults`() throws {
        let encoded = try JSONEncoder().encode(SceneDraft.generationSchema)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let properties = try #require(object["properties"] as? [String: [String: Any]])
        let names = try #require(properties["names"])
        #expect(names["maxItems"] as? Int == 3)
        #expect(try #require(names["description"] as? String)
            .contains("each at most 40 characters"))
        #expect(try #require(String(data: encoded, encoding: .utf8))
            .contains("at most 40 characters"))
        #expect(SceneDraft(posts: [], topicTags: []).names.isEmpty)
    }

    @Test
    func `first quoted response normalizes only literal source names in one call`() async throws {
        try await withWritingStore { store, cast in
            let (post, draft) = try Self.literalFixture()
            try await store.storeYourPost(post)
            let fake = WritingFixtures.fake([.content(draft.generatedContent)])
            let writer = SceneWriter(model: fake, store: store)
            let request = try cast.request(
                speakers: [cast.jun],
                seeds: [.yourPost(post, quoted: true, leadSpeaker: nil)],
            )
            let result = try await writer.write(request, at: WritingFixtures.now)
            guard case let .written(scene) = result
            else { Issue.record("Expected a response"); return }
            #expect(scene.names == ["Rust", "Manga", String(repeating: "x", count: 40)])
            #expect(fake.calls.count == 1)
            #expect(fake.calls[0].instructions.contains("names in the quoted seed post"))
        }
    }

    @Test(arguments: [false, true])
    func `ordinary and later quoted scenes never extract`(quoted: Bool) async throws {
        try await withWritingStore { store, cast in
            let post = try Post(
                id: Post.ID(),
                author: .you,
                text: "Rust",
                happenedAt: WritingFixtures.now,
            )
            try await store.storeYourPost(post)
            if quoted {
                try await Self.priorReply(to: post, by: cast.jun.id, store: store)
            }
            let draft = SceneDraft(
                posts: [.init(speaker: "Jun", text: "Rain again.", replyTo: nil)],
                topicTags: [],
                names: ["Rust"],
            )
            let fake = WritingFixtures.fake([.content(draft.generatedContent)])
            let request = try cast.request(
                speakers: [cast.jun],
                seeds: [.yourPost(post, quoted: quoted, leadSpeaker: nil)],
            )
            let result = try await SceneWriter(model: fake, store: store).write(
                request,
                at: WritingFixtures.now,
            )
            guard case let .written(scene) = result
            else { Issue.record("Expected a scene"); return }
            #expect(scene.names.isEmpty)
            #expect(fake.calls[0].instructions.contains("Return an empty names list"))
        }
    }

    @Test
    func `names are matched to original literal text rather than inferred or generated names`(
    ) async throws {
        try await withWritingStore { store, cast in
            let post = try Post(
                id: Post.ID(),
                author: .you,
                text: "Rust / Manga",
                happenedAt: WritingFixtures.now,
            )
            try await store.storeYourPost(post)
            let draft = SceneDraft(
                posts: [.init(speaker: "Jun", text: "Swift is fun.", replyTo: nil)],
                topicTags: [],
                names: ["Rust Manga", "Swift", "rust"],
            )
            let fake = WritingFixtures.fake([.content(draft.generatedContent)])
            let request = try cast.request(
                speakers: [cast.jun],
                seeds: [.yourPost(post, quoted: true, leadSpeaker: nil)],
            )
            let result = try await SceneWriter(model: fake, store: store).write(
                request,
                at: WritingFixtures.now,
            )
            guard case let .written(scene) = result
            else { Issue.record("Expected a scene"); return }
            #expect(scene.names == ["Rust"])
        }
    }

    @Test
    func `already cancelled first quoted writer propagates without a call or write`() async throws {
        try await withStore { store, directory in
            let cast = try WritingCast()
            try await store.found(cast.founding())
            let (post, draft) = try Self.literalFixture()
            try await store.storeYourPost(post)
            let raw = try directory.raw()
            let before = try raw.snapshot()
            let fake = WritingFixtures.fake([.content(draft.generatedContent)])
            let writer = SceneWriter(model: fake, store: store)
            let request = try cast.request(
                speakers: [cast.jun], seeds: [.yourPost(post, quoted: true, leadSpeaker: nil)],
            )
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await writer.write(request, at: WritingFixtures.now)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(fake.calls.isEmpty)
            #expect(try raw.snapshot() == before)
        }
    }
}
