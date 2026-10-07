import Foundation

extension TownStore.FoundingStep {
    /// The first scene's posts follow the founding row a millisecond apart — the store's
    /// precision — so they sort above it in order and are all already due when the
    /// timeline opens, rather than waiting to be revealed.
    private static let postSpacing: TimeInterval = 0.001

    /// A founded town as it is stored at `storedAt`: the town, its residents moving in,
    /// the founding row "You moved to {town}.", and a schedule whose next ordinary scene is
    /// due at the founding — the store needs a time there, and the engine's first step
    /// sets the real one (#19) — all at the founding time; then the first scene's posts
    /// a millisecond apart after it, the last at `storedAt`. Every row is therefore at or
    /// before `storedAt`, and the founding row is the oldest (ux-flows S3: S1 opens on the
    /// founding row with the first scene above it).
    ///
    /// - Throws: ``TownValueError`` when a value no longer passes its own checks, which a
    ///   founded town that passed them once cannot.
    init(
        town: Town,
        residents: [Resident],
        firstScene: WrittenScene,
        storedAt: Date,
        tuning: Tuning,
    ) throws(TownValueError) {
        let foundedAt = storedAt.addingTimeInterval(
            -Self.postSpacing * TimeInterval(firstScene.posts.count),
        )
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

    /// The posts of `scene`, a millisecond apart after `start`, with replies pointed at real
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
