import FoundationModels

/// What one scene call asks the model to write: 1–3 posts, a short exchange, and 0–3
/// topic tags for the scene (requirements §3.2, §3.11, :395).
///
/// The guides are part of what the model is told (`docs/architecture.md` › The on-device
/// model), so they state the limits; they are a request, not a guarantee, and
/// ``SceneWriter`` checks every limit again before a draft becomes a ``WrittenScene``. The
/// numbers in the descriptions are literals because a guide is fixed at compile time:
/// they mirror `Tuning.timeline.residentPostMaxLength` (280) and
/// ``Post/topicTagMaxLength`` (40), and change with them.
@Generable
public struct SceneDraft: Equatable, Sendable {
    /// One post the model wrote.
    @Generable
    public struct PostDraft: Equatable, Sendable {
        /// Who writes it — checked against the speakers the caller chose.
        @Guide(
            description: "The name of the resident who writes this post, exactly as listed under Speakers.",
        )
        public var speaker: String
        /// What the post says.
        @Guide(description: "The post: 1 or 2 sentences, at most 280 characters.")
        public var text: String
        /// The label of the post it replies to, as the prompt labels them.
        @Guide(
            description: """
            The label of the post this one replies to, such as P3 for a recent post or S1 for an \
            earlier post of this scene; leave it out when the post replies to none.
            """,
        )
        public var replyTo: String?

        /// Creates a post draft, as a test scripts the model's answer.
        public init(speaker: String, text: String, replyTo: String?) {
            self.speaker = speaker
            self.text = text
            self.replyTo = replyTo
        }
    }

    /// The scene's posts, in the order they appear.
    @Guide(
        description: "The scene's posts, in the order they appear.",
        .count(WrittenScene.postCount),
    )
    public var posts: [PostDraft]
    /// What the scene is about, for the status line (§3.3).
    @Guide(
        description: "Up to 3 short topic tags for what the scene is about, each at most 40 characters.",
        .maximumCount(Post.maxTopicTags),
    )
    public var topicTags: [String]

    /// Creates a scene draft, as a test scripts the model's answer.
    public init(posts: [PostDraft], topicTags: [String]) {
        self.posts = posts
        self.topicTags = topicTags
    }
}
