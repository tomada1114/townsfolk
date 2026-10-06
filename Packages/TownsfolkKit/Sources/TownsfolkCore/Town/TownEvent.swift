import Foundation

/// Something that happens in town — weather, a festival, a power cut — or a move, or the
/// founding row (requirements §3.6, §5). Named `TownEvent` so it does not read as a UI or
/// system event.
public struct TownEvent: Identifiable, Sendable, Equatable {
    /// Whether the event is still going on; an ended event stays in the log as the town's
    /// history (requirements.md:257).
    public enum Status: Sendable, Equatable {
        /// Over.
        case ended
        /// Still going on, and fed to scenes and the status line.
        case ongoing
    }

    /// The longest description, in characters (requirements.md:396).
    public static let descriptionMaxLength = 120

    /// The event's id.
    public let id: EntityID<Self>
    /// Which kind of event this is, from the seed tables.
    public let kind: EventKindID
    /// One line, shown as the event row.
    public let description: String
    /// When it starts, in town time.
    public let startsAt: Date
    /// When it ends, in town time; never before ``startsAt``.
    public let endsAt: Date
    /// Whether it is still going on.
    public let status: Status
    /// The resident it is about — always set for a move.
    public let relatedResident: EntityID<Resident>?

    /// Creates an event, trimming `description` at both ends.
    /// - Throws: ``TownValueError`` for an empty kind, a description blank, over
    ///   ``descriptionMaxLength``, or spanning lines, an end before the start, or a move
    ///   without its resident.
    public init(
        id: EntityID<Self>,
        kind: EventKindID,
        description: String,
        startsAt: Date,
        endsAt: Date,
        status: Status = .ongoing,
        relatedResident: EntityID<Resident>? = nil,
    ) throws(TownValueError) {
        guard !kind.rawValue.isEmpty else {
            throw .empty(.eventKind)
        }
        self.description = try TextRule.validated(
            description,
            .eventDescription,
            length: 1 ... Self.descriptionMaxLength,
            singleLine: true,
        )
        guard endsAt >= startsAt else {
            throw .outOfOrder(.endsAt)
        }
        if kind == .moveIn || kind == .moveOut, relatedResident == nil {
            throw .required(.relatedResident)
        }
        self.id = id
        self.kind = kind
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.status = status
        self.relatedResident = relatedResident
    }
}
