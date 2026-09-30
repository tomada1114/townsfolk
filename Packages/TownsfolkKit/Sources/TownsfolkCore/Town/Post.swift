import Foundation

/// One line on the board — a resident's, written in a scene, or yours (requirements §3.2,
/// §3.5, §5).
public struct Post: Identifiable, Sendable, Equatable {
    /// Who wrote a post.
    public enum Author: Sendable, Hashable {
        /// A resident, by id.
        case resident(EntityID<Resident>)
        /// You. No name is stored: a display-name change shows everywhere
        /// (requirements.md:334).
        case you
    }

    /// Why a resident's post was written (requirements.md:397).
    public enum Origin: Sendable, Equatable, CaseIterable {
        /// A scene written after a pause (§3.7).
        case catchUp
        /// A scene about an event (§3.6).
        case event
        /// A scene from the ordinary pace (§3.4).
        case ordinary
        /// A response scene to one of your posts (§3.5).
        case response
    }

    /// The most topic tags on one post (requirements.md:397).
    public static let maxTopicTags = 3
    /// The longest topic tag, in characters (requirements.md:397).
    public static let topicTagMaxLength = 40

    /// The post's id — minted before storing, so a scene's replies can point at it.
    public let id: EntityID<Self>
    /// Who wrote it.
    public let author: Author
    /// What it says, trimmed at both ends.
    public let text: String
    /// When it happened in town time — spread across a pause for catch-up posts.
    public let happenedAt: Date
    /// The language the text is written in; earlier posts keep theirs when the setting
    /// changes (requirements.md:333).
    public let language: TownLanguage
    /// The post this one replies to, if any.
    public let replyTarget: EntityID<Self>?
    /// What the post is about, feeding the status line (§3.3).
    public let topicTags: [String]
    /// Why a resident wrote it; `nil` exactly when ``author`` is ``Author/you``.
    public let origin: Origin?
    /// The scene it belongs to; `nil` exactly when ``author`` is ``Author/you``, whose
    /// post is a group of its own (`docs/product/ux-flows.md:53`).
    public let sceneID: SceneID?

    /// Creates a post, trimming its text and tags at both ends.
    ///
    /// A resident's text is 1 to `tuning.timeline.residentPostMaxLength[language]`
    /// characters; yours follows ``YourPostText``. A resident's post needs an `origin` and
    /// a `sceneID`; yours takes neither.
    /// - Throws: ``TownValueError`` for text or tags outside their limits, or an origin or
    ///   scene missing or unexpected for the author.
    public init(
        id: EntityID<Self>,
        author: Author,
        text: String,
        happenedAt: Date,
        language: TownLanguage,
        replyTarget: EntityID<Self>? = nil,
        topicTags: [String] = [],
        origin: Origin? = nil,
        sceneID: SceneID? = nil,
        tuning: Tuning = .default,
    ) throws(TownValueError) {
        switch author {
        case .resident:
            guard origin != nil else {
                throw .required(.origin)
            }
            guard sceneID != nil else {
                throw .required(.sceneID)
            }
            self.text = try TextRule.validated(
                text,
                .postText,
                length: 1 ... tuning.timeline.residentPostMaxLength[language],
                singleLine: false,
            )

        case .you:
            guard origin == nil else {
                throw .notAllowed(.origin)
            }
            guard sceneID == nil else {
                throw .notAllowed(.sceneID)
            }
            self.text = try YourPostText(text, tuning: tuning).value
        }
        self.topicTags = try Self.validatedTags(topicTags)
        self.id = id
        self.author = author
        self.happenedAt = happenedAt
        self.language = language
        self.replyTarget = replyTarget
        self.origin = origin
        self.sceneID = sceneID
    }

    private static func validatedTags(_ tags: [String]) throws(TownValueError) -> [String] {
        try TextRule.checkCount(tags.count, .topicTags, allowed: 0 ... maxTopicTags)
        var valid: [String] = []
        for tag in tags {
            try valid.append(
                TextRule.validated(
                    tag,
                    .topicTag,
                    length: 1 ... topicTagMaxLength,
                    singleLine: false,
                ),
            )
        }
        return valid
    }
}
