/// Your name in the town — the one thing founding asks (requirements §3.1, §3.10). A
/// type rather than a `String` so a name that reached the settings or the timeline has
/// already been trimmed and checked.
public struct DisplayName: Sendable, Hashable {
    /// The name, trimmed at both ends.
    public let value: String

    /// Trims `text` at both ends and accepts it only within
    /// `tuning.founding.displayNameLength` characters.
    /// - Throws: ``TownValueError`` naming ``TownValueError/Field/displayName``.
    public init(_ text: String, tuning: Tuning = .default) throws(TownValueError) {
        value = try TextRule.validated(
            text,
            .displayName,
            length: tuning.founding.displayNameLength,
            singleLine: false,
        )
    }
}
