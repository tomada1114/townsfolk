import Testing
import TownsfolkCore

@Suite("Writer name boundaries")
struct WriterNameBoundaryTests {
    @Test(arguments: [
        ("trust", "Rust", [String]()),
        ("Rusty", "Rust", []),
        ("Rust2", "Rust", []),
        ("2Rust", "Rust", []),
        ("_Rust", "Rust", []),
        ("Rust_", "Rust", []),
        ("éRust", "Rust", []),
        ("Rusté", "Rust", []),
        ("東京駅", "東京", []),
        ("trust, then RUST.", "rust", ["RUST"]),
        ("New Yorktown; then New York!", "new york", ["New York"]),
        ("(Rust), [Manga]!", "rust", ["Rust"]),
        ("Rust's syntax", "rust", ["Rust"]),
        ("‘Café’", "café", ["Café"]),
        ("(東京)", "東京", ["東京"]),
        ("Meet O’Keeffe.", "o’keeffe", ["O’Keeffe"]),
        ("Jean-Luc arrived.", "jean-luc", ["Jean-Luc"]),
    ])
    func `only complete literal names are extracted`(
        source: String,
        candidate: String,
        expected: [String],
    ) async throws {
        try await withWritingStore { store, cast in
            let post = try Post(
                id: Post.ID(), author: .you, text: source, happenedAt: WritingFixtures.now,
            )
            try await store.storeYourPost(post)
            let draft = SceneDraft(
                posts: [.init(speaker: "Jun", text: "Lovely weather.", replyTo: nil)],
                topicTags: [],
                names: [candidate],
            )
            let fake = WritingFixtures.fake([.content(draft.generatedContent)])
            let request = try cast.request(
                speakers: [cast.jun],
                seeds: [.yourPost(post, quoted: true, leadSpeaker: nil)],
            )
            let result = try await SceneWriter(model: fake, store: store).write(
                request, at: WritingFixtures.now,
            )
            guard case let .written(scene) = result
            else { Issue.record("Expected a response"); return }
            #expect(scene.names == expected)
            #expect(fake.calls.count == 1)
        }
    }
}
