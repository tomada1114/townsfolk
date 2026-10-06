import Foundation
import Testing
import TownsfolkCore

/// Loading a seed file that is missing, malformed, or from another format version: each
/// throws a ``SeedTablesError`` carrying nothing from the file, and none crashes (issue
/// #10 › Boundary Conditions).
@Suite("Seed table loading")
struct SeedTablesLoadingTests {
    /// A fresh directory standing in for a resource bundle, holding `files`.
    private func bundle(holding files: [String: Data]) throws -> (bundle: Bundle, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TownsfolkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: directory.appending(path: name))
        }
        let bundle = try #require(Bundle(url: directory))
        return (bundle, directory)
    }

    @Test
    func `a valid file in the given bundle loads`() throws {
        let fixture = try SeedFixture().data()
        let (bundle, directory) = try bundle(holding: ["SeedTables.json": fixture])
        defer { try? FileManager.default.removeItem(at: directory) }
        let tables = try SeedTables.load(from: bundle)
        #expect(tables.version == 1)
        #expect(tables.residentAxes.occupations.count == 30)
        #expect(tables.residentAxes.occupations.first?.id == "occupation-1")
        #expect(tables.residentAxes.occupations.first?.text == "occupation 1")
        #expect(tables.residentAxes.personalities.count == 20)
        #expect(tables.residentAxes.lifeStages.count == 6)
        #expect(tables.residentAxes.hobbies.count == 30)
        #expect(tables.eventKinds.first?.id == EventKindID(rawValue: "kind-1"))
        #expect(tables.eventKinds.first?.symbol == "star")
        #expect(tables.eventKinds.first?.hours == 1 ... 3)
        #expect(tables.fixedEventKinds.first?.id == .moveIn)
    }

    @Test
    func `a file missing from the bundle throws missing`() throws {
        let (bundle, directory) = try bundle(holding: ["Other.json": SeedFixture().data()])
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: SeedTablesError.missing) {
            try SeedTables.load(from: bundle)
        }
    }

    @Test
    func `a file that cannot be read throws missing`() throws {
        let (bundle, directory) = try bundle(holding: [:])
        defer { try? FileManager.default.removeItem(at: directory) }
        // A directory where the file should be: found by name, but unreadable as data.
        try FileManager.default.createDirectory(
            at: directory.appending(path: "SeedTables.json"),
            withIntermediateDirectories: false,
        )
        #expect(throws: SeedTablesError.missing) {
            try SeedTables.load(from: bundle)
        }
    }

    @Test(arguments: [
        Data("not json".utf8),
        Data(#"{"version": 1}"#.utf8),
        Data(#"{"version": "one"}"#.utf8),
        Data(),
    ])
    func `a file that does not decode throws malformed`(
        data: Data,
    ) throws {
        let (bundle, directory) = try bundle(holding: ["SeedTables.json": data])
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: SeedTablesError.malformed) {
            try SeedTables.load(from: bundle)
        }
    }

    @Test
    func `a file with a table but another format version throws naming the version`(
    ) throws {
        var fixture = SeedFixture()
        fixture.version = 2
        let data = try fixture.data()
        #expect(throws: SeedTablesError.unsupportedVersion(2)) {
            try SeedTables.decode(data)
        }
    }

    @Test
    func `a later version whose shape changed is reported as that version, not as malformed`(
    ) throws {
        let data = Data(#"{"version": 2, "somethingNew": []}"#.utf8)
        #expect(throws: SeedTablesError.unsupportedVersion(2)) {
            try SeedTables.decode(data)
        }
    }

    @Test
    func `an error's description carries no table text`() throws {
        var fixture = SeedFixture()
        fixture.occupations[0] = SeedFixture.entry("secret-id", text: "secret text")
        fixture.eventKinds[0] = SeedFixture.Kind(id: "secret-kind", hours: [6, 2]).json
        let data = try fixture.data()
        let error = try #require(throws: SeedTablesError.self) {
            try SeedTables.decode(data)
        }
        #expect(!String(describing: error).contains("secret"))
    }
}
