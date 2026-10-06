import Foundation

/// One of the town's people (requirements §3.1, §3.6, §3.12, §5). Residents are invented
/// by the model and never curated, so every field is checked here, where a bad draft is
/// caught before it reaches the store.
public struct Resident: Identifiable, Sendable, Equatable {
    /// Whether the resident still lives in town. A past resident stays remembered, so no
    /// one like them is invented again (requirements.md:260).
    public enum Status: Sendable, Equatable {
        /// Living here, and able to speak in scenes.
        case living
        /// Moved out; their posts stay, and they no longer speak.
        case movedOut
    }

    /// Who a resident is: the axes a scene is seeded from and a profile shows
    /// (requirements.md:139, §3.12). Grouped so a resident is built from one value.
    public struct Profile: Sendable, Equatable {
        /// Life stage, such as "teens" or "retired".
        public let ageGroup: String
        /// What they do for a living.
        public let occupation: String
        /// What they do for fun.
        public let hobby: String
        /// A current worry, which gives scenes something to return to.
        public let worry: String
        /// How they come across.
        public let personality: String

        /// Creates a profile, trimming each field at both ends.
        /// - Throws: ``TownValueError/empty(_:)`` naming the first blank field.
        public init(
            ageGroup: String,
            occupation: String,
            hobby: String,
            worry: String,
            personality: String,
        ) throws(TownValueError) {
            self.ageGroup = try TextRule.nonEmpty(ageGroup, .ageGroup)
            self.occupation = try TextRule.nonEmpty(occupation, .occupation)
            self.hobby = try TextRule.nonEmpty(hobby, .hobby)
            self.worry = try TextRule.nonEmpty(worry, .worry)
            self.personality = try TextRule.nonEmpty(personality, .personality)
        }
    }

    /// How a resident stands with another resident (requirements.md:394).
    public struct Relationship: Sendable, Equatable {
        /// The other resident.
        public let resident: EntityID<Resident>
        /// One line on what they are to each other. The documents set no length, so
        /// only one non-empty line is required.
        public let description: String

        /// Creates a relationship, trimming `description` at both ends.
        /// - Throws: ``TownValueError`` when the description is blank or spans lines.
        public init(resident: EntityID<Resident>, description: String) throws(TownValueError) {
            self.resident = resident
            self.description = try TextRule.validated(
                description,
                .relationshipDescription,
                length: TextRule.uncapped,
                singleLine: true,
            )
        }
    }

    /// The longest name, in characters (requirements.md:394).
    public static let nameMaxLength = 20
    /// The most relationships a resident keeps (requirements.md:394).
    public static let maxRelationships = 3
    /// The most interests a resident takes up (requirements.md:394).
    public static let maxInterests = 5

    /// The resident's id.
    public let id: EntityID<Self>
    /// The resident's name; names never repeat within a town (enforced by the founding
    /// and move rules, not here).
    public let name: String
    /// Who they are.
    public let profile: Profile
    /// Up to ``maxRelationships`` other residents they know.
    public let relationships: [Relationship]
    /// Up to ``maxInterests`` names you brought up that they took up as their own.
    public let interests: [EntityID<Interest>]
    /// Whether they still live here.
    public let status: Status
    /// When they moved in — founding, or their move-in event.
    public let movedInAt: Date
    /// When they moved out; set exactly when ``status`` is ``Status/movedOut``.
    public let movedOutAt: Date?

    /// Creates a resident, trimming `name` at both ends.
    /// - Throws: ``TownValueError`` for a name empty or over ``nameMaxLength``, too many
    ///   relationships or interests, a relationship to the resident itself, or a
    ///   moved-out date missing, unexpected, or before `movedInAt`.
    public init(
        id: EntityID<Self>,
        name: String,
        profile: Profile,
        movedInAt: Date,
        status: Status = .living,
        movedOutAt: Date? = nil,
        relationships: [Relationship] = [],
        interests: [EntityID<Interest>] = [],
    ) throws(TownValueError) {
        self.name = try TextRule.validated(
            name,
            .residentName,
            length: 1 ... Self.nameMaxLength,
            singleLine: false,
        )
        try TextRule.checkCount(
            relationships.count,
            .relationships,
            allowed: 0 ... Self.maxRelationships,
        )
        guard !relationships.contains(where: { $0.resident == id }) else {
            throw .selfReference(.relationships)
        }
        try TextRule.checkCount(interests.count, .interests, allowed: 0 ... Self.maxInterests)
        try Self.checkMoveOut(status: status, movedInAt: movedInAt, movedOutAt: movedOutAt)
        self.id = id
        self.profile = profile
        self.relationships = relationships
        self.interests = interests
        self.status = status
        self.movedInAt = movedInAt
        self.movedOutAt = movedOutAt
    }

    private static func checkMoveOut(
        status: Status,
        movedInAt: Date,
        movedOutAt: Date?,
    ) throws(TownValueError) {
        switch (status, movedOutAt) {
        case (.living, nil):
            return

        case (.living, .some):
            throw .notAllowed(.movedOutAt)

        case (.movedOut, nil):
            throw .required(.movedOutAt)

        case let (.movedOut, .some(date)):
            guard date >= movedInAt else {
                throw .outOfOrder(.movedOutAt)
            }
        }
    }
}
