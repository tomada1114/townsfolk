import Foundation

/// A name you brought up in a post — what you study, a comic you read — kept for the
/// town's life so residents may talk about it, take it up, or be seeded from it
/// (requirements §3.5, §5).
public struct Interest: Identifiable, Sendable, Equatable {
    /// The longest term, in characters (requirements.md:399).
    public static let termMaxLength = 40

    /// The interest's id.
    public let id: EntityID<Self>
    /// The name as you wrote it, trimmed at both ends.
    public let term: String
    /// When you first brought it up.
    public let firstMentionedAt: Date
    /// When it was last brought up; never before ``firstMentionedAt``.
    public let lastMentionedAt: Date
    /// How many times it has been brought up — at least once, or it would not be kept.
    public let mentions: Int
    /// The posts it was taken from.
    public let sourcePosts: [EntityID<Post>]

    /// Creates an interest, trimming `term` at both ends.
    /// - Throws: ``TownValueError`` for a term blank or over ``termMaxLength``, fewer than
    ///   one mention, or a last mention before the first.
    public init(
        id: EntityID<Self>,
        term: String,
        firstMentionedAt: Date,
        lastMentionedAt: Date,
        mentions: Int,
        sourcePosts: [EntityID<Post>] = [],
    ) throws(TownValueError) {
        self.term = try TextRule.validated(
            term,
            .term,
            length: 1 ... Self.termMaxLength,
            singleLine: false,
        )
        guard mentions >= 1 else {
            throw .tooFew(.mentions, minimum: 1)
        }
        guard lastMentionedAt >= firstMentionedAt else {
            throw .outOfOrder(.lastMentionedAt)
        }
        self.id = id
        self.firstMentionedAt = firstMentionedAt
        self.lastMentionedAt = lastMentionedAt
        self.mentions = mentions
        self.sourcePosts = sourcePosts
    }
}
