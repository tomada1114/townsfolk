import Foundation
import TownsfolkCore

/// An inline seed file built in the test, so each failure mode the seed checks guard
/// against is shown failing on a table small enough to read. It starts at exactly the
/// starting minimums, with every entry valid, and a test changes one thing.
struct SeedFixture {
    /// One event kind as a seed file spells it.
    struct Kind {
        /// The upper bound of a fixture kind's default `hours`, `[1, 3]`.
        static let fewHours = 3

        var id: String
        var text: String?
        var symbol = "star"
        var hours = [1, Self.fewHours]

        /// The kind as a JSON object; its text is its id with spaces unless one is set.
        var json: [String: Any] {
            ["id": id, "text": text ?? SeedFixture.words(id), "symbol": symbol, "hours": hours]
        }
    }

    var version = 1
    var occupations = Self.entries("occupation", count: SeedTablesCheck.Minimum.occupations)
    var personalities = Self.entries("personality", count: SeedTablesCheck.Minimum.personalities)
    var lifeStages = Self.entries("life-stage", count: SeedTablesCheck.Minimum.lifeStages)
    var hobbies = Self.entries("hobby", count: SeedTablesCheck.Minimum.hobbies)
    var eventKinds = (1 ... SeedTablesCheck.Minimum.eventKinds).map { Kind(id: "kind-\($0)").json }
    var fixedEventKinds: [[String: Any]] = [
        ["id": "move-in", "symbol": "house"],
        ["id": "move-out", "symbol": "figure.walk"],
        ["id": "founding", "symbol": "house"],
    ]

    /// `count` entries with ids `<prefix>-1` … and matching text.
    static func entries(_ prefix: String, count: Int) -> [[String: Any]] {
        (1 ... count).map { entry("\(prefix)-\($0)") }
    }

    /// One axis entry whose text is its id with spaces.
    static func entry(_ id: String) -> [String: Any] {
        entry(id, text: words(id))
    }

    /// One axis entry.
    static func entry(_ id: String, text: String) -> [String: Any] {
        ["id": id, "text": text]
    }

    /// `id` with its hyphens as spaces.
    static func words(_ id: String) -> String {
        id.replacing("-", with: " ")
    }

    /// The fixture as JSON, laid out as `Resources/SeedTables.json` is.
    func data() throws -> Data {
        let file: [String: Any] = [
            "version": version,
            "residentAxes": [
                "occupations": occupations,
                "personalities": personalities,
                "lifeStages": lifeStages,
                "hobbies": hobbies,
            ],
            "eventKinds": eventKinds,
            "fixedEventKinds": fixedEventKinds,
        ]
        return try JSONSerialization.data(withJSONObject: file, options: [.sortedKeys])
    }

    /// The fixture decoded the way the shipped file is.
    func file() throws -> SeedFile {
        try SeedFile(name: "SeedTables.json", tables: SeedTables.decode(data()))
    }
}
