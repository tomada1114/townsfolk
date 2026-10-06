/// A step of the town that ``TownStore`` committed, announced on
/// ``TownStore/changes()`` so the timeline and the status line follow the store without
/// polling. A step that rolled back is never announced.
public enum TownStoreChange: Sendable, Equatable {
    /// An event ended.
    case eventEnded(TownEvent.ID)
    /// An event started.
    case eventStarted(TownEvent.ID)
    /// Everything was deleted; the stream finishes after this.
    case everythingDeleted
    /// A town was founded, with its residents, first event, first scene, and schedule.
    case founded
    /// An interest was marked excluded from later contexts.
    case interestExcluded(Interest.ID)
    /// When the town last ran was recorded.
    case lastRanChanged
    /// A resident moved in or out.
    case moveRecorded(Resident.ID)
    /// The next ordinary scene's due time changed alone — a skipped turn.
    case nextOrdinarySceneDueChanged
    /// Pending responses were added or dropped.
    case pendingResponsesChanged
    /// A post was marked excluded from later contexts.
    case postExcluded(Post.ID)
    /// A scene's posts were stored, in the order given.
    case sceneStored(posts: [Post.ID])
    /// Your post was stored.
    case yourPostStored(Post.ID)
}
