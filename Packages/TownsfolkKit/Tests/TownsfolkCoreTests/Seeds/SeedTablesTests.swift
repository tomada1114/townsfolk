import Testing
import TownsfolkCore

/// The shipped seed file, `Resources/SeedTables.json`, held to `SeedTablesCheck`'s rules
/// and to the ids every stored event depends on. Each check's problems are the failure's
/// comment, so a failure names the list and the id.
@Suite("Seed tables")
struct SeedTablesTests {
    /// The event kinds requirements §3.6 names, one id each.
    private static let namedKinds = [
        "weather-turns", "shop-opens", "festival", "lost-pet", "road-works", "visitor", "power-cut",
    ]

    /// Every event-kind id format version 1 shipped with. An id is stored with every event,
    /// so it is never removed or renamed; new ids may be added beside these.
    private static let versionOneKinds = namedKinds + [
        "market-day", "snowfall", "thick-fog", "concert", "fireworks", "sports-day", "book-fair",
    ]

    /// The fixed kinds, never drawn at random, and their symbols.
    private static let fixedKinds: [(id: EventKindID, symbol: String)] = [
        (.moveIn, "house"), (.moveOut, "figure.walk"), (.founding, "house"),
    ]

    /// `Tuning`'s event-duration range in whole hours.
    private static var hourBounds: ClosedRange<Int> {
        let duration = Tuning.default.events.eventDuration
        let secondsPerHour: Int64 = 3_600
        return Int(duration.lowerBound.components.seconds / secondsPerHour)
            ... Int(duration.upperBound.components.seconds / secondsPerHour)
    }

    private static func file() throws -> SeedFile {
        try SeedFile(name: "SeedTables.json", tables: SeedTables.load())
    }

    @Test
    func `the file loads at format version 1`() throws {
        let tables = try SeedTables.load()
        #expect(tables.version == 1)
        #expect(SeedTables.formatVersion == 1)
    }

    @Test
    func `the file meets its minimum sizes`() throws {
        let problems = try SeedTablesCheck.sizeProblems(in: Self.file())
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test
    func `the file has no repeated id or text within a list`() throws {
        let problems = try SeedTablesCheck.duplicateProblems(in: Self.file())
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test
    func `every text in the file is trimmed and non-empty`() throws {
        let problems = try SeedTablesCheck.textProblems(in: Self.file())
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test
    func `the hour bounds are Tuning's 1 to 12 hours`() {
        #expect(Self.hourBounds == 1 ... 12)
    }

    @Test
    func `every event kind lasts within Tuning's event-duration range`() throws {
        let problems = try SeedTablesCheck.durationProblems(
            in: Self.file(),
            within: Self.hourBounds,
        )
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test
    func `the file holds every version 1 event kind, the seven named ones among them`() throws {
        let ids = try Set(SeedTables.load().eventKinds.map(\.id.rawValue))
        let missing = Self.versionOneKinds.filter { !ids.contains($0) }
        #expect(Self.versionOneKinds.count == 14)
        #expect(Set(Self.namedKinds).isSubset(of: Self.versionOneKinds))
        #expect(missing.isEmpty, "missing from SeedTables.json: \(missing)")
    }

    @Test
    func `the file holds the fixed kinds with their symbols and nothing else`() throws {
        let fixed = try SeedTables.load().fixedEventKinds
        #expect(fixed.map(\.id) == Self.fixedKinds.map(\.id))
        #expect(fixed.map(\.symbol) == Self.fixedKinds.map(\.symbol))
        #expect(fixed.map(\.id.rawValue) == ["move-in", "move-out", "founding"])
    }

    @Test
    func `the power cut keeps its symbol, its one to three hours, and its wording`() throws {
        let tables = try SeedTables.load()
        let powerCut = try #require(tables.eventKinds
            .first { $0.id == EventKindID(rawValue: "power-cut") })
        #expect(powerCut.symbol == "bolt.slash")
        #expect(powerCut.hours == 1 ... 3)
        #expect(powerCut.text == "a power cut")
    }
}
