import Foundation

/// What the store adds to a scene's prompt (REQ-003): recent posts, ongoing events, and
/// names you brought up — all three already without anything left out (#11). The town and
/// the residents come from the caller instead, so founding can write its first scene
/// before anything is stored.
///
/// Read once per turn; an item left out mid-turn is dropped here too, so the next seed's
/// prompt no longer carries it.
struct SceneContext {
    /// The recent window, newest first.
    private(set) var recentPosts: [Post]
    /// Events still going on, earliest first.
    let events: [TownEvent]
    /// Names you brought up, most recently mentioned first.
    private(set) var interests: [Interest]

    /// Reads the context for a scene written at `date`, taking at most `limit` recent
    /// posts.
    static func read(
        from store: TownStore,
        at date: Date,
        limit: Int,
    ) async throws(TownStoreError) -> Self {
        let recent = try await store.recentPosts(before: date, limit: limit)
        let ongoing = try await store.ongoingEvents()
        let names = try await store.interests()
        return Self(recentPosts: recent, events: ongoing, interests: names)
    }

    /// Drops a post that was just left out.
    mutating func leaveOut(post id: Post.ID) {
        recentPosts.removeAll { $0.id == id }
    }

    /// Drops a name that was just left out.
    mutating func leaveOut(name id: Interest.ID) {
        interests.removeAll { $0.id == id }
    }
}
