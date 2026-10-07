import Foundation

/// Every entry the timeline has read, and where each one stands: shown, held while you
/// are scrolled away, or waiting for its time (requirements §3.2: a scene's posts appear
/// one at a time, at the times they were stored with).
///
/// An entry is taken once: reading it again — the newest page re-read on a change, a
/// page overlapping one already loaded — changes nothing.
struct TimelineLog {
    /// An entry's identity across both tables.
    enum Key: Hashable {
        case event(TownEvent.ID)
        case post(Post.ID)
    }

    private(set) var posts: [Post.ID: Post] = [:]
    private(set) var events: [TownEvent.ID: TownEvent] = [:]
    /// The entries the rows show.
    private(set) var shown: Set<Key> = []
    /// Entries whose time has come while you were scrolled away, oldest first.
    private(set) var held: [Key] = []
    /// Entries whose time has not come yet.
    private var waiting: Set<Key> = []

    var isEmpty: Bool {
        posts.isEmpty && events.isEmpty
    }

    /// The posts the rows show.
    var shownPosts: [Post] {
        shown.compactMap { key in
            if case let .post(id) = key {
                return posts[id]
            }
            return nil
        }
    }

    /// The event rows the rows show.
    var shownEvents: [TownEvent] {
        shown.compactMap { key in
            if case let .event(id) = key {
                return events[id]
            }
            return nil
        }
    }

    /// How many held entries are posts — what the new-posts pill counts.
    var heldPostCount: Int {
        held.count(where: Self.isPost)
    }

    /// When the next waiting entry is due, or `nil` when none waits.
    var nextDue: Date? {
        waiting.compactMap(time(of:)).min()
    }

    private static func isPost(_ key: Key) -> Bool {
        if case .post = key {
            return true
        }
        return false
    }

    /// Takes entries loaded as a page or at launch: those whose time has come are shown
    /// at once, with no motion; the rest wait.
    mutating func load(_ entries: [TimelineEntry], now: Date) {
        for key in insertNew(entries) {
            if isDue(key, now: now) {
                shown.insert(key)
            } else {
                waiting.insert(key)
            }
        }
    }

    /// Takes entries that arrived while the timeline runs, returning those whose time
    /// has come, oldest first, for the caller to show or hold; the rest wait.
    mutating func arrive(_ entries: [TimelineEntry], now: Date) -> [Key] {
        var due: [Key] = []
        for key in insertNew(entries) {
            if isDue(key, now: now) {
                due.append(key)
            } else {
                waiting.insert(key)
            }
        }
        return sortedByTime(due)
    }

    /// Takes the waiting entries whose time has come, oldest first.
    mutating func takeDue(now: Date) -> [Key] {
        let due = waiting.filter { isDue($0, now: now) }
        waiting.subtract(due)
        return sortedByTime(Array(due))
    }

    mutating func show(_ keys: [Key]) {
        shown.formUnion(keys)
    }

    mutating func hold(_ keys: [Key]) {
        held += keys
    }

    /// Takes every held entry, oldest first.
    mutating func releaseHeld() -> [Key] {
        defer { held = [] }
        return held
    }

    /// Forgets everything: the town was deleted.
    mutating func removeAll() {
        self = Self()
    }

    func time(of key: Key) -> Date? {
        switch key {
        case let .event(id):
            events[id]?.startsAt

        case let .post(id):
            posts[id]?.happenedAt
        }
    }

    private func isDue(_ key: Key, now: Date) -> Bool {
        guard let time = time(of: key) else {
            return false
        }
        return time <= now
    }

    private func sortedByTime(_ keys: [Key]) -> [Key] {
        keys.sorted { (time(of: $0) ?? .distantPast) < (time(of: $1) ?? .distantPast) }
    }

    /// Stores the entries not read before and returns their keys.
    private mutating func insertNew(_ entries: [TimelineEntry]) -> [Key] {
        var added: [Key] = []
        for entry in entries {
            switch entry {
            case let .event(event):
                guard events[event.id] == nil else {
                    continue
                }
                events[event.id] = event
                added.append(.event(event.id))

            case let .post(post):
                guard posts[post.id] == nil else {
                    continue
                }
                posts[post.id] = post
                added.append(.post(post.id))
            }
        }
        return added
    }
}
