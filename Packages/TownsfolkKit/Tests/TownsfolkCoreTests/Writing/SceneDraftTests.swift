import Foundation
import FoundationModels
import Testing
import TownsfolkCore

/// The scene's `@Generable` output (REQ-001): it decodes from generated content, and its
/// schema states the limits the model is asked to keep.
@Suite("SceneDraft")
struct SceneDraftTests {
    @Test
    func `a scene decodes from generated content, a missing reply target as none`() throws {
        let content = try GeneratedContent(json: """
        {"posts": [
            {"speaker": "Mika", "text": "Rain again.", "replyTo": "P2"},
            {"speaker": "Jun", "text": "Bring an umbrella."}
        ], "topicTags": ["rain"]}
        """)

        let draft = try SceneDraft(content)

        #expect(draft == SceneDraft(
            posts: [
                SceneDraft.PostDraft(speaker: "Mika", text: "Rain again.", replyTo: "P2"),
                SceneDraft.PostDraft(speaker: "Jun", text: "Bring an umbrella.", replyTo: nil),
            ],
            topicTags: ["rain"],
        ))
    }

    @Test
    func `a scene the fake answers with decodes back into the same scene`() async throws {
        let draft = SceneDraft(
            posts: [SceneDraft.PostDraft(speaker: "Jun", text: "Quiet day.", replyTo: "S1")],
            topicTags: [],
        )
        let fake = WritingFixtures.fake([.content(draft.generatedContent)])

        let content = try await fake.respond(
            instructions: "",
            prompt: "Write.",
            schema: SceneDraft.generationSchema,
        )

        #expect(try SceneDraft(content) == draft)
    }

    @Test
    func `content without posts does not decode`() throws {
        let content = try GeneratedContent(json: #"{"topicTags": []}"#)
        #expect(throws: (any Error).self) {
            try SceneDraft(content)
        }
    }

    @Test
    func `the schema states domain limits and defers tunable post length to the instructions`(
    ) throws {
        let encoded = try JSONEncoder().encode(SceneDraft.generationSchema)
        let schema = try #require(String(bytes: encoded, encoding: .utf8))

        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let properties = try #require(object["properties"] as? [String: [String: Any]])
        let posts = try #require(properties["posts"])
        let tags = try #require(properties["topicTags"])
        #expect(posts["minItems"] as? Int == WrittenScene.postCount.lowerBound)
        #expect(posts["maxItems"] as? Int == WrittenScene.postCount.upperBound)
        #expect(tags["maxItems"] as? Int == Post.maxTopicTags)
        #expect(schema.contains("the character limit in the instructions"))
        #expect(!schema
            .contains("at most \(Tuning.default.timeline.residentPostMaxLength) characters"))
        #expect(schema.contains("each at most \(Post.topicTagMaxLength) characters"))
        #expect(schema.contains("Up to \(Post.maxTopicTags) short topic tags"))
        #expect(schema.contains("exactly as listed under Speakers"))
    }
}
