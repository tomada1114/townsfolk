import Foundation

/// The composer's counter (`docs/design/ux-guidelines.md:78-80`): absent until 20
/// characters remain, then how many are left, and past the limit how many are over.
public enum ComposerCounter: Sendable, Equatable {
    /// How many characters may still be typed — 20 or fewer.
    case left(Int)
    /// How many characters too many; Return does nothing.
    case over(Int)

    /// The fewest remaining characters before the counter shows (ux-guidelines.md:78).
    static let threshold = 20

    /// "{n} left", or "{n} over".
    public var title: LocalizedStringResource {
        switch self {
        case let .left(count):
            ComposerWording.charactersLeft(count)

        case let .over(count):
            ComposerWording.charactersOver(count)
        }
    }

    /// Whether the text is over the limit: the counter is then in the primary color with
    /// `exclamationmark.triangle`, never color alone.
    public var isOver: Bool {
        if case .over = self {
            return true
        }
        return false
    }

    /// The counter for a post `length` characters long after trimming, under `limit`.
    init?(length: Int, limit: Int) {
        let remaining = limit - length
        if remaining < 0 {
            self = .over(-remaining)
        } else if remaining <= Self.threshold {
            self = .left(remaining)
        } else {
            return nil
        }
    }
}
