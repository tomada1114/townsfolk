/// The kind of a ``TownEvent``: an id naming an entry in the seed tables' event kinds
/// (ADR-0007), which carry its symbol, wording, and duration. A `String` so the tables
/// can grow without a code change.
public struct EventKindID: RawRepresentable, Hashable, Sendable {
    /// A resident moved in (requirements.md:262); the event names the resident.
    public static let moveIn = Self(rawValue: "move-in")
    /// A resident moved out (requirements.md:262); the event names the resident.
    public static let moveOut = Self(rawValue: "move-out")
    /// The first row of every town, "You moved to {town}." (`docs/product/ux-flows.md:211`).
    public static let founding = Self(rawValue: "founding")

    /// The id exactly as the seed tables spell it.
    public let rawValue: String

    /// Wraps an id from the seed tables or the store.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
