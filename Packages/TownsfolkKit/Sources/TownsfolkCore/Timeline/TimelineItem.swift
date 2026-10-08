import Foundation

/// One scene (1–3 posts) or one post of yours, joined by a thread line when it is a scene
/// (`docs/product/ux-flows.md:70-72`).
public struct TimelinePostGroup: Identifiable, Sendable, Equatable {
    public let id: TimelineItem.Key
    /// The older post this group replies to, when its first post replies outside it.
    public let quote: TimelineQuote?
    /// The posts shown so far, oldest first: a scene being revealed grows at the bottom.
    public let posts: [TimelinePost]

    /// Whether the group is a scene, which a thread line joins; a post of yours stands
    /// alone without one.
    public var isScene: Bool {
        if case .scene = id {
            return true
        }
        return false
    }
}

/// One post in a group: its author's name, its text, and when it happened.
public struct TimelinePost: Identifiable, Sendable, Equatable {
    /// The name a post's header shows.
    public enum Author: Sendable, Equatable {
        /// A resident's name, as the town invented it — not wording, so it is not looked
        /// up in the catalog.
        case resident(String)
        /// Your current name — `nil` with none stored — followed by `marker`, "(you)".
        case you(name: String?, marker: LocalizedStringResource)
    }

    public let id: Post.ID
    /// The name in the header.
    public let author: Author
    /// The resident who wrote it, or `nil` for a post of yours.
    public let residentID: Resident.ID?
    /// What the post says; it always wraps and is never cut short.
    public let text: String
    /// When it happened, shown as a relative time.
    public let happenedAt: Date

    /// Whether the post is yours.
    public var isYours: Bool {
        if case .you = author {
            return true
        }
        return false
    }
}

/// The one-line quote of the older post a group replies to (`↩ Name: "text…"`).
public struct TimelineQuote: Sendable, Equatable {
    /// The quoted post.
    public let postID: Post.ID
    /// Its author's name — your current name, without "(you)", for a post of yours.
    public let name: String
    /// Its whole text; the view cuts it to one line.
    public let text: String
}

/// An event or a move as one line with its time; it cannot be replied to or selected.
public struct TimelineEventRow: Identifiable, Sendable, Equatable {
    public let id: TownEvent.ID
    /// The event's one-line description.
    public let text: String
    /// When it started, shown as a relative time.
    public let startsAt: Date
    /// The SF Symbol its kind names in the seed tables, or `nil` for a kind they do not
    /// list — the row then shows its text alone.
    public let symbol: String?
}

/// A polite VoiceOver announcement the timeline asks the view to post. Each has a serial
/// of its own, so two announcements with the same words are still two.
public struct TimelineAnnouncement: Sendable, Equatable {
    /// Counts up from 1 per timeline.
    public let serial: Int
    /// What VoiceOver says.
    public let text: LocalizedStringResource
}

/// One row of the timeline as the town window lays it out, top to bottom: a group of
/// posts, or an event row (ux-flows S1). Newest first by the group's first post or the
/// event's start.
public enum TimelineItem: Identifiable, Sendable, Equatable {
    /// An event or a move, set apart from the groups.
    case event(TimelineEventRow)
    /// One scene, or one post of yours.
    case group(TimelinePostGroup)

    /// Which row this is, stable while it grows: a scene keeps its key as its posts
    /// appear. It is the row's `id`.
    public enum Key: Hashable, Sendable {
        /// An event row.
        case event(TownEvent.ID)
        /// A group holding one scene's posts.
        case scene(SceneID)
        /// A group holding one post of yours.
        case yourPost(Post.ID)
    }

    public var id: Key {
        switch self {
        case let .event(row):
            .event(row.id)

        case let .group(group):
            group.id
        }
    }
}
