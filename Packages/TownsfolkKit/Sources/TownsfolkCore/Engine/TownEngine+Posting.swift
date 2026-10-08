import Foundation

extension TownEngine {
    /// Stores your post and schedules its responses atomically at the speed captured by
    /// the caller on Return, before its first suspension. It never waits for an ongoing
    /// scene or calls the model: this actor serializes only its draws, and the store
    /// inserts the post, adds responses and prunes the oldest pending groups together.
    ///
    /// - Throws: `TownStoreError` when the transaction cannot commit, including `.cancelled`
    ///   for cancellation before writing, `.notFound` before founding, and a rejected
    ///   origin when `post` is not authored by you. A failure stores nothing.
    public func submitYourPost(_ post: Post, speed: Speed) async throws(TownStoreError) {
        let responses = drawResponses(to: post, speed: speed)
        try await store.storeScheduledYourPost(
            post,
            responses: responses,
            maximum: tuning.yourPost.maxPostsAwaitingResponses,
        )
        responseRetryAt = nil
        logScheduledResponses(responses, to: post)
        nap?.cancel()
    }

    func logScheduledResponses(_ responses: [Schedule.PendingResponse], to post: Post) {
        let offset = responses.first?.dueAt.timeIntervalSince(post.happenedAt) ?? 0
        EngineLog.recordResponsesScheduled(responses.count, offset: offset)
    }

    func drawResponses(to post: Post, speed: Speed) -> [Schedule.PendingResponse] {
        let scale = tuning.yourPost.responseDelayScale[speed]
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
}
