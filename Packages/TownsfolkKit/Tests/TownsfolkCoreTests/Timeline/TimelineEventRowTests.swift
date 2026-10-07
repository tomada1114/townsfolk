import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// Event rows: their text, time, and the symbol the injected lookup names (REQ-003).
@MainActor
@Suite("Timeline event rows")
struct TimelineEventRowTests {
    private let clock = ManualClock(start: Fixtures.at("12:12:00"))

    private static func eventRows(in model: TimelineViewModel) -> [TimelineEventRow] {
        model.items.compactMap { item in
            if case let .event(row) = item {
                return row
            }
            return nil
        }
    }

    @Test(arguments: [
        ("move-in", "house"),
        ("move-out", "figure.walk"),
        ("founding", "house"),
        ("weather-turns", "cloud.sun.rain"),
    ])
    func `an event row takes its kind's symbol from the lookup`(
        kind: String,
        symbol: String,
    ) throws {
        let resident = kind.hasPrefix("move") ? Fixtures.mika : nil
        let snapshot = try TimelineSnapshot(entries: [
            .event(Fixtures.event(
                "12:00:00",
                "Something happened.",
                kind: EventKindID(rawValue: kind),
                resident: resident,
            )),
        ])
        let row = try #require(Self.eventRows(in: Fixtures.model(snapshot, clock: clock)).first)
        #expect(row.symbol == symbol)
        #expect(row.text == "Something happened.")
    }

    @Test
    func `a kind the lookup does not name shows its text alone`() throws {
        let snapshot = try TimelineSnapshot(entries: [
            .event(Fixtures.event(
                "12:00:00",
                "A kite got stuck.",
                kind: EventKindID(rawValue: "kite"),
            )),
        ])
        let row = try #require(Self.eventRows(in: Fixtures.model(snapshot, clock: clock)).first)
        #expect(row.symbol == nil)
        #expect(row.text == "A kite got stuck.")
    }

    @Test
    func `an event row shows its start as a relative time and reads text then time`() throws {
        let snapshot = try TimelineSnapshot(entries: [
            .event(Fixtures.event("12:00:00", "It started raining.")),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        let row = try #require(Self.eventRows(in: model).first)
        #expect(model.time(of: row.startsAt) == "12m")
        #expect(model.reading(of: row).resolved(in: .english) == "It started raining., 12m")
    }
}
