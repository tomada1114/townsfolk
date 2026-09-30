import Foundation

/// The id of one stored town value — `Resident.ID`, `Post.ID`, and so on. `Entity` only
/// tags the type, so a post's id can never be passed where a resident's is expected.
///
/// UUID-backed so Core can mint ids and link a scene's posts, a reply, or a move to its
/// resident before the store has written anything.
public struct EntityID<Entity>: Hashable, Sendable {
    /// The UUID the store keeps.
    public let rawValue: UUID

    /// Wraps a UUID the store read back.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// A fresh id. An id carries no meaning beyond identity, so drawing it from the
    /// system is not the kind of randomness a test needs to control.
    public init() {
        rawValue = UUID()
    }
}
