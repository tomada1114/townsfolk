import Foundation

/// What the view renders and VoiceOver reads, written against ``TimelineViewModel/now``
/// at the moment the view asks, so only the rows on screen are written afresh each
/// minute.
extension TimelineViewModel {
    /// The Town menu's title (ux-flows S8).
    public static var townMenuTitle: LocalizedStringResource {
        TimelineWording.townMenu
    }

    /// The Town menu's Scroll to Latest command (⌘↑).
    public static var scrollToLatestTitle: LocalizedStringResource {
        TimelineWording.scrollToLatest
    }

    /// The new-posts pill's label, or `nil` while no post waits above the rows.
    public var pillTitle: LocalizedStringResource? {
        newPostCount > 0 ? TimelineWording.newPosts(count: newPostCount) : nil
    }

    /// Whether Scroll to Latest can act: not while the timeline is already at its top.
    public var canScrollToLatest: Bool {
        !isAtTop
    }

    /// How times are written: in the environment's locale and calendar.
    var format: RelativeTimeFormat {
        RelativeTimeFormat(locale: environment.locale, calendar: environment.calendar)
    }

    /// `date` as a relative time: "now", "5m", "3h", or a short date.
    public func time(of date: Date) -> String {
        format.relative(date, now: now)
    }

    /// `date` in full, for the `.help` on a time.
    public func fullTime(of date: Date) -> String {
        format.full(date)
    }

    /// A quote line's visible text, which the view cuts to one line.
    public func line(of quote: TimelineQuote) -> LocalizedStringResource {
        TimelineWording.quoteLine(name: quote.name, text: quote.text)
    }

    /// What VoiceOver reads for `post`: "{name}, {time}: {text}", or "You, …".
    public func reading(of post: TimelinePost) -> LocalizedStringResource {
        let time = time(of: post.happenedAt)
        switch post.author {
        case let .resident(name):
            return TimelineWording.postReading(name: name, time: time, text: post.text)

        case .you:
            return TimelineWording.yourPostReading(time: time, text: post.text)
        }
    }

    /// What VoiceOver reads for `quote`: "Replying to {name}: {text}".
    public func reading(of quote: TimelineQuote) -> LocalizedStringResource {
        TimelineWording.quoteReading(name: quote.name, text: quote.text)
    }

    /// What VoiceOver reads for `group`'s container: "Conversation, {n} posts".
    public func reading(of group: TimelinePostGroup) -> LocalizedStringResource {
        TimelineWording.groupReading(count: group.posts.count)
    }

    /// What VoiceOver reads for `event`: "{text}, {time}".
    public func reading(of event: TimelineEventRow) -> LocalizedStringResource {
        TimelineWording.eventReading(text: event.text, time: time(of: event.startsAt))
    }
}
