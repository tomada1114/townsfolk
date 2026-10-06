import Foundation

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

    /// The `Locale` this language's strings resolve in and its formatters use — the
    /// language alone, with no region, so a Japanese UI on a Mac set to another region
    /// still formats as Japanese.
    public var locale: Locale {
        switch self {
        case .english:
            Locale(identifier: "en")

        case .japanese:
            Locale(identifier: "ja")
        }
    }

    /// The language's name in that language — "English", and Japanese written in
    /// Japanese — as a language picker offers it, whatever the app's language is. From
    /// Foundation rather than the String Catalog, since it is never translated.
    public var nativeName: String {
        locale.localizedString(forLanguageCode: rawValue) ?? rawValue
    }

    /// `resource`, set to resolve in this language whatever the process's preferred
    /// languages are.
    ///
    /// The one way a Core string reaches the app's language (ADR-0007): the process's
    /// languages are fixed at launch, while the in-app setting switches at once. A
    /// resource's `locale` defaults to `.current` when it is built, so this replaces it
    /// after the declaration rather than at it — every `LocalizedStringResource(…)` call
    /// stays the literal-key declaration `LocalizationTests` scans.
    public func localized(_ resource: LocalizedStringResource) -> LocalizedStringResource {
        var resource = resource
        resource.locale = locale
        return resource
    }
}
