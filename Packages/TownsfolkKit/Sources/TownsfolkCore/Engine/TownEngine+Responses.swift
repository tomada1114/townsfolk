import Foundation

/// Your posts schedule delayed scenes through the same writer as ordinary scenes.
extension TownEngine {
    /// A fallback's profile owner must still be one of the final speakers.
    private static func seed(_ seed: SceneSeed, fits speakers: [Resident.ID]) -> Bool {
        switch seed {
        case let .profile(resident, _):
            speakers.contains(resident)

        case .event, .name, .topic:
            true

        case .yourPost:
            false
        }
    }

    /// Handles a committed store change. Also used by the run loop's subscription.
    func responseChange(_ change: TownStoreChange) async {
        guard affectsResponses(change) else {
            return
        }
        while isBusy {
            await untilIdle()
        }
        guard !Task.isCancelled else {
            return
        }
        isBusy = true
        defer { becomeIdle(); nap?.cancel() }
        do throws(TownStoreError) {
            try await responseWrite(change)
        } catch {
            EngineLog.record(.failed(error))
        }
    }

    private func affectsResponses(_ change: TownStoreChange) -> Bool {
        switch change {
        case .yourPostStored, .postExcluded:
            true

        case .eventEnded, .eventStarted, .everythingDeleted, .founded:
            false

        case .interestExcluded, .lastRanChanged, .moveRecorded:
            false

        case .nextOrdinarySceneDueChanged, .pendingResponsesChanged, .sceneStored:
            false
        }
    }

    private func responseWrite(_ change: TownStoreChange) async throws(TownStoreError) {
        switch change {
        case let .yourPostStored(id):
            let post = try await store.responsePost(id)
            if let post {
                try await scheduleResponses(to: post)
            }

        case let .postExcluded(id):
            try await store.updatePendingResponses(adding: [], droppingFor: [id])

        case .eventEnded, .eventStarted, .everythingDeleted, .founded:
            break

        case .interestExcluded, .lastRanChanged, .moveRecorded:
            break

        case .nextOrdinarySceneDueChanged, .pendingResponsesChanged, .sceneStored:
            break
        }
    }

    func scheduleResponses(to post: Post) async throws(TownStoreError) {
        guard let schedule = try await store.schedule(),
              !schedule.pendingResponses.contains(where: { $0.post == post.id }),
              try await !store.hasResponse(to: post.id)
        else { return }
        let responses = drawResponses(to: post)
        var pendingPosts: [Post] = []
        for id in Set(schedule.pendingResponses.map(\.post)) {
            if let pendingPost = try await store.post(id) {
                pendingPosts.append(pendingPost)
            }
        }
        pendingPosts.append(post)
        pendingPosts.sort { first, second in
            if first.happenedAt == second.happenedAt {
                return first.id.rawValue.uuidString < second.id.rawValue.uuidString
            }
            return first.happenedAt < second.happenedAt
        }
        let excess = max(0, pendingPosts.count - tuning.yourPost.maxPostsAwaitingResponses)
        try await store.updatePendingResponses(
            adding: responses,
            droppingFor: pendingPosts.prefix(excess).map(\.id),
        )
        let offset = responses.first?.dueAt.timeIntervalSince(post.happenedAt) ?? 0
        responseRetryAt = nil
        EngineLog.recordResponsesScheduled(responses.count, offset: offset)
    }

