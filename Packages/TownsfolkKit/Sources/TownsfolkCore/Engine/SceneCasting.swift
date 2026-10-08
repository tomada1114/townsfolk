/// Who speaks in an ordinary scene and which seeds the writer tries (requirements.md:161–
/// :163): drawn by rules, never by the model (`docs/architecture.md` › Principles).
///
/// The draws, in order: the first seed — its kind uniformly among the kinds that have a
/// candidate (a profile, a topic, an ongoing event), then a candidate of that kind
/// uniformly; the speaker count, uniform within 1 to 3 and no more than live in town; the
/// speakers, the first seed's resident first and the rest uniformly among the other
/// living residents; then up to two more seeds the same way as the first, among the
/// speakers' profiles and the topics and events left, for the writer's refusal retries. A
/// profile seed's resident therefore always speaks.
///
/// After a move the first seed is that move's event, drawn from nothing, and after a
/// move-in the newcomer speaks first (REQ-009 of #25).
struct SceneCasting {
    /// The scene's speakers and seeds.
    struct Cast: Equatable {
        let speakers: [Resident.ID]
        let seeds: [SceneSeed]
    }

    /// A move the next scene is about: its event, and the newcomer after a move-in.
    struct News: Equatable {
        let event: TownEvent
        let newcomer: Resident.ID?
    }

    /// The parts of a profile a seed may be about, in the order candidates are listed.
    private static let aspects: [SceneSeed.ProfileAspect] = [
        .occupation, .hobby, .worry, .personality,
    ]

    /// Every resident, living and moved out, in the store's order.
    let residents: [Resident]
    /// The topic tags of the recent window, newest first, each once.
    let topics: [String]
    /// The events still going on, earliest first.
    var events: [TownEvent] = []
    /// Included names, in the store's order; an empty pool adds no draw.
    var names: [Interest] = []
    /// The move this scene is about, if one just happened.
    var news: News?

    private static func profileSeeds(of residents: [Resident.ID]) -> [SceneSeed] {
        residents.flatMap { resident in aspects.map { SceneSeed.profile(resident, $0) } }
    }

    /// Draws one seed — a kind uniformly among the pools that hold a candidate, then a
    /// candidate of it uniformly — removing it there; `nil` when every pool is empty. A
    /// town with no ongoing event draws exactly as before events existed.
    private static func drawSeed(
        from pools: inout [[SceneSeed]],
        using generator: inout some RandomNumberGenerator,
    ) -> SceneSeed? {
        let kinds = pools.indices.filter { !pools[$0].isEmpty }
        guard !kinds.isEmpty else {
            return nil
        }
        let kind = kinds[generator.nextIndex(below: kinds.count)]
        return pools[kind].remove(at: generator.nextIndex(below: pools[kind].count))
    }

    /// The cast of one scene, or `nil` when nobody lives in town.
    func cast(using generator: inout some RandomNumberGenerator) -> Cast? {
        let living = residents.filter { $0.status == .living }.map(\.id)
        // Before any draw: a topic is a seed even with nobody left to speak about it.
        guard !living.isEmpty else {
            return nil
        }
        let topicSeeds = topics.map(SceneSeed.topic)
        let eventSeeds = events.map(SceneSeed.event)
        let nameSeeds = names.map(SceneSeed.name)
        var pools = [Self.profileSeeds(of: living), topicSeeds, eventSeeds, nameSeeds]
        guard let first = news.map({ SceneSeed.event($0.event) })
            ?? Self.drawSeed(from: &pools, using: &generator)
        else {
            return nil
        }
        let count = 1 + generator.nextIndex(
            below: min(SceneRequest.speakerCount.upperBound, living.count),
        )
        var speakers: [Resident.ID] = []
        if case let .profile(resident, _) = first {
            speakers.append(resident)
        } else if let newcomer = news?.newcomer, living.contains(newcomer) {
            speakers.append(newcomer)
        }
        var others = living.filter { !speakers.contains($0) }
        while speakers.count < count {
            speakers.append(others.remove(at: generator.nextIndex(below: others.count)))
        }
        var seeds = [first]
        pools = [
            Self.profileSeeds(of: living.filter(speakers.contains)),
            topicSeeds,
            eventSeeds,
            nameSeeds,
        ].map { $0.filter { $0 != first } }
        while seeds.count < SceneRequest.seedCount.upperBound {
            guard let next = Self.drawSeed(from: &pools, using: &generator) else {
                break
            }
            seeds.append(next)
        }
        return Cast(speakers: speakers, seeds: seeds)
    }
}
