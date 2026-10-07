/// One row of the timeline: a post, or an event (moves and the founding row included).
public enum TimelineEntry: Sendable, Equatable {
    /// An event row, placed at the event's start.
    case event(TownEvent)
    /// A post, yours or a resident's — shown even when excluded from later contexts.
    case post(Post)
}

/// Where the next older page starts: just below the last entry of the page that handed
/// it out. Opaque, so a caller can only pass back what a page gave it.
public struct TimelineCursor: Sendable, Hashable {
    /// The last entry's time, in stored milliseconds.
    let time: Int64
    /// The last entry's id, as stored.
    let id: String
}

/// One page of the timeline, newest first.
public struct TimelinePage: Sendable, Equatable {
    /// The entries, newest first by time, then by id.
    public let entries: [TimelineEntry]
    /// The cursor for the next older page, or `nil` when no older entry remains.
    public let older: TimelineCursor?
}
