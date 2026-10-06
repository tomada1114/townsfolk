import Foundation
import Testing
import TownsfolkCore

/// Each failure mode `SeedTablesCheck` guards the shipped files against, shown failing on
/// an inline table (issue #10 › Boundary Conditions), so a check that passes on the
/// shipped files is known not to pass on everything.
@Suite("Seed table checks")
struct SeedTablesCheckTests {
    private static let hourBounds = 1 ... 12

    // MARK: - Size

    @Test
    func `a table holding exactly the minimums passes every check`() throws {
        let file = try SeedFixture().file()
        #expect(SeedTablesCheck.sizeProblems(in: file).isEmpty)
        #expect(SeedTablesCheck.duplicateProblems(in: file).isEmpty)
        #expect(SeedTablesCheck.textProblems(in: file).isEmpty)
        #expect(SeedTablesCheck.durationProblems(in: file, within: Self.hourBounds).isEmpty)
    }

    @Test(arguments: [
        ("occupations", "occupations: 29 in SeedTables.json, fewer than 30"),
        ("personalities", "personalities: 19 in SeedTables.json, fewer than 20"),
        ("lifeStages", "lifeStages: 5 in SeedTables.json, fewer than 6"),
        ("hobbies", "hobbies: 29 in SeedTables.json, fewer than 30"),
        ("eventKinds", "eventKinds: 11 in SeedTables.json, fewer than 12"),
    ])
    func `one fewer than a minimum fails naming the list and the file`(
        list: String,
        problem: String,
    ) throws {
        var fixture = SeedFixture()
        switch list {
        case "occupations":
            fixture.occupations.removeLast()

        case "personalities":
            fixture.personalities.removeLast()

        case "lifeStages":
            fixture.lifeStages.removeLast()

        case "hobbies":
            fixture.hobbies.removeLast()

        default:
            fixture.eventKinds.removeLast()
        }
        #expect(try SeedTablesCheck.sizeProblems(in: fixture.file()) == [problem])
    }

    // MARK: - Duplicates and text

    @Test
    func `a repeated id or text within one list fails naming it`() throws {
        var fixture = SeedFixture()
        fixture.occupations.append(SeedFixture.entry("occupation-1", text: "baker"))
        fixture.hobbies.append(SeedFixture.entry("hobby-extra", text: "hobby 3"))
        fixture.eventKinds.append(SeedFixture.Kind(id: "kind-2", text: "a fair").json)
        fixture.fixedEventKinds.append(["id": "move-in", "symbol": "house"])
        #expect(try SeedTablesCheck.duplicateProblems(in: fixture.file()) == [
            "occupations: duplicate id occupation-1 in SeedTables.json",
            "hobbies: duplicate text hobby 3 in SeedTables.json",
            "eventKinds: duplicate id kind-2 in SeedTables.json",
            "fixedEventKinds: duplicate id move-in in SeedTables.json",
        ])
    }

    @Test
    func `the same id in two different lists is not a duplicate`() throws {
        var fixture = SeedFixture()
        fixture.hobbies.append(SeedFixture.entry("occupation-1", text: "something else"))
        #expect(try SeedTablesCheck.duplicateProblems(in: fixture.file()).isEmpty)
    }

    @Test(arguments: ["", " baker", "baker ", "baker\n"])
    func `an empty or untrimmed text fails naming the id`(text: String) throws {
        var fixture = SeedFixture()
        fixture.lifeStages[0] = SeedFixture.entry("life-stage-1", text: text)
        fixture.eventKinds[0] = SeedFixture.Kind(id: "kind-1", text: text).json
        #expect(try SeedTablesCheck.textProblems(in: fixture.file()) == [
            "lifeStages: life-stage-1 text is empty or untrimmed in SeedTables.json",
            "eventKinds: kind-1 text is empty or untrimmed in SeedTables.json",
        ])
    }

    // MARK: - Durations

    @Test(arguments: [[1, 12], [1, 1], [12, 12]])
    func `hours inside the tuning range pass`(hours: [Int]) throws {
        var fixture = SeedFixture()
        fixture.eventKinds[0] = SeedFixture.Kind(id: "festival", hours: hours).json
        #expect(try SeedTablesCheck.durationProblems(in: fixture.file(), within: Self.hourBounds)
            .isEmpty)
    }

    @Test(arguments: [
        ([0, 3], "festival: 0...3 is outside 1...12 in SeedTables.json"),
        ([4, 13], "festival: 4...13 is outside 1...12 in SeedTables.json"),
    ])
    func `hours outside the tuning range fail naming the id`(hours: [Int], problem: String) throws {
        var fixture = SeedFixture()
        fixture.eventKinds[0] = SeedFixture.Kind(id: "festival", hours: hours).json
        #expect(try SeedTablesCheck
            .durationProblems(in: fixture.file(), within: Self.hourBounds) == [problem])
    }

    @Test(arguments: [[6, 2], [3], [1, 2, 3]])
    func `hours that are not a forward pair do not decode, and the failure names the id`(
        hours: [Int],
    ) throws {
        var fixture = SeedFixture()
        fixture.eventKinds[0] = SeedFixture.Kind(id: "festival", hours: hours).json
        let data = try fixture.data()
        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(SeedTables.self, from: data)
        }
        guard case let .dataCorrupted(context) = error else {
            Issue.record("expected dataCorrupted, got \(error)")
            return
        }
        #expect(context.debugDescription.hasPrefix("festival:"))
        #expect(throws: SeedTablesError.malformed) {
            try SeedTables.decode(data)
        }
    }
}
