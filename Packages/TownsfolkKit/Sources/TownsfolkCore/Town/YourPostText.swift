/// The text of a post you write — one line, like the composer (requirements §3.5).
/// A type rather than a `String` so the composer and ``Post`` check it the same way.
public struct YourPostText: Sendable, Hashable {
    /// The text, trimmed at both ends.
    public let value: String

    /// Trims `text` at both ends and accepts it only if it is one line within
    /// `tuning.yourPost.yourPostLength` characters.
    /// - Throws: ``TownValueError`` naming ``TownValueError/Field/postText``.
    public init(_ text: String, tuning: Tuning = .default) throws(TownValueError) {
        value = try TextRule.validated(
            text,
            .postText,
            length: tuning.yourPost.yourPostLength,
            singleLine: true,
        )
    }
}
