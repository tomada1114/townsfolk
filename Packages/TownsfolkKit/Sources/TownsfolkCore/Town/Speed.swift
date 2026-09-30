/// How often the town writes a scene — the one lever that trades liveliness for heat and
/// battery (requirements §3.4).
///
/// The raw values are what `settings.speed` stores (ADR-0004), so they are contract:
/// renaming one resets every user's choice.
public enum Speed: String, Sendable, CaseIterable {
    /// A scene about every minute.
    case fast
    /// A scene about every 6 minutes — the default (requirements.md:202).
    case normal
    /// A scene about every 30 minutes.
    case slow

    /// The speed a new install starts at (requirements.md:202, :335).
    public static let `default` = Self.normal
}
