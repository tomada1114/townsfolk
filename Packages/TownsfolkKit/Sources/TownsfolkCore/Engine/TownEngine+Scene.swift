import Foundation

/// A written scene that cannot become stored posts: a post breaks a rule of ``Post``, or
/// replies to a post not earlier in the scene.
struct InvalidSceneError: Error {}

/// One ordinary scene: casting it, asking the writer, and storing what comes back
/// (requirements §3.2, §3.4; `docs/architecture.md` › Core flows, "A scene").
extension TownEngine {
    /// The scene's posts with their ids, times, origin, scene, and tags — a reply to an
    /// earlier post of the scene pointed at that post's new id.
    /// - Throws: ``InvalidSceneError`` when a post breaks a rule of ``Post`` or replies to
    ///   a post not earlier in the scene; a refused post is logged with its rule.
    static func posts(
        of scene: WrittenScene,
        at times: [Date],
        tuning: Tuning,
        response: Schedule.PendingResponse?,
    ) throws(InvalidSceneError) -> [Post] {
        let ids = scene.posts.map { _ in Post.ID() }
        let sceneID = SceneID()
        var posts: [Post] = []
        for (index, (written, time)) in zip(scene.posts, times).enumerated() {
            var target: Post.ID?
            switch written.replyTarget {
            case nil:
                target = index == 0 ? response?.post : nil

            case let .post(id):
                target = id

            case let .earlierInScene(earlier):
                guard (0 ..< index).contains(earlier) else {
                    throw InvalidSceneError()
                }
                target = ids[earlier]
            }
            do {
                try posts.append(Post(
                    id: ids[index],
                    author: .resident(written.speaker),
                    text: written.text,
                    happenedAt: time,
                    replyTarget: target,
                    topicTags: scene.topicTags,
                    origin: response == nil ? .ordinary : .response,
                    sceneID: sceneID,
                    tuning: tuning,
                ))
            } catch {
                EngineLog.recordRejectedPost(error)
                throw InvalidSceneError()
            }
        }
        return posts
    }

    static func posts(
        of scene: WrittenScene,
        at times: [Date],
        tuning: Tuning,
    ) throws(InvalidSceneError) -> [Post] {
        try posts(of: scene, at: times, tuning: tuning, response: nil)
    }

    /// Skips a due turn: stores only a new due time, now plus a drawn interval (REQ-005).
    func skip(_ reason: EngineSkipReason, at now: Date) async -> EngineStep {
        let factor = pace.drawFactor(using: &generator)
        let due = pace.due(after: now, speed: settings.speed, factor: factor)
        let hasDueResponse: Bool
        do throws(TownStoreError) {
            hasDueResponse = try await store.schedule()?.pendingResponses
                .contains { $0.dueAt <= now } ?? false
            try await store.setNextOrdinarySceneDue(due)
        } catch {
            return .failed(error)
        }
        pending = Pending(anchor: now, factor: factor)
        responseRetryAt = hasDueResponse ? due : nil
        return .skipped(reason, nextDue: due)
    }

    /// Casts the due scene, asks the writer for it, and stores it (REQ-003, REQ-004). A
    /// move's news seeds it, and an ongoing event may (REQ-009 of #25).
    func writeScene(
        at now: Date,
        response: Schedule.PendingResponse?,
    ) async throws -> EngineStep {
        guard let you = settings.displayName else {
            return await skip(.noDisplayName, at: now)
        }
        let town: Town
        let casting: SceneCasting
        do throws(TownStoreError) {
            guard let founded = try await store.town() else {
                return .notFounded
            }
            town = founded
            casting = try await SceneCasting(
                residents: store.residents(),
                topics: store.recentTopicTags(before: now),
                events: store.ongoingEvents(),
                news: news,
            )
        } catch {
            return .failed(error)
        }
        guard let ordinary = casting.cast(using: &generator) else {
            return await skip(.noSpeakers, at: now)
        }
        let cast: SceneCasting.Cast
        do throws(TownStoreError) {
            cast = try await responseCast(ordinary, response: response, casting: casting, at: now)
        } catch { return .failed(error) }
        let request: SceneRequest
        do throws(SceneRequestError) {
            request = try SceneRequest(
                you: you,
                town: town,
                residents: casting.residents,
                speakers: cast.speakers,
                seeds: cast.seeds,
            )
        } catch {
            return await skip(.invalidRequest(error), at: now)
        }
        let outcome = try await writer.write(request, at: now)
        do throws(TownStoreError) { try await prepareResponses() } catch { return .failed(error) }
        return try await finishScene(outcome, at: now, response: response)
    }

    private func finishScene(
        _ outcome: SceneOutcome,
        at now: Date,
        response: Schedule.PendingResponse?,
    ) async throws -> EngineStep {
        switch outcome {
        case .skipped(.unavailable):
            return .modelUnavailable

        case let .skipped(reason):
            return await skip(.writer(reason), at: now)

        case let .written(scene):
            if case let .yourPost(post, _, _) = scene.seed {
                do throws(TownStoreError) {
                    guard try await store.responsePost(post.id) != nil else {
                        return await skip(.writer(.refused), at: now)
                    }
                } catch { return .failed(error) }
            }
            let delivered = deliveredResponse(for: scene, pending: response)
            let stored = try await storeWritten(scene, at: now, response: delivered)
            // The news stays until a scene is stored: a scene discarded, refused by the
            // store, or cancelled leaves the next turn to tell it.
            if case let .sceneStored(_, nextDue: due) = stored {
                if delivered == nil {
                    news = nil
                }
                responseRetryAt = response != nil && delivered == nil ? due : nil
            }
            return stored
        }
    }

    private func deliveredResponse(
        for scene: WrittenScene,
        pending: Schedule.PendingResponse?,
    ) -> Schedule.PendingResponse? {
        guard case let .yourPost(post, quoted: true, _) = scene.seed,
              post.id == pending?.post else { return nil }
        return pending
    }

    /// Stores a written scene in one transaction: its posts, the first at `now` and each
    /// next one a reveal gap later, and the next due time from its last post (REQ-004).
    /// A failed transaction keeps nothing and leaves the old due time (REQ-009).
    private func storeWritten(
        _ scene: WrittenScene,
        at now: Date,
        response: Schedule.PendingResponse?,
    ) async throws -> EngineStep {
        let speed = settings.speed
        let times = pace.revealTimes(
            count: scene.posts.count,
            from: now,
            speed: speed,
            using: &generator,
        )
        let factor = pace.drawFactor(using: &generator)
        let posts: [Post]
        do throws(InvalidSceneError) {
            posts = try Self.posts(of: scene, at: times, tuning: tuning, response: response)
        } catch {
            return await skip(.invalidScene, at: now)
        }
        guard let last = times.last else {
            return await skip(.invalidScene, at: now)
        }
        let due = pace.due(after: last, speed: speed, factor: factor)
        do throws(TownStoreError) {
            try await store.storeScene(TownStore.SceneStep(
                posts: posts,
                deliveredResponse: response,
                nextOrdinarySceneDue: due,
            ))
        } catch .cancelled {
            throw CancellationError()
        } catch {
            return .failed(error)
        }
        pending = Pending(anchor: last, factor: factor)
        responseRetryAt = nil
        if response != nil {
            EngineLog.recordResponseStored(posts.count)
        }
        return .sceneStored(posts: posts.map(\.id), nextDue: due)
    }
}
