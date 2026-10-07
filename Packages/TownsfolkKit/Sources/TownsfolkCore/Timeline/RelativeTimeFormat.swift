import Foundation

/// How the timeline writes a time (ux-guidelines › Language and copy): "now" under a
/// minute, then minutes, then hours up to 23, then a short date — the platform
/// formatters' abbreviated forms in the locale it is handed — and the full date and time
/// for pointing at one.
///
/// Locale and calendar are inputs, `.current` in the app, so a test pins both
/// (`designing-core-logic` › Inject locale); the calendar carries the time zone.
public struct RelativeTimeFormat: Sendable {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3_600
    private static let secondsPerDay = 86_400

    /// The locale every time is formatted in.
    public var locale: Locale
    /// The calendar, with its time zone, a date is formatted in.
    public var calendar: Calendar

    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// Creates a format writing in `locale` and `calendar`.
    public init(locale: Locale, calendar: Calendar) {
        self.locale = locale
        self.calendar = calendar
    }

    /// `date` relative to `now`. A date after `now` reads "now": a post is only shown
    /// once its time has come.
    public func relative(_ date: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < Self.secondsPerMinute {
            var resource = TimelineWording.now
            resource.locale = locale
            return String(localized: resource)
        }
        if elapsed < Self.secondsPerHour {
            return narrow(.minutes(elapsed / Self.secondsPerMinute), unit: .minutes)
        }
        if elapsed < Self.secondsPerDay {
            return narrow(
                .seconds(elapsed / Self.secondsPerHour * Self.secondsPerHour),
                unit: .hours,
            )
        }
        return date.formatted(dateStyle.month(.abbreviated).day())
    }

    /// `date` in full, for the `.help` shown on pointing at a time.
    public func full(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(
            date: .long,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone,
        ))
    }

    /// A whole number of `unit`s in the formatter's narrowest form ("5m", "23h").
    private func narrow(_ duration: Duration, unit: Duration.UnitsFormatStyle.Unit) -> String {
        duration.formatted(.units(allowed: [unit], width: .narrow).locale(locale))
    }
}
