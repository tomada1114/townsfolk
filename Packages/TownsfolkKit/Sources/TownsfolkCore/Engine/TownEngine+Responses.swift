import Foundation

/// Your posts schedule delayed scenes through the same writer as ordinary scenes.
extension TownEngine {
    /// A profile owner and its living relationship partner must survive lead casting.
    private static func seed(
        _ seed: SceneSeed,
        fits speakers: [Resident.ID],
        in residents: [Resident],
    ) -> Bool {
        switch seed {
        case let .profile(resident, aspect):
            guard speakers.contains(resident) else {
                return false
            }
            switch aspect {
            case .hobby, .occupation, .personality, .worry:
                return true

            case let .relationship(partner):
                return residents.contains { other in
                    other.id == partner && (other.status == .movedOut || speakers.contains(partner))
                }
            }

        case .event, .name, .topic:
            return true

        case .yourPost:
            return false
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
        case .yourPostStored:
            try await prepareResponses()

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
        let responses = drawResponses(to: post, speed: settings.speed)
        if try await store.repairResponses(
            to: post.id,
            adding: responses,
            maximum: tuning.yourPost.maxPostsAwaitingResponses,
        ) {
            responseRetryAt = nil
            logScheduledResponses(responses, to: post)
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
        let candidates = try await store
            .unscheduledYourPosts(maximum: tuning.yourPost.maxPostsAwaitingResponses)
        for post in candidates {
            try await scheduleResponses(to: post)
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
            if retries.contains(where: { !Self.seed($0, fits: speakers, in: casting.residents) }) {
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
        var retries = Array(original.filter { Self.seed($0, fits: speakers, in: casting.residents) }
            .prefix(limit))
        let profiles = casting.profileSeeds(
            of: speakers,
            partners: speakers,
            aspects: SceneSeed.ProfileAspect.allCases,
        )
        var pools = [
            profiles,
            casting.topics.map(SceneSeed.topic),
            casting.events.map(SceneSeed.event),
            casting.names.map(SceneSeed.name),
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
