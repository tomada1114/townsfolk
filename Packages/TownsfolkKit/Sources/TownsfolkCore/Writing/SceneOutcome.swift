/// Why a turn wrote no scene. A skipped turn shows nothing (requirements §3.2, §3.11);
/// the engine tries again on the next one.
///
/// No case carries a prompt, a post, a name, or anything the model wrote: a reason is
/// logged and may reach test output (`designing-errors` › No user data in errors or logs).
public enum SceneSkipReason: Sendable, Equatable {
    /// A post was blank or too long, or the scene had no post or more than three.
    case invalidPosts
    /// A post was written by someone who is not one of the speakers.
    case invalidSpeaker
    /// The seed set a lead speaker, and someone else wrote the first post.
    case leadSpeakerMismatch
    /// The model's answer did not decode into a ``SceneDraft``.
    case malformedOutput
    /// The model failed for a reason with no recovery beyond skipping.
    case modelFailed
    /// The prompt did not fit the context, even without recent posts or after the
    /// half-size retry.
    case overflow
    /// Every seed tried was refused.
    case refused
    /// Reading the store failed with this error, which carries only codes.
    case storeReadFailed(TownStoreError)
    /// The model is not available.
    case unavailable
}

/// One checked post of a ``WrittenScene``: a speaker the caller chose, text within its
/// limits, and a reply target that names a real post or none.
public struct WrittenPost: Sendable, Equatable {
    /// What a post replies to.
    public enum ReplyTarget: Sendable, Equatable {
        /// The earlier post of the same scene at this index — its id is minted when the
        /// engine stores the scene.
        case earlierInScene(Int)
        /// A post that was in the prompt.
        case post(Post.ID)
    }

    /// The resident who wrote it, one of the request's speakers.
    public let speaker: Resident.ID
    /// What it says, trimmed at both ends.
    public let text: String
    /// What it replies to, if anything.
    public let replyTarget: ReplyTarget?

    /// Creates a written post.
    public init(speaker: Resident.ID, text: String, replyTarget: ReplyTarget?) {
        self.speaker = speaker
        self.text = text
        self.replyTarget = replyTarget
    }
}

/// A scene the model wrote and the writer checked (REQ-002): what the engine (#19) and
/// founding (#20) turn into stored posts, with their ids, times, origin, and scene id.
public struct WrittenScene: Sendable, Equatable {
    /// How many posts a scene has (requirements.md:161).
    public static let postCount = 1 ... 3

    /// The seed the scene was written from — after a refusal, a later one of the
    /// request's.
    public let seed: SceneSeed
    /// The scene's posts, in order.
    public let posts: [WrittenPost]
    /// Up to ``Post/maxTopicTags`` topic tags, each within ``Post/topicTagMaxLength``.
    public let topicTags: [String]

    /// Validated literal names from an eligible first quoted response; otherwise empty.
    public let names: [String]

    /// Creates a written scene.
    public init(seed: SceneSeed, posts: [WrittenPost], topicTags: [String], names: [String] = []) {
        self.seed = seed
        self.posts = posts
        self.topicTags = topicTags
        self.names = names
    }
}

/// What one turn of the writer came to: a scene, or the reason there is none.
public enum SceneOutcome: Sendable, Equatable {
    /// No scene; the turn is skipped.
    case skipped(SceneSkipReason)
    /// A checked scene, ready for the engine to time and store.
    case written(WrittenScene)
}
