import Foundation

/// The id of one scene — the 1–3 posts one model call writes (requirements.md:161),
/// which the timeline shows as one group (`docs/product/ux-flows.md:53`). A scene is not
/// stored as a row of its own; this id is what its posts share.
public struct SceneID: Hashable, Sendable {
    /// The UUID the store keeps on each of the scene's posts.
    public let rawValue: UUID

    /// Wraps a UUID the store read back.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// A fresh id for a scene about to be written.
    public init() {
        rawValue = UUID()
    }
}
