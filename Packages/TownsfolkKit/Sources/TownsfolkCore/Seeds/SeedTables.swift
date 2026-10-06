import Foundation

/// The keys of an event kind in a seed file. At file scope rather than inside
/// ``SeedTables/EventKind``, which would nest it two levels deep.
private enum EventKindKey: String, CodingKey {
    case hours, id, symbol, text
}

/// The read-only lists the town's rules draw from: the resident axes founding and
/// newcomers combine at random, and the event kinds the engine picks (requirements §3.1,
/// §3.6). Rules draw from them; the model never does (`docs/architecture.md` ›
/// Principles).
///
/// They ship as one file, `Resources/SeedTables.json`. A stored event keeps only its
/// kind's id, so an event kind's id is never removed or reused. The seed tests, not this
/// type, hold the file to its sizes.
public struct SeedTables: Decodable, Sendable, Equatable {
    /// One entry of a resident axis: a stable id, and the text.
    public struct Entry: Decodable, Sendable, Equatable {
        /// Unique within its axis.
        public let id: String
        /// The entry as the model is given it.
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
        /// What happens.
        public let text: String
        /// The SF Symbol an event row of this kind shows.
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
        /// The SF Symbol its event row shows.
        public let symbol: String
    }

    /// Just the version, read before the rest so a later shape is reported as a version
    /// this build does not read rather than as a broken file.
    private struct Header: Decodable {
        let version: Int
    }

    /// The format version this build reads; a file declaring another is rejected.
    public static let formatVersion = 1
    /// The file's name in a bundle, without its extension.
    package static let resourceName = "SeedTables"

    /// The file's format version, ``formatVersion`` for any table that loaded.
    public let version: Int
    /// The lists residents are seeded from.
    public let residentAxes: ResidentAxes
    /// The kinds of event the engine may start.
    public let eventKinds: [EventKind]
    /// The kinds the rules record themselves.
    public let fixedEventKinds: [FixedEventKind]

    /// The shipped tables, from Core's resource bundle.
    /// - Throws: ``SeedTablesError`` when the file is missing, does not decode, or is
    ///   another format version.
    public static func load() throws(SeedTablesError) -> Self {
        try load(from: .module)
    }

    /// The tables in `bundle`'s `SeedTables.json` — the seam a test uses to load a file it
    /// wrote.
    package static func load(from bundle: Bundle) throws(SeedTablesError) -> Self {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw .missing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .missing
        }
        return try decode(data)
    }

    /// The tables in `data`, a seed file.
    package static func decode(_ data: Data) throws(SeedTablesError) -> Self {
        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw .malformed
        }
        guard header.version == formatVersion else {
            throw .unsupportedVersion(header.version)
        }
        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            throw .malformed
        }
    }
}
