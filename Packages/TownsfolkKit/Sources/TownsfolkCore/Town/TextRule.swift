import Foundation

/// The checks every town value shares, so a text limit and a list limit mean the same
/// thing on every field: text is trimmed at both ends, and a character is a `Character`
/// (a grapheme cluster), so a kana and an emoji each count one.
enum TextRule {
    /// Any length from one character up — for fields the documents require but do not cap.
    static let uncapped = 1 ... Int.max

    /// `raw` trimmed, or the first limit it breaks: empty, then a line break when
    /// `singleLine`, then too short, then too long.
    static func validated(
        _ raw: String,
        _ field: TownValueError.Field,
        length: ClosedRange<Int>,
        singleLine: Bool,
    ) throws(TownValueError) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw .empty(field)
        }
        if singleLine, text.contains(where: \.isNewline) {
            throw .multipleLines(field)
        }
        guard text.count >= length.lowerBound else {
            throw .tooShort(field, minimum: length.lowerBound)
        }
        guard text.count <= length.upperBound else {
            throw .tooLong(field, limit: length.upperBound)
        }
        return text
    }

    /// `raw` trimmed, or ``TownValueError/empty(_:)`` when nothing is left.
    static func nonEmpty(
        _ raw: String,
        _ field: TownValueError.Field,
    ) throws(TownValueError) -> String {
        try validated(raw, field, length: uncapped, singleLine: false)
    }

    /// Throws when `count` entries fall outside `allowed`.
    static func checkCount(
        _ count: Int,
        _ field: TownValueError.Field,
        allowed: ClosedRange<Int>,
    ) throws(TownValueError) {
        guard count >= allowed.lowerBound else {
            throw .tooFew(field, minimum: allowed.lowerBound)
        }
        guard count <= allowed.upperBound else {
            throw .tooMany(field, limit: allowed.upperBound)
        }
    }
}
