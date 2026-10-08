import Testing
import TownsfolkCore

/// Injected post limits reach generation and validation together.
@Suite("SceneWriter tuning")
struct WriterTuningTests {
    @Test(arguments: [(300, true), (301, false)])
    func `custom post length reaches the model and validates the boundary`(
        length: Int,
        accepted: Bool,
    ) async throws {
        try await withWritingStore { store, cast in
            var tuning = Tuning.default
            tuning.timeline.residentPostMaxLength = 300
            let text = String(repeating: "x", count: length)
            let content = WritingFixtures.content([DraftPost(speaker: "Mika", text: text)])
            let fake = WritingFixtures.fake([.content(content)])
            let writer = SceneWriter(model: fake, store: store, tuning: tuning)
            let request = try cast.request(speakers: [cast.mika], seeds: [.topic("rain")])

            let outcome = try await writer.write(request, at: WritingFixtures.now)

            if accepted {
                #expect(outcome == .written(WrittenScene(
                    seed: .topic("rain"),
                    posts: [WrittenPost(speaker: cast.mika.id, text: text, replyTarget: nil)],
                    topicTags: [],
                )))
            } else {
                #expect(outcome == .skipped(.invalidPosts))
            }
            let call = try #require(fake.calls.first)
            #expect(call.instructions.contains("at most 300 characters"))
        }
    }
}
