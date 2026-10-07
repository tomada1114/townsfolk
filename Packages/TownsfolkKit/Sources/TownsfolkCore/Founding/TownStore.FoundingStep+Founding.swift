import Foundation

extension TownStore.FoundingStep {
    /// The first scene's posts follow the founding row a second apart, so all of them show
    /// at once when the timeline opens.
    private static let postSpacing: TimeInterval = 1

    /// A founded town as it is stored, every time set to `foundedAt`: the town, its
    /// residents moving in, the founding row "You moved to {town}.", the first scene's
    /// posts just after it, and a schedule whose next ordinary scene is due at founding —
    /// the store needs a time there, and the engine's first step sets the real one (#19).
    ///
    /// - Throws: ``TownValueError`` when a value no longer passes its own checks, which a
    ///   founded town that passed them once cannot.
    init(
        town: Town,
        residents: [Resident],
        firstScene: WrittenScene,
        foundedAt: Date,
        tuning: Tuning,
    ) throws(TownValueError) {
        var settled: [Resident] = []
        for resident in residents {
            try settled.append(Resident(
                id: resident.id,
                name: resident.name,
                profile: resident.profile,
                movedInAt: foundedAt,
                relationships: resident.relationships,
            ))
        }
        try self.init(
            town: Town(
                name: town.name,
                setting: town.setting,
                places: town.places,
                foundedAt: foundedAt,
                tuning: tuning,
            ),
            residents: settled,
            foundingEvent: TownEvent(
                id: TownEvent.ID(),
                kind: .founding,
                description: String(localized: FoundingWording.movedTo(town: town.name)),
                startsAt: foundedAt,
                endsAt: foundedAt,
                status: .ended,
            ),
            schedule: Schedule(nextOrdinarySceneDue: foundedAt, lastRanAt: foundedAt),
            firstScene: TownStore.SceneStep(
                posts: Self.posts(of: firstScene, after: foundedAt, tuning: tuning),
            ),
        )
    }

    /// The posts of `scene`, a second apart after `start`, with replies pointed at real
    /// post ids, the scene's tags on each, and one scene id.
    private static func posts(
        of scene: WrittenScene,
        after start: Date,
        tuning: Tuning,
    ) throws(TownValueError) -> [Post] {
        let sceneID = SceneID()
        let ids = scene.posts.map { _ in Post.ID() }
        var posts: [Post] = []
        for (index, (written, id)) in zip(scene.posts, ids).enumerated() {
            let target: Post.ID? = switch written.replyTarget {
            case let .earlierInScene(earlier)?:
                ids.indices.contains(earlier) ? ids[earlier] : nil

            case let .post(post)?:
                post

            case nil:
                nil
            }
            try posts.append(Post(
                id: id,
                author: .resident(written.speaker),
                text: written.text,
                happenedAt: start.addingTimeInterval(postSpacing * TimeInterval(index + 1)),
                replyTarget: target,
                topicTags: scene.topicTags,
                origin: .ordinary,
                sceneID: sceneID,
                tuning: tuning,
            ))
        }
        return posts
    }
}