    private func drawResponses(to post: Post) -> [Schedule.PendingResponse] {
        let scale = tuning.yourPost.responseDelayScale[settings.speed]
        let delay = tuning.yourPost.firstResponseDelay
        let bounds = (delay.lowerBound / .seconds(1)) ... (delay.upperBound / .seconds(1))
        let first = generator.nextFraction(in: bounds) * scale
        let weights = tuning.yourPost.responseSceneWeights
        let draw = generator.nextIndex(below: weights.reduce(0, +))
        var cumulative = 0
        var count = tuning.yourPost.responseSceneCount.lowerBound
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if draw < cumulative {
                count += index; break
            }
        }
        var offsets = [first]
        while offsets.count < count {
            offsets.append(generator.nextFraction(in: first ... max(
                first,
                tuning.yourPost.responseSpan / .seconds(1) * scale,
            )))
        }
        return offsets.sorted().map { offset in
            Schedule.PendingResponse(
                post: post.id,
                dueAt: ScenePace.wholeMilliseconds(post.happenedAt.addingTimeInterval(offset)),
            )
        }
    }

    /// Recovers the commit-to-schedule crash window, and removes excluded pending seeds.
    func prepareResponses() async throws(TownStoreError) {
        let responses = try await store.schedule()?.pendingResponses ?? []
        var excluded: [Post.ID] = []
        for id in Set(responses.map(\.post)) where try await store.responsePost(id) == nil {
            excluded.append(id)
        }
        if !excluded.isEmpty {
            try await store.updatePendingResponses(
                adding: [],
                droppingFor: excluded,
            )
        }
        if let latest = try await store.latestYourPost() {
            try await scheduleResponses(to: latest)
        }
    }

    func waitForNextTurn(fallback: Date) async throws {
        var due = fallback
        do throws(TownStoreError) {
            if let schedule = try await store.schedule() {
                due = schedule.nextOrdinarySceneDue
                if let response = schedule.pendingResponses.first {
                    due = min(due, max(response.dueAt, responseRetryAt ?? response.dueAt))
                }
                if let last = try await store.lastScenePostTime() {
                    due = max(due, last)
                }
            }
        } catch { EngineLog.record(.failed(error)) }
        try await wait(seconds: due.timeIntervalSince(currentTime()))
    }

    func responseCast(
        _ ordinary: SceneCasting.Cast,
        response: Schedule.PendingResponse?,
        casting: SceneCasting,
        at now: Date,
    ) async throws(TownStoreError) -> SceneCasting.Cast {
        let post: Post
        let quoted: Bool
        var lead: Resident.ID?
        if let response {
            guard let seed = try await store.responsePost(response.post) else {
                return ordinary
            }
            post = seed
            quoted = true
            lead = try await responseLead(to: post)
        } else {
            let candidates = try await store.yourPostSeeds(before: now)
            guard !candidates.isEmpty,
                  generator.nextUnit() < tuning.yourPost.postSeedChance else { return ordinary }
            post = candidates[generator.nextIndex(below: candidates.count)]
            quoted = false
        }
        var speakers = ordinary.speakers
        var retries = Array(ordinary.seeds.prefix(tuning.generation.refusalRetriesPerTurn))
        if let lead, !speakers.contains(lead) {
            speakers[0] = lead
            if retries.contains(where: { !Self.seed($0, fits: speakers) }) {
                retries = responseRetries(keeping: retries, speakers: speakers, casting: casting)
            }
        }
        return SceneCasting.Cast(
            speakers: speakers,
            seeds: [.yourPost(post, quoted: quoted, leadSpeaker: lead)] + retries,
        )
    }

    /// Keeps compatible retries and refills with the ordinary pools after lead casting.
    /// Pool kinds are uniform, then their candidates are uniform, as in SceneCasting.
    private func responseRetries(
        keeping original: [SceneSeed],
        speakers: [Resident.ID],
        casting: SceneCasting,
    ) -> [SceneSeed] {
        let limit = min(
            tuning.generation.refusalRetriesPerTurn,
            SceneRequest.seedCount.upperBound - 1,
        )
        var retries = Array(original.filter { Self.seed($0, fits: speakers) }.prefix(limit))
        let profiles = speakers.flatMap { resident in
            SceneSeed.ProfileAspect.allCases.map { SceneSeed.profile(resident, $0) }
        }
        var pools = [
            profiles,
            casting.topics.map(SceneSeed.topic),
            casting.events.map(SceneSeed.event),
        ]
        .map { candidates in candidates.filter { !retries.contains($0) } }
        while retries.count < limit {
            let kinds = pools.indices.filter { !pools[$0].isEmpty }
            guard !kinds.isEmpty else { break }
            let kind = kinds[generator.nextIndex(below: kinds.count)]
            retries.append(pools[kind].remove(at: generator.nextIndex(below: pools[kind].count)))
        }
        return retries
    }

    private func responseLead(to post: Post) async throws(TownStoreError) -> Resident.ID? {
        guard try await !store.hasResponse(to: post.id),
              let target = post.replyTarget,
              let replied = try await store.post(target),
              case let .resident(resident) = replied.author,
              try await isLiving(resident) else { return nil }
        return generator.nextUnit() < tuning.yourPost
            .repliedResidentSpeaksFirstChance ? resident : nil
    }

    private func isLiving(_ resident: Resident.ID) async throws(TownStoreError) -> Bool {
        try await store.residents().contains { $0.id == resident && $0.status == .living }
    }
}
