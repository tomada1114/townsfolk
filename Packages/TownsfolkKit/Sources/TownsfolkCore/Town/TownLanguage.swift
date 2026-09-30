/// The language the town is written in — picked at founding and switchable in Settings
/// (requirements §3.1, §3.10). An enum, not a `Locale`, because the model is told one of
/// exactly two languages and every per-language limit is keyed by it.
///
/// The raw values are what `settings.language` stores (ADR-0004), so they are contract:
/// renaming one resets every user's choice.
public enum TownLanguage: String, Sendable, CaseIterable {
    /// English, preselected at first run (requirements.md:135).
    case english = "en"
    /// Japanese.
    case japanese = "ja"

    /// The language a new install starts in (requirements.md:135).
    public static let `default` = Self.english
}
