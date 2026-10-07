import Foundation

/// How the store writes a `Date`: whole milliseconds since 1970 UTC, so two stored times
/// compare exactly and a keyset cursor never skips or repeats a row. Part of the file
/// format (`docs/architecture.md` › What is contract and what is private).
enum StoredTime {
    private static let millisecondsPerSecond = 1_000.0

    /// `date` to the nearest millisecond.
    /// - Throws: ``TownStoreError/dateOutOfRange`` for a date no `Int64` count of
    ///   milliseconds can hold, rather than trapping on the conversion.
    static func milliseconds(_ date: Date) throws(TownStoreError) -> Int64 {
        let scaled = (date.timeIntervalSince1970 * millisecondsPerSecond).rounded()
        guard let milliseconds = Int64(exactly: scaled) else {
            throw .dateOutOfRange
        }
        return milliseconds
    }

    /// The date `milliseconds` stands for.
    static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / millisecondsPerSecond)
    }
}
