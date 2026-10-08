import Foundation

/// One deterministic comparison for extraction, deduplication, and stored-name merges.
enum NameTerms {
    private static let locale = Locale(identifier: "en_US_POSIX")
    static let maximumCount = 3

    static func key(_ term: String) -> String {
        term.folding(options: .caseInsensitive, locale: locale)
    }

    /// Keeps the original source spelling and literal line breaks, never prompt folding.
    static func validated(_ candidates: [String], in source: String) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for candidate in candidates {
            let term = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= Interest.termMaxLength,
                  let range = source.range(
                      of: term,
                      options: [.caseInsensitive, .literal],
                      locale: locale,
                  )
            else { continue }
            let original = String(source[range])
            guard original.count <= Interest.termMaxLength,
                  seen.insert(key(original)).inserted else { continue }
            names.append(original)
            if names.count == maximumCount {
                break
            }
        }
        return names
    }
}
