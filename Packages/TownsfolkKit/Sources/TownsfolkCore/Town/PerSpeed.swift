/// One value per ``Speed`` — an interval or a scale that differs by speed. A struct
/// rather than a dictionary so a lookup can never miss.
public struct PerSpeed<Value: Sendable & Equatable>: Sendable, Equatable {
    /// The value at ``Speed/fast``.
    public var fast: Value
    /// The value at ``Speed/normal``.
    public var normal: Value
    /// The value at ``Speed/slow``.
    public var slow: Value

    /// Creates one value per speed; a test builds a smaller one to reach a boundary.
    public init(fast: Value, normal: Value, slow: Value) {
        self.fast = fast
        self.normal = normal
        self.slow = slow
    }

    /// The value for `speed`.
    public subscript(speed: Speed) -> Value {
        switch speed {
        case .fast:
            fast

        case .normal:
            normal

        case .slow:
            slow
        }
    }
}
