import Testing
import TownsfolkCore

/// The shipped seed files, `Resources/Seeds/en.json` and `ja.json` (ADR-0007), held to
/// `SeedTablesCheck`'s rules and to the ids every stored event depends on. Each check's
/// problems are the failure's comment, so a failure names the list, the id, and the file.
@Suite("Seed tables")
struct SeedTablesTests {
    /// The event kinds requirements §3.6 names, one id each.
    private static let namedKinds = [
        "weather-turns", "shop-opens", "festival", "lost-pet", "road-works", "visitor", "power-cut",
    ]

    /// Every event-kind id format version 1 shipped with. An id is stored with every event
    /// (ADR-0007), so it is never removed or renamed; new ids may be added beside these.
    private static let versionOneKinds = namedKinds + [
        "market-day", "snowfall", "thick-fog", "concert", "fireworks", "sports-day", "book-fair",
    ]

    /// The fixed kinds, never drawn at random, and their symbols (ADR-0008).
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

    private static func file(_ language: TownLanguage) throws -> SeedFile {
        try SeedFile(name: "\(language.rawValue).json", tables: SeedTables.load(for: language))
    }

    @Test(arguments: TownLanguage.allCases)
    func `each file loads at format version 1`(language: TownLanguage) throws {
        let tables = try SeedTables.load(for: language)
        #expect(tables.version == 1)
        #expect(SeedTables.formatVersion == 1)
    }

    @Test(arguments: TownLanguage.allCases)
    func `each file meets its minimum sizes`(language: TownLanguage) throws {
        let problems = try SeedTablesCheck.sizeProblems(in: Self.file(language))
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test(arguments: TownLanguage.allCases)
    func `each file has no repeated id or text within a list`(language: TownLanguage) throws {
        let problems = try SeedTablesCheck.duplicateProblems(in: Self.file(language))
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test(arguments: TownLanguage.allCases)
    func `every text in each file is trimmed and non-empty`(language: TownLanguage) throws {
        let problems = try SeedTablesCheck.textProblems(in: Self.file(language))
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test
    func `the hour bounds are Tuning's 1 to 12 hours`() {
        #expect(Self.hourBounds == 1 ... 12)
    }

    @Test(arguments: TownLanguage.allCases)
    func `every event kind lasts within Tuning's event-duration range`(
        language: TownLanguage,
    ) throws {
        let problems = try SeedTablesCheck.durationProblems(
            in: Self.file(language),
            within: Self.hourBounds,
        )
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test
    func `both files give each event kind and fixed kind the same ids, symbols, and ranges`(
    ) throws {
        let problems = try SeedTablesCheck.parityProblems(Self.file(.english), Self.file(.japanese))
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test(arguments: TownLanguage.allCases)
    func `each file holds every version 1 event kind, the seven named ones among them`(
        language: TownLanguage,
    ) throws {
        let ids = try Set(SeedTables.load(for: language).eventKinds.map(\.id.rawValue))
        let missing = Self.versionOneKinds.filter { !ids.contains($0) }
        #expect(Self.versionOneKinds.count == 14)
        #expect(Set(Self.namedKinds).isSubset(of: Self.versionOneKinds))
        #expect(missing.isEmpty, "missing from \(language.rawValue).json: \(missing)")
    }

    @Test(arguments: TownLanguage.allCases)
    func `each file holds the fixed kinds with their symbols and nothing else`(
        language: TownLanguage,
    ) throws {
        let fixed = try SeedTables.load(for: language).fixedEventKinds
        #expect(fixed.map(\.id) == Self.fixedKinds.map(\.id))
        #expect(fixed.map(\.symbol) == Self.fixedKinds.map(\.symbol))
        #expect(fixed.map(\.id.rawValue) == ["move-in", "move-out", "founding"])
    }

    @Test
    func `the Japanese power cut keeps its symbol and its one to three hours`() throws {
        let tables = try SeedTables.load(for: .japanese)
        let powerCut = try #require(tables.eventKinds
            .first { $0.id == EventKindID(rawValue: "power-cut") })
        #expect(powerCut.symbol == "bolt.slash")
        #expect(powerCut.hours == 1 ... 3)
        // The Japanese for "power cut", as escapes so the source stays English (AGENTS.md).
        #expect(powerCut.text == "\u{505C}\u{96FB}")
    }

    @Test
    func `the files differ in wording, not in event ids`() throws {
        let english = try SeedTables.load(for: .english)
        let japanese = try SeedTables.load(for: .japanese)
        #expect(english.eventKinds.map(\.id) == japanese.eventKinds.map(\.id))
        #expect(english.eventKinds.map(\.text) != japanese.eventKinds.map(\.text))
        #expect(english.residentAxes.occupations.map(\.text) != japanese.residentAxes.occupations
            .map(\.text))
    }
}
