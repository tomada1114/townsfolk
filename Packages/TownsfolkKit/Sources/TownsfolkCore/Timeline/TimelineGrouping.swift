import Foundation

/// The timeline's grouping rules (`docs/product/ux-flows.md:70-78`): one group per scene,
/// its posts oldest first; one group per post of yours; a quote line above a group whose
/// first post replies outside it; and groups and event rows newest first by their first
/// post or the event's start — a group above an event row at the same moment, so a just
/// founded town shows its first scene above "You moved to {town}.".
struct TimelineGrouping {
    /// The rows, and the posts a quote line needs that `lookup` did not know.
    struct Result {
        var items: [TimelineItem]
        var missingQuotes: Set<Post.ID>
    }

    /// Where a row sorts: newest first, then a group before an event row, then by id so
    /// equal times always fall the same way.
    private struct SortKey: Comparable {
        let time: Date
        let isGroup: Bool
        let id: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.time != rhs.time {
                return lhs.time < rhs.time
            }
            if lhs.isGroup != rhs.isGroup {
                return !lhs.isGroup
            }
            return lhs.id < rhs.id
        }
    }

    var residentNames: [Resident.ID: String]
    var displayName: DisplayName?
    var locale: Locale
    var eventSymbols: [EventKindID: String]

    /// Your name as a quote line shows it: your current name, or "You" with none stored.
    private var yourName: String {
        if let displayName {
            return displayName.value
        }
        var resource = TimelineWording.you
        resource.locale = locale
        return String(localized: resource)
    }

    private static func isOlder(_ lhs: Post, _ rhs: Post) -> Bool {
        if lhs.happenedAt != rhs.happenedAt {
            return lhs.happenedAt < rhs.happenedAt
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    /// Lays out `posts` and `events`, finding a quoted post with `lookup`.
    func items(
        posts: [Post],
        events: [TownEvent],
        lookup: (Post.ID) -> Post?,
    ) -> Result {
        var groups: [TimelineItem.Key: [Post]] = [:]
        for post in posts {
            let id: TimelineItem.Key = post.sceneID.map { .scene($0) } ?? .yourPost(post.id)
            groups[id, default: []].append(post)
        }
        var missing: Set<Post.ID> = []
        var rows: [(key: SortKey, item: TimelineItem)] = []
        rows.reserveCapacity(groups.count + events.count)
        for (id, members) in groups {
            let ordered = members.sorted(by: Self.isOlder)
            guard let first = ordered.first else {
                continue
            }
            let quote = quote(for: ordered, lookup: lookup, missing: &missing)
            let group = TimelinePostGroup(id: id, quote: quote, posts: ordered.map(row(for:)))
            let key = SortKey(
                time: first.happenedAt,
                isGroup: true,
                id: first.id.rawValue.uuidString,
            )
            rows.append((key, .group(group)))
        }
        for event in events {
            let row = TimelineEventRow(
                id: event.id,
                text: event.description,
                startsAt: event.startsAt,
                symbol: eventSymbols[event.kind],
            )
            let key = SortKey(
                time: event.startsAt,
                isGroup: false,
                id: event.id.rawValue.uuidString,
            )
            rows.append((key, .event(row)))
        }
        rows.sort { $0.key > $1.key }
        return Result(items: rows.map(\.item), missingQuotes: missing)
    }

    /// The quote line of a group whose first post replies to a post outside it.
    private func quote(
        for ordered: [Post],
        lookup: (Post.ID) -> Post?,
        missing: inout Set<Post.ID>,
    ) -> TimelineQuote? {
        guard let target = ordered.first?.replyTarget,
              !ordered.contains(where: { $0.id == target })
        else {
            return nil
        }
        guard let quoted = lookup(target) else {
            missing.insert(target)
            return nil
        }
        return TimelineQuote(postID: quoted.id, name: name(of: quoted.author), text: quoted.text)
    }

    private func row(for post: Post) -> TimelinePost {
        var residentID: Resident.ID?
        if case let .resident(id) = post.author {
            residentID = id
        }
        let author: TimelinePost.Author = switch post.author {
        case let .resident(id):
            .resident(residentNames[id] ?? "")

        case .you:
            .you(name: displayName?.value, marker: TimelineWording.youMarker)
        }
        return TimelinePost(
            id: post.id,
            author: author,
            residentID: residentID,
            text: post.text,
            happenedAt: post.happenedAt,
        )
    }

    private func name(of author: Post.Author) -> String {
        switch author {
        case let .resident(id):
            residentNames[id] ?? ""

        case .you:
            yourName
        }
    }
}
