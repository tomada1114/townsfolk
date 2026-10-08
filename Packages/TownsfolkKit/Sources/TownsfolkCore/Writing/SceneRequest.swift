/// Why a ``SceneRequest`` was refused. A refused request is the caller's mistake — the
/// engine and founding choose the speakers and seeds — so it is caught when the request
/// is made rather than met as a skipped turn. No case carries a name or a text.
public enum SceneRequestError: Error, Equatable, Sendable {
    /// The same seed is in the list twice.
    case duplicateSeed
    /// The same speaker is in the list twice.
    case duplicateSpeaker
    /// A seed's lead speaker is not one of the speakers.
    case leadNotSpeaker
    /// The request carries this many seeds, outside ``SceneRequest/seedCount``.
    case seedCount(Int)
    /// A post seed is not one of your posts.
    case seedPostNotYours
    /// The request carries this many speakers, outside ``SceneRequest/speakerCount``.
    case speakerCount(Int)
    /// A speaker is not a living resident of the roster.
    case speakerNotLiving
    /// A relationship seed names a link absent from its owner's stored profile.
    case unknownRelationship
    /// A profile seed's owner or relationship partner is absent from the roster.
    case unknownResident
}

/// Everything the caller decides about one scene (requirements §3.2, REQ-002): who you
/// are, the town, the roster, who speaks, and which seeds to try in which order. The
/// store adds only recent posts, ongoing events, and names, so founding can write its
/// first scene before anything is stored.
public struct SceneRequest: Sendable, Equatable {
    /// How many residents speak in one scene (requirements.md:161).
    public static let speakerCount = 1 ... 3
    /// How many seeds one turn may try (requirements.md:349: the first, then up to two
    /// retries after a refusal).
    public static let seedCount = 1 ... 3

    /// Your display name, under which your posts are quoted.
    public let you: DisplayName
    /// The town the scene happens in.
    public let town: Town
    /// Every resident, living and moved out: the only people a scene may mention.
    public let residents: [Resident]
    /// The residents who may write the scene's posts, in the caller's order.
    public let speakers: [Resident.ID]
    /// The seeds to try, first to last; each refusal moves to the next.
    public let seeds: [SceneSeed]

    /// The speakers, as residents.
    var speakingResidents: [Resident] {
        speakers.compactMap { speaker in residents.first { $0.id == speaker } }
    }

    /// Creates a request.
    /// - Throws: ``SceneRequestError`` for speakers or seeds outside their counts or
    ///   repeated, a speaker who is not a living resident of `residents`, a profile seed
    ///   of someone not in `residents`, a post seed that is not yours, or a lead speaker
    ///   who is not speaking, or a relationship seed without its stored link or roster partner.
    public init(
        you: DisplayName,
        town: Town,
        residents: [Resident],
        speakers: [Resident.ID],
        seeds: [SceneSeed],
    ) throws(SceneRequestError) {
        try Self.check(speakers: speakers, in: residents)
        guard Self.seedCount.contains(seeds.count) else {
            throw .seedCount(seeds.count)
        }
        for (index, seed) in seeds.enumerated() {
            guard !seeds[..<index].contains(seed) else {
                throw .duplicateSeed
            }
            try Self.check(seed, speakers: speakers, residents: residents)
        }
        self.you = you
        self.town = town
        self.residents = residents
        self.speakers = speakers
        self.seeds = seeds
    }

    private static func check(
        speakers: [Resident.ID],
        in residents: [Resident],
    ) throws(SceneRequestError) {
        guard speakerCount.contains(speakers.count) else {
            throw .speakerCount(speakers.count)
        }
        guard Set(speakers).count == speakers.count else {
            throw .duplicateSpeaker
        }
        for speaker in speakers {
            guard residents.contains(where: { $0.id == speaker && $0.status == .living }) else {
                throw .speakerNotLiving
            }
        }
    }

    private static func check(
        _ seed: SceneSeed,
        speakers: [Resident.ID],
        residents: [Resident],
    ) throws(SceneRequestError) {
        switch seed {
        case .event, .name, .topic:
            return

        case let .profile(id, aspect):
            guard let resident = residents.first(where: { $0.id == id }) else {
                throw .unknownResident
            }
            if case let .relationship(partner) = aspect {
                guard residents.contains(where: { $0.id == partner }) else {
                    throw .unknownResident
                }
                guard resident.relationships.contains(where: { $0.resident == partner }) else {
                    throw .unknownRelationship
                }
            }

        case let .yourPost(post, _, lead):
            guard post.author == .you else {
                throw .seedPostNotYours
            }
            if let lead, !speakers.contains(lead) {
                throw .leadNotSpeaker
            }
        }
    }
}
