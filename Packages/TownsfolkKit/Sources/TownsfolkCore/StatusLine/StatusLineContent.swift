import Foundation

/// What the status line says (requirements §3.3): an ongoing event first, then the
/// latest topic, filled into one of four templates — built from what the store holds,
/// with no model call. Equal contents are the same line, so the view crossfades only when
/// this changes.
public struct StatusLineContent: Sendable, Hashable {
    /// Which template the line uses, with the text it is filled with.
    public enum Line: Sendable, Hashable {
        /// "{event} · {topic}".
        case eventAndTopic(event: String, topic: String)
        /// "{event}".
        case event(String)
        /// "Everyone's talking about {topic}".
        case topic(String)
        /// "A quiet day in {town}".
        case quiet(town: String)
    }

    /// The template and its text.
    public let line: Line
    /// The kind of the event the line leads with, whose symbol goes before the text.
    public let eventKind: EventKindID?

    /// Chooses the line at `now`.
    ///
    /// - Parameters:
    ///   - townName: The town's name, for the quiet day.
    ///   - ongoingEvents: Events the store holds as ongoing; only those with
    ///     `startsAt <= now < endsAt` count, and the one that started latest is shown.
    ///   - recentTopicTags: The recent window's tags, newest post first; the first is the
    ///     latest topic.
    ///   - now: The date the line is chosen at.
    public init(
        townName: String,
        ongoingEvents: [TownEvent],
        recentTopicTags: [String],
        now: Date,
    ) {
        let shown = ongoingEvents
            .filter { $0.status == .ongoing && $0.startsAt <= now && now < $0.endsAt }
            .max { $0.startsAt < $1.startsAt }
        let topic = recentTopicTags.first
        switch (shown, topic) {
        case let (event?, topic?):
            line = .eventAndTopic(event: event.description, topic: topic)

        case let (event?, nil):
            line = .event(event.description)

        case let (nil, topic?):
            line = .topic(topic)

        case (nil, nil):
            line = .quiet(town: townName)
        }
        eventKind = shown?.kind
    }

    /// Creates a line as it is, for a preview of a line no stored value could make.
    package init(line: Line, eventKind: EventKindID?) {
        self.line = line
        self.eventKind = eventKind
    }

    /// The next moment after `now` at which an event in `events` starts or ends — when
    /// the line may change with no write to the store.
    static func nextBoundary(of events: [TownEvent], after now: Date) -> Date? {
        events.flatMap { [$0.startsAt, $0.endsAt] }.filter { $0 > now }.min()
    }
}
