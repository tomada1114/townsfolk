/// A bounded counter — the template's placeholder domain model.
///
/// Exists to demonstrate the template's testing conventions: a typed error with
/// payload, boundary clamping, and value semantics.
public struct Counter: Equatable, Sendable {
    /// Errors thrown by ``Counter``.
    public enum CounterError: Error, Equatable {
        case valueOutOfRange(value: Int, range: ClosedRange<Int>)
    }

    /// The inclusive bounds the counter value is confined to.
    public let range: ClosedRange<Int>
    /// The current value, always within ``range``.
    public private(set) var value: Int

    /// Whether the counter sits at its upper bound.
    public var isAtMax: Bool {
        value == range.upperBound
    }

    /// Whether the counter sits at its lower bound.
    public var isAtMin: Bool {
        value == range.lowerBound
    }

    /// Creates a counter, validating that `value` lies within `range`.
    /// - Throws: ``CounterError/valueOutOfRange(value:range:)`` when it does not.
    public init(value: Int = 0, range: ClosedRange<Int> = -100 ... 100) throws {
        guard range.contains(value) else {
            throw CounterError.valueOutOfRange(value: value, range: range)
        }
        self.value = value
        self.range = range
    }

    /// Increments by one, clamping at `range.upperBound`.
    public mutating func increment() {
        value = min(value + 1, range.upperBound)
    }

    /// Decrements by one, clamping at `range.lowerBound`.
    public mutating func decrement() {
        value = max(value - 1, range.lowerBound)
    }

    /// Resets to 0 when the range contains it, otherwise to `range.lowerBound`.
    public mutating func reset() {
        value = range.contains(0) ? 0 : range.lowerBound
    }
}
