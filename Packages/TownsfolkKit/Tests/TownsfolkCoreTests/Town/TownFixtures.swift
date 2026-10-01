import Foundation

/// Fixed inputs the Town suites share: a moment that never moves, and text of an exact
/// character count, so a boundary test states its expected length as a literal.
enum TownFixtures {
    /// 2026-10-02T09:00:00Z.
    static let movedIn = Date(timeIntervalSince1970: movedInSeconds)

    /// One hour after ``movedIn``.
    static let anHourLater = movedIn.addingTimeInterval(anHour)

    /// One hour before ``movedIn``.
    static let anHourEarlier = movedIn.addingTimeInterval(-anHour)

    /// HIRAGANA LETTER A — one `Character`, written as an escape so the source stays ASCII.
    static let hiragana = "\u{3042}"

    /// A waving hand with a skin-tone modifier: two scalars, one `Character`.
    static let wavingHand = "\u{1F44B}\u{1F3FD}"

    private static let movedInSeconds: TimeInterval = 1_790_931_600
    private static let anHour: TimeInterval = 3_600

    /// `count` copies of "a".
    static func text(_ count: Int) -> String {
        text(count, of: "a")
    }

    /// `count` copies of `unit`.
    static func text(_ count: Int, of unit: String) -> String {
        String(repeating: unit, count: count)
    }
}
