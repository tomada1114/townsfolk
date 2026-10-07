import Foundation
import Observation

/// The town window's timeline (ux-flows S1): the town's posts and events newest first,
/// one scene per group, read from ``TownStore`` and never written to it.
///
/// It loads the newest page, then older pages as the last row appears; follows the
/// store's committed steps; and holds a post back until its stored time comes, so a
/// scene appears one post at a time (requirements §3.2). A post that appears while the
/// timeline runs arrives live — the view fades it in under a Lamplight wash — unless you
/// are scrolled away from the top: then the rows stay as they are and the new-posts pill
/// counts what is waiting, until the pill, ⌘↑, or scrolling back up shows it.
///
/// Time, the date, and the locale come from ``TimelineEnvironment``; ``run()`` is the one
/// action that waits on them. Construction reads and writes nothing. Nothing a resident or
/// you wrote, and no name, is ever logged (`.claude/rules/swift.md` › Logging).
@MainActor
@Observable
public final class TimelineViewModel {
    /// The window's title before a town exists (`docs/product/ux-flows.md:30`): the app's
    /// name, which is not translated.
    public static let untitled = "Townsfolk"
    /// How often relative times are written afresh (ux-guidelines › Language and copy).
    static let refreshInterval = Duration.seconds(secondsPerRefresh)
    private static let secondsPerRefresh = 60

    /// The window's title: the town's name, or ``untitled`` before there is a town.
    public private(set) var title: String
    /// The rows, top to bottom.
    public private(set) var items: [TimelineItem] = []
    /// The date relative times are written against, refreshed every 60 seconds.
    public private(set) var now: Date
    /// Whether the timeline is scrolled to its top, where new rows are inserted at once.
    public private(set) var isAtTop = true
    /// How many posts arrived while you were scrolled away and wait above the rows.
    public private(set) var newPostCount = 0
    /// The post selected with the keyboard or the pointer, shown by the focus ring alone.
    public private(set) var selectedPostID: Post.ID?
    /// Whether an older page may remain: `false` once a page came back short.
    public private(set) var canLoadOlder = false
    /// The latest polite announcement for VoiceOver, or `nil` before the first.
    public private(set) var announcement: TimelineAnnouncement?
    /// Counts up each time the timeline asks the view to scroll to the top.
    public private(set) var scrollToTopRequest = 0
    /// Counts up each time the timeline asks the view to move focus to the selected post.
    public private(set) var focusRequest = 0
    /// Your name, shown with "(you)" on every post of yours.
    public private(set) var displayName: DisplayName?
    /// The posts that arrived live and have not finished fading in.
    private var liveArrivals: Set<Post.ID> = []

    @ObservationIgnored let store: TownStore?
    @ObservationIgnored let environment: TimelineEnvironment
    @ObservationIgnored private let eventSymbols: [EventKindID: String]
    @ObservationIgnored private(set) var log = TimelineLog()
    @ObservationIgnored private var residentNames: [Resident.ID: String] = [:]
    /// Posts a quote line needs that no loaded page holds, read from the store.
    @ObservationIgnored private var quoted: [Post.ID: Post] = [:]
    /// Quoted posts already asked of the store, found or not, so none is asked twice.
    @ObservationIgnored private var askedQuotes: Set<Post.ID> = []
    /// Live residents' replies whose target no loaded page holds, announced once the
    /// store is read for it — or dropped, when it is not yours or the store lacks it.
    @ObservationIgnored private var unannouncedReplies: [Post.ID] = []
    /// Quoted posts the rows need and the store has not been asked for yet.
    @ObservationIgnored private(set) var missingQuotes: Set<Post.ID> = []
    @ObservationIgnored private(set) var olderCursor: TimelineCursor?
    @ObservationIgnored var isLoadingOlder = false
    /// Counts up each time the town is deleted, so a read begun before the deletion is
    /// dropped when it returns instead of loading the old town's rows.
    @ObservationIgnored package private(set) var loadGeneration = 0
    /// The sleep ``run()`` is in, cancelled to wake it early when a new post waits.
    @ObservationIgnored var sleeper: Task<Void, Never>?

