/// A step of the town that ``TownStore`` committed, announced on
/// ``TownStore/changes()`` so the timeline and the status line follow the store without
/// polling. A step that rolled back is never announced.
///
/// Each committed step announces exactly one change, naming the step — not one per thing
/// it wrote. A move also starts its event, and a scene may move the next due time, yet
/// they announce only ``moveRecorded(_:)`` and ``sceneStored(posts:)``. A subscriber
/// therefore re-reads what it shows on any change, rather than waiting for the case
/// that names one effect.
public enum TownStoreChange: Sendable, Equatable {
    /// An event ended.
    case eventEnded(TownEvent.ID)
    /// An event started on its own (``TownStore/startEvent(_:)``).
    case eventStarted(TownEvent.ID)
    /// Everything was deleted; the stream finishes after this.
    case everythingDeleted
    /// A town was founded, with its residents, first event, first scene, and schedule.
    case founded
    /// An interest was marked excluded from later contexts.
    case interestExcluded(Interest.ID)
    /// When the town last ran was recorded.
    case lastRanChanged
    /// A resident moved in or out, with the event recording it.
    case moveRecorded(Resident.ID)
    /// The next ordinary scene's due time changed alone — a skipped turn.
    case nextOrdinarySceneDueChanged
    /// Pending responses were added or dropped.
    case pendingResponsesChanged
    /// A post was marked excluded from later contexts.
    case postExcluded(Post.ID)
    /// A scene was stored — its posts, in the order given, with everything else the
    /// scene changed.
    case sceneStored(posts: [Post.ID])
    /// Your post was stored, including any responses scheduled atomically with it.
    case yourPostStored(Post.ID)
}
