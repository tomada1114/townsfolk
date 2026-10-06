import Foundation

/// The subset of the String Catalog format `LocalizationTests` reads: its source language
/// and, per key, each language's single string. A plural or device-varied entry has
/// `variations` instead of a `stringUnit`.
struct StringCatalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogEntry]
}

/// One key's entry. An entry keyed by its own English text may carry no `localizations`
/// at all, which decodes as none rather than failing the whole catalog.
struct CatalogEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case localizations
    }

    let localizations: [String: CatalogLocalization]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localizations = try container.decodeIfPresent(
            [String: CatalogLocalization].self,
            forKey: .localizations,
        ) ?? [:]
    }
}

struct CatalogLocalization: Decodable {
    struct StringUnit: Decodable {
        let state: String?
        let value: String
    }

    let stringUnit: StringUnit?
}

/// Holds every key's translation to the source: present, non-empty, marked `translated`,
/// and taking the same arguments. ADR-0007 leaves translation to the implementing agent
/// with no separate review, so this is what notices a key that never got its Japanese.
enum CatalogTranslationCheck {
    /// One sentence per problem, each naming its key, sorted by key; empty when every
    /// key's `language` value is complete.
    static func problems(in catalog: StringCatalog, language: String) -> [String] {
        catalog.strings.keys.sorted().compactMap { key in
            let localizations = catalog.strings[key]?.localizations ?? [:]
            guard let unit = localizations[language]?.stringUnit,
                  unit.state == "translated",
                  !unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return "\(key) has no translated \(language) value"
            }
            let source = localizations[catalog.sourceLanguage]?.stringUnit?.value ?? ""
            let expected = formatSpecifiers(in: source)
            let actual = formatSpecifiers(in: unit.value)
            guard actual == expected else {
                return "\(key)'s \(language) value takes \(describe(actual)) where its "
                    + "\(catalog.sourceLanguage) takes \(describe(expected))"
            }
            return nil
        }
    }

    /// The argument each format specifier in `format` consumes, by its 1-based position:
    /// `%@ %lld` and `%2$lld %1$@` both read as `[1: "@", 2: "lld"]`, so a translation
    /// may reorder its arguments but not change their number or type. `%%` is a literal.
    static func formatSpecifiers(in format: String) -> [Int: String] {
        let specifier = /%(?:(\d+)\$)?(ll[diux]|l[diux]|[diuxX@fgecs])/
        var byPosition: [Int: String] = [:]
        var next = 1
        for match in format.replacing("%%", with: "").matches(of: specifier) {
            let position = match.output.1.flatMap { Int($0) } ?? next
            byPosition[position] = String(match.output.2)
            next = position + 1
        }
        return byPosition
    }

    private static func describe(_ specifiers: [Int: String]) -> String {
        let list = specifiers.keys.sorted().map { "%\($0)$\(specifiers[$0] ?? "")" }
        return list.isEmpty ? "no arguments" : list.joined(separator: " ")
    }
}
