import Foundation

/// One deterministic comparison for extraction, deduplication, and stored-name merges.
enum NameTerms {
    private static let locale = Locale(identifier: "en_US_POSIX")
    static let maximumCount = 3

    static func key(_ term: String) -> String {
        term.folding(options: .caseInsensitive, locale: locale)
    }

    /// Keeps original spelling from a complete literal name, never prompt folding.
    static func validated(_ candidates: [String], in source: String) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for candidate in candidates {
            let term = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= Interest.termMaxLength,
                  let range = completeOccurrence(of: term, in: source)
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

    private static func completeOccurrence(
        of term: String,
        in source: String,
    ) -> Range<String.Index>? {
        var start = source.startIndex
        while start < source.endIndex {
            guard let range = source.range(
                of: term,
                options: [.caseInsensitive, .literal],
                range: start ..< source.endIndex,
                locale: locale,
            ) else { return nil }
            let leftIsWord = range.lowerBound > source.startIndex
                && isWordCharacter(source[source.index(before: range.lowerBound)])
            let rightIsWord = range.upperBound < source.endIndex
                && isWordCharacter(source[range.upperBound])
            if !leftIsWord, !rightIsWord {
                return range
            }
            start = source.index(after: range.lowerBound)
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.nonBaseCharacters.contains(scalar)
                || scalar.properties.generalCategory == .connectorPunctuation
        }
    }
}
