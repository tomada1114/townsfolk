import Foundation

/// What the timeline reads from the world, handed in rather than read
/// (`designing-core-logic` › Inject time, Inject locale): the clock it waits on, the date
/// it reads now, the locale and calendar it writes times in, and how many rows a page
/// asks the store for. The defaults are the real ones; a test passes a manual clock and
/// pins the rest.
public struct TimelineEnvironment: Sendable {
    /// What the timeline sleeps on until the next post is due or the times need
    /// refreshing.
    public var clock: any Clock<Duration>
    /// The date now. Read alongside ``clock``, so a test's clock moves both.
    public var now: @Sendable () -> Date
    /// The locale times are written in.
    public var locale: Locale
    /// The calendar, and the time zone it carries, dates are written in.
    public var calendar: Calendar
    /// How many rows one page asks the store for — an implementation value, not a
    /// starting value to tune; below 1 counts as 1.
    public var pageSize: Int

    /// Creates an environment; every default is the real world, and 100 rows a page.
    public init(
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now },
        locale: Locale = .current,
        calendar: Calendar = .current,
        pageSize: Int = 100,
    ) {
        self.clock = clock
        self.now = now
        self.locale = locale
        self.calendar = calendar
        self.pageSize = pageSize
    }
}
