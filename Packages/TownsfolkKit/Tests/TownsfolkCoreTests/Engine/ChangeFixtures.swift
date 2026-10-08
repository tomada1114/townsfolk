import Foundation
import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// One stored event as the tests read it back.
struct StoredEvent: Equatable {
    let kind: String
    let description: String
    let startsAt: Date
    let endsAt: Date
    let status: String
    let resident: String?
}

/// Values the event and move suites share. Their second turn comes six minutes after an
/// opening turn at 10:06, so the running time between them is 360 s: an event starts on a
/// draw under 360 ÷ 3 h = 0.0333…, and a move on a draw under 360 ÷ d for the span d drawn.
enum ChangeFixtures {
    /// When the second turn runs.
    static let secondTurn = EngineFixtures.time("10:12:00")
    /// The running time between the opening turn and the second, in seconds.
    static let sixMinutesInSeconds = 360
    /// The running time between the opening turn and the second.
    static let sixMinutes = Duration.seconds(sixMinutesInSeconds)
    /// An event chance draw that starts nothing.
    static let noEvent = 0.99
    /// A move span draw: half way within 24–48 hours, so d is 36 hours.
    static let midSpan = 0.5
    /// A move chance draw that moves nobody.
    static let noMoveChance = 0.99
    /// A move chance draw that moves someone.
    static let moveChance = 0.0
    /// A move span draw, then a move chance draw that moves nobody.
    static let noMove = [midSpan, noMoveChance]
    /// A move span draw, then a move chance draw that moves someone.
    static let aMove = [midSpan, moveChance]
    /// The fewest whole hours each kind of ``tables(kinds:)`` lasts.
    static let tableShortestHours = 1
    /// The most whole hours each kind of ``tables(kinds:)`` lasts.
    static let tableLongestHours = 2

    private static let middleOfAChoice = 0.5

    /// The fraction that picks index `index` among `count` choices.
    static func pick(_ index: Int, of count: Int) -> Double {
        (Double(index) + middleOfAChoice) / Double(count)
    }

    /// The model describing an event as `text`.
    static func description(_ text: String) -> FakeLanguageModelProvider.Outcome {
        .content(EventDescriptionDraft(description: text).generatedContent)
    }

    /// The model inventing a newcomer named `name`, worried about a flat, knowing nobody.
    static func newcomer(_ name: String) -> FakeLanguageModelProvider.Outcome {
        let draft = NewResidentDraft(name: name, worry: "finding a flat", relationships: [])
        return .content(draft.generatedContent)
    }

    /// An ongoing event of `kind`, started at nine, ending at `endsAt`.
    static func ongoing(_ kind: String, _ description: String, endsAt: Date) throws -> TownEvent {
        try TownEvent(
            id: TownEvent.ID(),
            kind: EventKindID(rawValue: kind),
            description: description,
            startsAt: StoreFixtures.morning,
            endsAt: endsAt,
        )
    }

    /// Living residents named `names`, a minute apart in that order, so the store's
    /// moved-in order is the order given.
    static func residents(living names: [String]) throws -> [Resident] {
        try residents(living: names, movedOut: [])
    }

    /// Residents named `living` and then `movedOut`, a minute apart in that order.
    static func residents(living: [String], movedOut: [String]) throws -> [Resident] {
        let names = living.map { ($0, false) } + movedOut.map { ($0, true) }
        return try names.enumerated().map { minute, entry in
            let movedIn = StoreFixtures.minutes(minute)
            return try Resident(
                id: Resident.ID(),
                name: entry.0,
                profile: Resident.Profile(
                    ageGroup: "thirties",
                    occupation: "potter",
                    hobby: "chess",
                    worry: "the rent",
                    personality: "calm",
                ),
                movedInAt: movedIn,
                status: entry.1 ? .movedOut : .living,
                movedOutAt: entry.1 ? movedIn : nil,
            )
        }
    }

    /// Seed tables with the shipped resident axes and only `kinds`, each lasting one or two
    /// hours.
    static func tables(kinds: [String]) throws -> SeedTables {
        let shipped = try SeedTables.load()
        func entries(_ axis: [SeedTables.Entry]) -> [[String: String]] {
            axis.map { ["id": $0.id, "text": $0.text] }
        }
        let eventKinds: [[String: Any]] = kinds.map { kind in
            [
                "id": kind,
                "text": "some \(kind)",
                "symbol": "star",
                "hours": [tableShortestHours, tableLongestHours],
            ]
        }
        let file: [String: Any] = [
            "version": SeedTables.formatVersion,
            "residentAxes": [
                "occupations": entries(shipped.residentAxes.occupations),
                "personalities": entries(shipped.residentAxes.personalities),
                "lifeStages": entries(shipped.residentAxes.lifeStages),
                "hobbies": entries(shipped.residentAxes.hobbies),
            ],
            "eventKinds": eventKinds,
            "fixedEventKinds": [["id": "founding", "symbol": "house"]],
        ]
        return try SeedTables.decode(JSONSerialization.data(withJSONObject: file))
    }
}

extension EngineHarness {
    private enum EventColumn {
        static let kind = 0
        static let description = 1
        static let startsAt = 2
        static let endsAt = 3
        static let status = 4
        static let resident = 5
    }

    private static let millisecondsPerSecond = 1_000.0

    private static func date(_ milliseconds: String) -> Date {
        Date(timeIntervalSince1970: (Double(milliseconds) ?? 0) / millisecondsPerSecond)
    }

    /// Takes the opening turn with the model unavailable — no draw and no call, only the
    /// turn's time is kept — then makes the model available, lets six minutes pass, and
    /// steps.
    func stepAfterOpeningTurn() async throws -> EngineStep {
        let available = model.availability
        model.availability = .modelNotReady
        #expect(try await engine.step() == .modelUnavailable)
        model.availability = available
        clock.advance(by: ChangeFixtures.sixMinutes)
        return try await engine.step()
    }

    /// Every event but the founding row, oldest first, with its resident's name.
    func storedEvents() async throws -> [StoredEvent] {
        let names = try await Dictionary(
            uniqueKeysWithValues: store.residents().map { ($0.id.rawValue.uuidString, $0.name) },
        )
        let rows = try directory.raw().rows("""
        SELECT kind, description, starts_at, ends_at, status, related_resident_id FROM events
        WHERE kind != 'founding' ORDER BY starts_at, kind
        """)
        return rows.map { row in
            StoredEvent(
                kind: row[EventColumn.kind],
                description: row[EventColumn.description],
                startsAt: Self.date(row[EventColumn.startsAt]),
                endsAt: Self.date(row[EventColumn.endsAt]),
                status: row[EventColumn.status],
                resident: names[row[EventColumn.resident]],
            )
        }
    }

    /// The names of the residents living now, in moved-in order.
    func livingNames() async throws -> [String] {
        try await store.residents().filter { $0.status == .living }.map(\.name)
    }
}
