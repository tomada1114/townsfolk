import Foundation

/// Town › Show Profile (⌘I) asking the selected post's row to open its author's profile,
/// anchored to the name in its header. A serial of its own makes a second ask of the same
/// post a new request.
public struct ProfileRequest: Sendable, Equatable {
    /// Counts up from 1 per timeline.
    public let serial: Int
    /// The post whose author's profile opens.
    public let postID: Post.ID
}
