import Foundation

/// The keys of an event kind in a seed file. At file scope rather than inside
/// ``SeedTables/EventKind``, which would nest it two levels deep.
private enum EventKindKey: String, CodingKey {
    case hours, id, symbol, text
}

/// The read-only lists the town's rules draw from, for one ``TownLanguage``: the resident
/// axes founding and newcomers combine at random, and the event kinds the engine picks
/// (requirements §3.1, §3.6). Rules draw from them; the model never does
/// (`docs/architecture.md` › Principles).
///
/// Each language ships its own file, `Resources/Seeds/<language>.json` (ADR-0007). The
/// resident axes are that language's own; the event kinds and fixed kinds share their ids,
/// symbols, and durations across files, because a stored event keeps only its kind's id
/// and must still render after a language switch. The seed tests, not this type, hold the
/// files to their sizes and to that agreement.
public struct SeedTables: Decodable, Sendable, Equatable {
    /// One entry of a resident axis: an id that stays English, and the text in the file's
    /// language.
    public struct Entry: Decodable, Sendable, Equatable {
        /// Unique within its axis and file; English in every file.
        public let id: String
        /// The entry as the model is given it, in the file's language.
        public let text: String
    }

    /// The four lists a resident is seeded from, one entry of each (requirements §3.1).
    public struct ResidentAxes: Decodable, Sendable, Equatable {
        /// What a resident does for a living.
        public let occupations: [Entry]
        /// What a resident is like.
        public let personalities: [Entry]
        /// Where a resident is in life.
        public let lifeStages: [Entry]
        /// What a resident does for fun.
        public let hobbies: [Entry]
    }

    /// A kind of event the engine may start at random (requirements §3.6).
    public struct EventKind: Decodable, Sendable, Equatable {
        /// `hours` is written as `[lower, upper]`.
        private static let boundsPerRange = 2

        /// Stored with every event of this kind, so it is never removed or reused.
        public let id: EventKindID
        /// What happens, in the file's language.
        public let text: String
        /// The SF Symbol an event row of this kind shows (ADR-0008).
        public let symbol: String
        /// How long an event of this kind lasts, in whole hours of town time.
        public let hours: ClosedRange<Int>

        /// Decodes `hours` from a `[lower, upper]` pair.
        /// - Throws: `DecodingError.dataCorrupted` naming the kind's id when `hours` is not
        ///   exactly two numbers with the first no greater than the second — a range that
        ///   cannot be formed must fail to load, never trap.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: EventKindKey.self)
            id = try container.decode(EventKindID.self, forKey: .id)
            text = try container.decode(String.self, forKey: .text)
            symbol = try container.decode(String.self, forKey: .symbol)
            let bounds = try container.decode([Int].self, forKey: .hours)
            guard bounds.count == Self.boundsPerRange, let lower = bounds.first,
                  let upper = bounds.last,
                  lower <= upper
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .hours,
                    in: container,
                    debugDescription: "\(id.rawValue): hours must be [lower, upper] with lower <= upper",
                )
            }
            hours = lower ... upper
        }
    }

    /// A kind the rules record themselves and never draw — a move in, a move out, the
    /// founding row — listed so every event row's symbol is found in one place.
    public struct FixedEventKind: Decodable, Sendable, Equatable {
        /// One of ``EventKindID``'s constants.
        public let id: EventKindID
        /// The SF Symbol its event row shows (ADR-0008).
        public let symbol: String
    }

    /// Just the version, read before the rest so a later shape is reported as a version
    /// this build does not read rather than as a broken file.
    private struct Header: Decodable {
        let version: Int
    }

    /// The format version this build reads; a file declaring another is rejected.
    public static let formatVersion = 1

    /// The file's format version, ``formatVersion`` for any table that loaded.
    public let version: Int
    /// The lists residents are seeded from.
    public let residentAxes: ResidentAxes
    /// The kinds of event the engine may start.
    public let eventKinds: [EventKind]
    /// The kinds the rules record themselves.
    public let fixedEventKinds: [FixedEventKind]

    /// The tables shipped for `language`, from Core's resource bundle.
    /// - Throws: ``SeedTablesError`` naming `language` when its file is missing, does
    ///   not decode, or is another format version.
    public static func load(for language: TownLanguage) throws(SeedTablesError) -> Self {
        try load(for: language, from: .module)
    }

    /// The tables for `language` from `bundle`'s `<language>.json` — the seam a test uses
    /// to load a file it wrote.
    package static func load(
        for language: TownLanguage,
        from bundle: Bundle,
    ) throws(SeedTablesError) -> Self {
        guard let url = bundle.url(forResource: language.rawValue, withExtension: "json") else {
            throw .missing(language)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .missing(language)
        }
        return try decode(data, for: language)
    }

    /// The tables in `data`, a seed file written for `language`.
    package static func decode(
        _ data: Data,
        for language: TownLanguage,
    ) throws(SeedTablesError) -> Self {
        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw .malformed(language)
        }
        guard header.version == formatVersion else {
            throw .unsupportedVersion(language, version: header.version)
        }
        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            throw .malformed(language)
        }
    }
}
