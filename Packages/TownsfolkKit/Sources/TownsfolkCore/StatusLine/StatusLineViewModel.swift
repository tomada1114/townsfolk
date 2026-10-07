import Foundation
import Observation

/// The town's status line (ux-flows S1, requirements §3.3): one line saying what is going
/// on, read from ``TownStore`` and never written to it, with no model call.
///
/// ``run()`` reads the town, its ongoing events, and the recent topic tags, then follows
/// the store's committed steps and the clock — an event's end, or a post's time coming,
/// changes the line with no write — until cancelled. ``content`` is the one place the
/// line is decided, so the resting line can later take its place here. Nothing the line
/// says is ever logged.
@MainActor
@Observable
public final class StatusLineViewModel {
    /// How often the line is read afresh with no change announced, so a post whose stored
    /// time comes later shows its topic once it appears.
    static let refreshInterval = Duration.seconds(secondsPerRefresh)
    private static let secondsPerRefresh = 60
    private static let millisecondsPerSecond: Double = 1_000

    /// What VoiceOver calls the line: "Town status".
    public static var accessibilityLabel: LocalizedStringResource {
        StatusLineWording.accessibilityLabel
    }

    /// The line, or `nil` before there is a town.
    public private(set) var content: StatusLineContent?

    @ObservationIgnored private let store: TownStore?
    @ObservationIgnored private let eventSymbols: [EventKindID: String]
    @ObservationIgnored private let environment: TimelineEnvironment
    /// The ongoing events as last read, for when the clock should next wake.
    @ObservationIgnored private var events: [TownEvent] = []
    /// Counts up with each read begun, so an older read returning late is dropped.
    @ObservationIgnored private var readGeneration = 0
    /// The sleep ``run()`` is in, cancelled to recount the wait after a change.
    @ObservationIgnored private var sleeper: Task<Void, Never>?

    /// The line to show, in the environment's locale, or `nil` before there is a town.
    public var text: LocalizedStringResource? {
        guard let content else {
            return nil
        }
        var resource = switch content.line {
        case let .eventAndTopic(event, topic):
            StatusLineWording.eventAndTopic(event: event, topic: topic)

        case let .event(event):
            StatusLineWording.event(event)

        case let .topic(topic):
            StatusLineWording.topic(topic)

        case let .quiet(town):
            StatusLineWording.quiet(town: town)
        }
        resource.locale = environment.locale
        return resource
    }

    /// The SF Symbol of the event the line leads with, or `nil` when it leads with none
    /// or its kind has no symbol.
    public var symbol: String? {
        content?.eventKind.flatMap { eventSymbols[$0] }
    }

    /// Creates the status line over `store`, showing nothing until ``run()`` reads it.
    ///
    /// - Parameters:
    ///   - store: The town's log, read and never written.
    ///   - eventSymbols: The SF Symbol each event kind names in the seed tables — the same
    ///     lookup the timeline's event rows use; a kind it lacks shows its text alone.
    ///   - environment: The clock, the date, and the locale the line is written in.
    public convenience init(
        store: TownStore,
        eventSymbols: [EventKindID: String],
        environment: TimelineEnvironment = TimelineEnvironment(),
    ) {
        self.init(store: Optional(store), eventSymbols: eventSymbols, environment: environment)
    }

    /// Creates a status line already showing `content`, with no store behind it — for a
    /// preview, and for a test of what the line says.
    package convenience init(
        content: StatusLineContent?,
        eventSymbols: [EventKindID: String],
        environment: TimelineEnvironment,
    ) {
        self.init(store: nil, eventSymbols: eventSymbols, environment: environment)
        self.content = content
    }

    private init(
        store: TownStore?,
        eventSymbols: [EventKindID: String],
        environment: TimelineEnvironment,
    ) {
        self.store = store
        self.eventSymbols = eventSymbols
        self.environment = environment
    }

    /// Reads the line, then follows the store's committed steps and the clock until
    /// cancelled — the view calls it from `.task`, so it stops with the view. A status
    /// line with no store does nothing.
    public func run() async {
        guard let store else {
            return
        }
        // Subscribing before the first read, so a step committed meanwhile is not missed.
        let changes = await store.changes()
        await read(from: store)
        await withDiscardingTaskGroup { group in
            group.addTask { await self.follow(changes, from: store) }
            group.addTask { await self.keepTime(from: store) }
        }
    }

    private func follow(_ changes: AsyncStream<TownStoreChange>, from store: TownStore) async {
        for await change in changes {
            if change == .everythingDeleted {
                readGeneration += 1
                events = []
                show(nil)
            } else {
                // A step announces itself, not each thing it wrote, so any change re-reads.
                await read(from: store)
            }
            sleeper?.cancel()
        }
    }

    private func keepTime(from store: TownStore) async {
        while !Task.isCancelled {
            let wait = nextWait()
            let clock = environment.clock
            // A cancelled sleep is the early wake, not a failure, so its error is dropped.
            let nap = Task<Void, Never> { try? await clock.sleep(for: wait) }
            sleeper = nap
            await withTaskCancellationHandler {
                await nap.value
            } onCancel: {
                nap.cancel()
            }
            sleeper = nil
            guard !Task.isCancelled else {
                return
            }
            await read(from: store)
        }
    }

    /// Until the next event starts or ends, or the refresh interval, whichever is sooner.
    private func nextWait() -> Duration {
        let now = environment.now()
        guard let boundary = StatusLineContent.nextBoundary(of: events, after: now) else {
            return Self.refreshInterval
        }
        let milliseconds = boundary.timeIntervalSince(now) * Self.millisecondsPerSecond
        return min(.milliseconds(Int64(milliseconds.rounded(.up))), Self.refreshInterval)
    }

    private func read(from store: TownStore) async {
        readGeneration += 1
        let generation = readGeneration
        let now = environment.now()
        do {
            let town = try await store.town()
            let ongoing = try await store.ongoingEvents()
            let tags = try await store.recentTopicTags(before: now)
            guard generation == readGeneration else {
                return
            }
            events = ongoing
            show(town.map { town in
                StatusLineContent(
                    townName: town.name,
                    ongoingEvents: ongoing,
                    recentTopicTags: tags,
                    now: now,
                )
            })
        } catch {
            AppLog.timeline
                .error("status line read failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Shows `new`, leaving an unchanged line untouched so the view does not animate.
    private func show(_ new: StatusLineContent?) {
        if new != content {
            content = new
        }
    }
}
