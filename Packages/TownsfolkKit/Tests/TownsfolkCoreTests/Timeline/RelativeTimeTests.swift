import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// Relative times, the full time on pointing, and the 60-second refresh (REQ-005).
@MainActor
@Suite("Relative time")
struct RelativeTimeTests {
    private static let now = StoreFixtures.date("2026-10-01T12:00:00Z")

    private static var format: RelativeTimeFormat {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(identifier: "UTC") {
            calendar.timeZone = utc
        }
        return RelativeTimeFormat(locale: Locale(identifier: "en_US_POSIX"), calendar: calendar)
    }

    @Test(arguments: [
        (0, "now"),
        (59, "now"),
        (60, "1m"),
        (119, "1m"),
        (3_599, "59m"),
        (3_600, "1h"),
        (86_340, "23h"),
        (86_399, "23h"),
        (86_400, "Sep 30"),
        (-30, "now"),
    ])
    func `a time reads now, then minutes, then hours up to 23, then a short date`(
        secondsAgo: Int,
        expected: String,
    ) {
        let date = Self.now.addingTimeInterval(-TimeInterval(secondsAgo))
        #expect(Self.format.relative(date, now: Self.now) == expected)
    }

    @Test
    func `a time in another locale goes through that locale's formatter`() {
        var format = Self.format
        format.locale = Locale(identifier: "de_DE")
        let twoDaysAgo = StoreFixtures.date("2026-09-29T12:00:00Z")
        #expect(format.relative(twoDaysAgo, now: Self.now) == "29. Sept.")
    }

    @Test
    func `pointing at a time gives the full date and time`() {
        let date = StoreFixtures.date("2026-09-30T12:00:00Z")
        // The formatter puts a narrow no-break space before "PM".
        #expect(Self.format.full(date) == "September 30, 2026 at 12:00\u{202F}PM")
    }

    @Test
    func `the timeline refreshes its relative times every 60 seconds`() async throws {
        let clock = ManualClock(start: Fixtures.at("12:00:30"))
        let post = try Fixtures.post(Fixtures.mika, "12:00:00", "Bread is out.")
        let model = try Fixtures.model(TimelineSnapshot(entries: [.post(post)]), clock: clock)
        try await whileRunning(model, on: clock) {
            #expect(model.time(of: post.happenedAt) == "now")
            await clock.advanceAndWait(by: .seconds(60))
            #expect(model.time(of: post.happenedAt) == "1m")
            #expect(model.fullTime(of: post.happenedAt) == "October 1, 2026 at 12:00\u{202F}PM")
        }
    }
}
