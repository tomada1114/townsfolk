/// Who speaks in an ordinary scene and which seeds the writer tries (requirements.md:161–
/// :163): drawn by rules, never by the model (`docs/architecture.md` › Principles).
///
/// The draws, in order: the first seed — its kind uniformly among the kinds that have a
/// candidate, then a candidate of that kind uniformly; the speaker count, uniform within
/// 1 to 3 and no more than live in town; the speakers, the first seed's resident first and
/// the rest uniformly among the other living residents; then up to two more seeds the same
/// way as the first, among the speakers' profiles and the topics left, for the writer's
/// refusal retries. A profile seed's resident therefore always speaks.
struct SceneCasting {
    /// The scene's speakers and seeds.
    struct Cast: Equatable {
        let speakers: [Resident.ID]
        let seeds: [SceneSeed]
    }

    /// The parts of a profile a seed may be about, in the order candidates are listed.
    private static let aspects: [SceneSeed.ProfileAspect] = [
        .occupation, .hobby, .worry, .personality,
    ]

    /// Every resident, living and moved out, in the store's order.
    let residents: [Resident]
    /// The topic tags of the recent window, newest first, each once.
    let topics: [String]

    private static func profileSeeds(of residents: [Resident.ID]) -> [SceneSeed] {
        residents.flatMap { resident in aspects.map { SceneSeed.profile(resident, $0) } }
    }

    /// Draws one seed out of `profiles` or `topics`, removing it there; `nil` when both
    /// are empty.
    private static func drawSeed(
        profiles: inout [SceneSeed],
        topics: inout [SceneSeed],
        using generator: inout some RandomNumberGenerator,
    ) -> SceneSeed? {
        let kinds = [profiles.isEmpty ? nil : 0, topics.isEmpty ? nil : 1].compactMap(\.self)
        guard !kinds.isEmpty else {
            return nil
        }
        if kinds[generator.nextIndex(below: kinds.count)] == 0 {
            return profiles.remove(at: generator.nextIndex(below: profiles.count))
        }
        return topics.remove(at: generator.nextIndex(below: topics.count))
    }

    /// The cast of one scene, or `nil` when nobody lives in town.
    func cast(using generator: inout some RandomNumberGenerator) -> Cast? {
        let living = residents.filter { $0.status == .living }.map(\.id)
        // Before any draw: a topic is a seed even with nobody left to speak about it.
        guard !living.isEmpty else {
            return nil
        }
        let topicSeeds = topics.map(SceneSeed.topic)
        var profiles = Self.profileSeeds(of: living)
        var openTopics = topicSeeds
        guard let first = Self.drawSeed(
            profiles: &profiles,
            topics: &openTopics,
            using: &generator,
        ) else {
            return nil
        }
        let count = 1 + generator.nextIndex(
            below: min(SceneRequest.speakerCount.upperBound, living.count),
        )
        var speakers: [Resident.ID] = []
        var others = living
        if case let .profile(resident, _) = first {
            speakers.append(resident)
            others.removeAll { $0 == resident }
        }
        while speakers.count < count {
            speakers.append(others.remove(at: generator.nextIndex(below: others.count)))
        }
        var seeds = [first]
        profiles = Self.profileSeeds(of: living.filter(speakers.contains)).filter { $0 != first }
        openTopics = topicSeeds.filter { $0 != first }
        while seeds.count < SceneRequest.seedCount.upperBound {
            guard let next = Self.drawSeed(
                profiles: &profiles,
                topics: &openTopics,
                using: &generator,
            ) else {
                break
            }
            seeds.append(next)
        }
        return Cast(speakers: speakers, seeds: seeds)
    }
}
