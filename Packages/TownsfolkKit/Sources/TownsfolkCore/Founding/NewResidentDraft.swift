import Foundation
import FoundationModels

/// What a call inventing one resident asks the model to write: a name, a current worry,
/// and how they know the residents already in town (requirements §3.1, :394). Declared
/// once, here, for founding and for the newcomers who move in later (`TownEngine`).
///
/// The rest of a profile — life stage, occupation, personality, hobby — is drawn from
/// the seed tables by rules and handed to the model, never invented by it
/// (`docs/architecture.md` › Principles). The guides state the limits, which
/// ``Founder`` checks again; their numbers mirror ``Resident/nameMaxLength`` (20) and
/// ``Resident/maxRelationships`` (3).
@Generable
public struct NewResidentDraft: Equatable, Sendable {
    /// How the new resident stands with one resident already in town.
    @Generable
    public struct RelationshipDraft: Equatable, Sendable {
        /// The other resident's name, matched against the residents already in town.
        @Guide(
            description: "The name of a resident listed under Residents so far, exactly as written there.",
        )
        public var name: String
        /// What they are to each other.
        @Guide(description: "One line on what the two of them are to each other.")
        public var description: String

        /// Creates a relationship draft, as a test scripts the model's answer.
        public init(name: String, description: String) {
            self.name = name
            self.description = description
        }
    }

    /// The new resident's name.
    @Guide(description: "One first name, at most 20 characters, unlike every name already taken.")
    public var name: String
    /// Something everyday the resident is worried about now.
    @Guide(
        description: "A short phrase, not a sentence, naming something everyday this resident is worried about now.",
    )
    public var worry: String
    /// How the resident knows residents already in town.
    @Guide(
        description: "How this resident knows residents listed under Residents so far; empty when there are none.",
        .maximumCount(Resident.maxRelationships),
    )
    public var relationships: [RelationshipDraft]

    /// Creates a resident draft, as a test scripts the model's answer.
    public init(name: String, worry: String, relationships: [RelationshipDraft]) {
        self.name = name
        self.worry = worry
        self.relationships = relationships
    }
}

extension NewResidentDraft {
    /// Whether two names are the same once trimmed, ignoring case.
    private static func same(_ name: String, _ other: String) -> Bool {
        let trimmed = other.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.caseInsensitiveCompare(trimmed) == .orderedSame
    }

    /// The resident this draft describes, seeded from `seed`, moving in at `movedInAt`
    /// among `earlier` — the residents already invented, whose names are taken and whom
    /// alone a relationship may name. `past` — a newcomer's past residents — holds names
    /// taken too, which no relationship names. A relationship naming anyone else, or
    /// naming the same resident twice, is dropped; names are compared trimmed and
    /// ignoring case.
    ///
    /// - Throws: ``FoundingFailure/repeatedName`` for a name an earlier or past resident
    ///   has, and ``FoundingFailure/invalidResident`` for more than
    ///   ``Resident/maxRelationships`` relationships, or a name, worry, or kept
    ///   relationship outside its limits.
    func resident(
        id: Resident.ID,
        seed: ResidentSeed,
        among earlier: [Resident],
        alsoTaken past: [Resident],
        movedInAt: Date,
    ) throws(FoundingFailure) -> Resident {
        guard relationships.count <= Resident.maxRelationships else {
            throw .invalidResident
        }
        let resident: Resident
        do throws(TownValueError) {
            var kept: [Resident.Relationship] = []
            for relationship in relationships {
                guard let other = earlier.first(where: { Self.same($0.name, relationship.name) }),
                      !kept.contains(where: { $0.resident == other.id })
                else {
                    continue
                }
                try kept.append(Resident.Relationship(
                    resident: other.id,
                    description: relationship.description,
                ))
            }
            resident = try Resident(
                id: id,
                name: name,
                profile: Resident.Profile(
                    ageGroup: seed.lifeStage.text,
                    occupation: seed.occupation.text,
                    hobby: seed.hobby.text,
                    worry: worry,
                    personality: seed.personality.text,
                ),
                movedInAt: movedInAt,
                relationships: kept,
            )
        } catch {
            throw .invalidResident
        }
        guard !(earlier + past).contains(where: { Self.same($0.name, resident.name) }) else {
            throw .repeatedName
        }
        return resident
    }
}