    /// Creates the timeline over `store`, showing nothing until ``run()`` loads it.
    ///
    /// - Parameters:
    ///   - store: The town's log, read and never written.
    ///   - displayName: Your name; ``displayNameChanged(_:)`` follows a change to it.
    ///   - eventSymbols: The SF Symbol each event kind names in the seed tables, the fixed
    ///     kinds included; a kind it lacks shows its text alone.
    ///   - environment: The clock, date, locale, calendar, and page size.
    public convenience init(
        store: TownStore,
        displayName: DisplayName?,
        eventSymbols: [EventKindID: String],
        environment: TimelineEnvironment = TimelineEnvironment(),
    ) {
        self.init(
            store: Optional(store),
            displayName: displayName,
            eventSymbols: eventSymbols,
            environment: environment,
        )
    }

    /// Creates a timeline already in `snapshot`'s state, with no store behind it — for a
    /// preview, and for a test of what the rows show.
    package convenience init(
        snapshot: TimelineSnapshot,
        displayName: DisplayName?,
        eventSymbols: [EventKindID: String],
        environment: TimelineEnvironment,
    ) {
        self.init(
            store: nil,
            displayName: displayName,
            eventSymbols: eventSymbols,
            environment: environment,
        )
        title = snapshot.townName ?? Self.untitled
        residentNames = snapshot.residentNames
        log.load(snapshot.entries, now: now)
        show(log.arrive(snapshot.arrivedLive, now: now), live: true)
        let away = log.arrive(snapshot.arrivedWhileAway, now: now)
        if !away.isEmpty {
            isAtTop = false
            log.hold(away)
            newPostCount = log.heldPostCount
        }
        selectedPostID = snapshot.selectedPost
        rebuild()
    }

    private init(
        store: TownStore?,
        displayName: DisplayName?,
        eventSymbols: [EventKindID: String],
        environment: TimelineEnvironment,
    ) {
        self.store = store
        self.displayName = displayName
        self.eventSymbols = eventSymbols
        self.environment = environment
        title = Self.untitled
        now = environment.now()
    }

    // MARK: Actions

    /// The scroll position crossed the top. Reaching it shows every post that waited
    /// above, live, and the pill goes.
    public func scrollPositionChanged(isAtTop: Bool) {
        guard isAtTop != self.isAtTop else {
            return
        }
        self.isAtTop = isAtTop
        if isAtTop {
            releaseHeld()
        }
    }

    /// The pill was clicked or Scroll to Latest (⌘↑) chosen: shows what waited, resets
    /// the count, and asks the view to scroll to the top.
    public func scrollToLatestChosen() {
        isAtTop = true
        releaseHeld()
        scrollToTopRequest += 1
    }

    /// ↓ in the timeline: selects the next post down, skipping event rows and quote
    /// lines, and stays on the last; with none selected, selects the topmost.
    public func downArrowPressed() {
        moveSelection(by: 1)
    }

    /// ↑ in the timeline: selects the next post up, and stays on the topmost.
    public func upArrowPressed() {
        moveSelection(by: -1)
    }

    /// Esc left the composer: focus comes to the timeline — the selected post, or the
    /// topmost with none selected; with no posts, nothing takes it.
    public func composerDismissed() {
        if selectedPostID == nil {
            selectedPostID = postOrder.first
        }
        focusRequest += 1
    }

    /// A post took focus from the pointer or Tab, or focus left the posts (`nil`).
    public func postSelected(_ id: Post.ID?) {
        selectedPostID = id
    }

    /// Your name changed in Settings; every post of yours shows the new one at once.
    public func displayNameChanged(_ name: DisplayName?) {
        displayName = name
        rebuild()
    }

    /// The view finished fading `id` in, so the row shows plainly if it appears again.
    public func arrivalShown(_ id: Post.ID) {
        liveArrivals.remove(id)
    }

    /// Whether `id` arrived live and its row should fade in under the wash.
    public func isArrivingLive(_ id: Post.ID) -> Bool {
        liveArrivals.contains(id)
    }

    // MARK: Changes from the store and the clock

    /// The town and its residents as last read.
    func townRead(_ town: Town?, residents: [Resident]) {
        title = town?.name ?? Self.untitled
        residentNames = Dictionary(residents.map { ($0.id, $0.name) }) { first, _ in first }
    }

    /// A page — the newest at launch, or the next older one — was read: its rows are
    /// shown without motion, and its cursor says where the next starts.
    func pageLoaded(_ page: TimelinePage) {
        now = environment.now()
        log.load(page.entries, now: now)
        olderCursor = page.older
        canLoadOlder = page.older != nil && page.entries.count >= pageSize
        rebuild()
    }

    /// Entries read after a change in the store; the new ones whose time has come arrive.
    func entriesArrived(_ entries: [TimelineEntry]) {
        now = environment.now()
        arrived(log.arrive(entries, now: now))
    }

