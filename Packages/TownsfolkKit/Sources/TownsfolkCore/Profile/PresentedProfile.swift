import Foundation

/// The profile popover open in the window: whose post it is anchored to, and what it shows.
public struct PresentedProfile: Sendable, Equatable {
    /// The post whose author's name the popover is anchored to.
    public let postID: Post.ID
    /// What it shows.
    public let profile: ResidentProfile
}
