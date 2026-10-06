import Foundation
import TownsfolkCore

/// One seed file's tables and the name its problems are reported under.
struct SeedFile {
    let name: String
    let tables: SeedTables
}

/// One list of a seed file whose entries have an id and a text: a resident axis, or the
/// event kinds.
struct SeedList {
    let name: String
    let ids: [String]
    let texts: [String]
}

/// The rules the shipped seed files are held to, each returning one line per problem
/// that names what broke it — the list or the id, and the file — so a failing `#expect`
/// reads as the fix. Nothing here is read at run time: the engine trusts the shipped
/// files because these checks pass on them.
enum SeedTablesCheck {
    /// What must match between files for one event or fixed kind id.
    private struct Shape: Equatable {
        let symbol: String
        let hours: ClosedRange<Int>?
    }

    /// The smallest each list may be, per file — starting values settled in use
    /// (requirements §6), chosen in issue #10.
    enum Minimum {
        static let occupations = 30
        static let personalities = 20
        static let lifeStages = 6
        static let hobbies = 30
        static let eventKinds = 12
    }

    /// ``Minimum`` by list name.
    static let minimums = [
        "occupations": Minimum.occupations,
        "personalities": Minimum.personalities,
        "lifeStages": Minimum.lifeStages,
        "hobbies": Minimum.hobbies,
        "eventKinds": Minimum.eventKinds,
    ]

    /// Each list in `tables` that has ids and texts, by the name the file uses, in file
    /// order.
    static func lists(in tables: SeedTables) -> [SeedList] {
        let axes = tables.residentAxes
        return [
            list("occupations", axes.occupations),
            list("personalities", axes.personalities),
            list("lifeStages", axes.lifeStages),
            list("hobbies", axes.hobbies),
            SeedList(
                name: "eventKinds",
                ids: tables.eventKinds.map(\.id.rawValue),
                texts: tables.eventKinds.map(\.text),
            ),
        ]
    }

    /// Lists shorter than their minimum.
    static func sizeProblems(in file: SeedFile) -> [String] {
        lists(in: file.tables).compactMap { list in
            guard let minimum = minimums[list.name], list.ids.count < minimum else {
                return nil
            }
            return "\(list.name): \(list.ids.count) in \(file.name), fewer than \(minimum)"
        }
    }

    /// Ids, and texts, that appear more than once within one list.
    static func duplicateProblems(in file: SeedFile) -> [String] {
        let listed = lists(in: file.tables).flatMap { list in
            repeated(list.ids).map { "\(list.name): duplicate id \($0) in \(file.name)" }
                + repeated(list.texts).map { "\(list.name): duplicate text \($0) in \(file.name)" }
        }
        let fixed = repeated(file.tables.fixedEventKinds.map(\.id.rawValue))
            .map { "fixedEventKinds: duplicate id \($0) in \(file.name)" }
        return listed + fixed
    }

    /// Texts that are empty or carry whitespace at either end.
    static func textProblems(in file: SeedFile) -> [String] {
        lists(in: file.tables).flatMap { list in
            zip(list.ids, list.texts)
                .filter { _, text in
                    text.isEmpty || text != text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .map { id, _ in "\(list.name): \(id) text is empty or untrimmed in \(file.name)" }
        }
    }

    /// Event kinds whose hours fall outside `bounds`, the `Tuning` event-duration range in
    /// whole hours. A backwards range never gets this far: decoding rejects it.
    static func durationProblems(in file: SeedFile, within bounds: ClosedRange<Int>) -> [String] {
        file.tables.eventKinds
            .filter { kind in
                !bounds.contains(kind.hours.lowerBound) || !bounds.contains(kind.hours.upperBound)
            }
            .map { kind in
                "\(kind.id.rawValue): \(describe(kind.hours)) is outside \(describe(bounds)) in \(file.name)"
            }
    }

    /// Every way the event kinds and fixed kinds of two files disagree: an id in one and
    /// not the other, or the same id with a different symbol or range. Resident axes are
    /// each file's own and are not compared.
    static func parityProblems(_ first: SeedFile, _ second: SeedFile) -> [String] {
        let names = (first: first.name, second: second.name)
        return compare("eventKinds", (kindShapes(first), kindShapes(second)), names: names)
            + compare("fixedEventKinds", (fixedShapes(first), fixedShapes(second)), names: names)
    }

    private static func list(_ name: String, _ entries: [SeedTables.Entry]) -> SeedList {
        SeedList(name: name, ids: entries.map(\.id), texts: entries.map(\.text))
    }

    private static func kindShapes(_ file: SeedFile) -> [(id: String, shape: Shape)] {
        file.tables.eventKinds.map { kind in
            (id: kind.id.rawValue, shape: Shape(symbol: kind.symbol, hours: kind.hours))
        }
    }

    private static func fixedShapes(_ file: SeedFile) -> [(id: String, shape: Shape)] {
        file.tables.fixedEventKinds.map { kind in
            (id: kind.id.rawValue, shape: Shape(symbol: kind.symbol, hours: nil))
        }
    }

    private static func compare(
        _ list: String,
        _ files: (first: [(id: String, shape: Shape)], second: [(id: String, shape: Shape)]),
        names: (first: String, second: String),
    ) -> [String] {
        let firstShapes = Dictionary(files.first.map { ($0.id, $0.shape) }) { kept, _ in kept }
        let secondShapes = Dictionary(files.second.map { ($0.id, $0.shape) }) { kept, _ in kept }
        let missingFromSecond = files.first
            .filter { secondShapes[$0.id] == nil }
            .map { "\(list): \($0.id) missing from \(names.second)" }
        let missingFromFirst = files.second
            .filter { firstShapes[$0.id] == nil }
            .map { "\(list): \($0.id) missing from \(names.first)" }
        let differing = files.first.flatMap { entry in
            guard let theirs = secondShapes[entry.id] else {
                return [String]()
            }
            return differences("\(list): \(entry.id)", (entry.shape, theirs), names: names)
        }
        return missingFromSecond + missingFromFirst + differing
    }

    private static func differences(
        _ subject: String,
        _ shapes: (first: Shape, second: Shape),
        names: (first: String, second: String),
    ) -> [String] {
        var problems: [String] = []
        if shapes.first.symbol != shapes.second.symbol {
            problems.append(
                "\(subject) symbol \(shapes.first.symbol) in \(names.first), "
                    + "\(shapes.second.symbol) in \(names.second)",
            )
        }
        if shapes.first.hours != shapes.second.hours {
            problems.append(
                "\(subject) hours \(describe(shapes.first.hours)) in \(names.first), "
                    + "\(describe(shapes.second.hours)) in \(names.second)",
            )
        }
        return problems
    }

    private static func repeated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var repeats: [String] = []
        for value in values where !seen.insert(value).inserted && !repeats.contains(value) {
            repeats.append(value)
        }
        return repeats
    }

    private static func describe(_ range: ClosedRange<Int>?) -> String {
        guard let range else {
            return "none"
        }
        return "\(range.lowerBound)...\(range.upperBound)"
    }
}