    /// The clock woke the timeline: times are written afresh, and every post whose time
    /// has come arrives.
    func clockTicked() {
        now = environment.now()
        arrived(log.takeDue(now: now))
    }

    /// An older page read that began in `generation` returned. One begun before the town
    /// was deleted is dropped; otherwise its rows are shown and the next page may load.
    package func olderPageRead(_ page: TimelinePage, startedIn generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        isLoadingOlder = false
        pageLoaded(page)
    }

    /// An older page read that began in `generation` failed; the next page may be asked
    /// for again unless the town was deleted meanwhile.
    func olderPageFailed(startedIn generation: Int) {
        if generation == loadGeneration {
            isLoadingOlder = false
        }
    }

    /// Quoted posts the store was asked for in `generation`; `found` holds those it had.
    /// Posts read before the town was deleted are dropped.
    func quotesFetched(_ found: [Post], asked: Set<Post.ID>, startedIn generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        askedQuotes.formUnion(asked)
        for post in found {
            quoted[post.id] = post
        }
        let waiting = unannouncedReplies
        unannouncedReplies = []
        announceReplies(to: waiting)
        rebuild()
    }

    /// Moving away deleted the town: the timeline is empty again.
    func everythingDeleted() {
        loadGeneration += 1
        isLoadingOlder = false
        log.removeAll()
        quoted = [:]
        askedQuotes = []
        unannouncedReplies = []
        liveArrivals = []
        olderCursor = nil
        canLoadOlder = false
        selectedPostID = nil
        newPostCount = 0
        isAtTop = true
        title = Self.untitled
        rebuild()
    }

    // MARK: Private

    private func arrived(_ keys: [TimelineLog.Key]) {
        guard !keys.isEmpty else {
            return
        }
        announceReplies(to: keys.compactMap { key in
            if case let .post(id) = key {
                return id
            }
            return nil
        })
        if isAtTop {
            show(keys, live: true)
            rebuild()
        } else {
            log.hold(keys)
            newPostCount = log.heldPostCount
            if !unannouncedReplies.isEmpty {
                // Held rows are not rebuilt, but the targets they wait for are read now.
                rebuild()
            }
        }
    }

    private func releaseHeld() {
        let held = log.releaseHeld()
        newPostCount = 0
        guard !held.isEmpty else {
            return
        }
        show(held, live: true)
        rebuild()
    }

    private func show(_ keys: [TimelineLog.Key], live: Bool) {
        log.show(keys)
        guard live else {
            return
        }
        for case let .post(id) in keys {
            liveArrivals.insert(id)
        }
    }

    private func moveSelection(by step: Int) {
        let order = postOrder
        guard let topmost = order.first else {
            return
        }
        guard let selectedPostID, let index = order.firstIndex(of: selectedPostID) else {
            selectedPostID = topmost
            return
        }
        self.selectedPostID = order[min(max(index + step, 0), order.count - 1)]
    }

    private func rebuild() {
        let grouping = TimelineGrouping(
            residentNames: residentNames,
            displayName: displayName,
            locale: environment.locale,
            eventSymbols: eventSymbols,
        )
        let result = grouping.items(posts: log.shownPosts, events: log.shownEvents) { id in
            log.posts[id] ?? quoted[id]
        }
        if result.items != items {
            items = result.items
        }
        let waitedFor = unannouncedReplies.compactMap { log.posts[$0]?.replyTarget }
        missingQuotes = result.missingQuotes.union(waitedFor).subtracting(askedQuotes)
    }
}

extension TimelineViewModel {
    /// Announces each arriving resident's post that replies to one of yours; one whose
    /// target is not read yet waits for it, unless the store was already asked.
    private func announceReplies(to ids: [Post.ID]) {
        for id in ids {
            guard let post = log.posts[id],
                  case let .resident(author) = post.author,
                  let target = post.replyTarget
            else {
                continue
            }
            guard let replied = log.posts[target] ?? quoted[target] else {
                if !askedQuotes.contains(target) {
                    unannouncedReplies.append(id)
                }
                continue
            }
            guard replied.author == .you else {
                continue
            }
            // A name the timeline has not read would announce as " replied to you".
            guard let name = residentNames[author] else {
                continue
            }
            let serial = (announcement?.serial ?? 0) + 1
            announcement = TimelineAnnouncement(
                serial: serial,
                text: TimelineWording.repliedToYou(name: name),
            )
        }
    }
}
