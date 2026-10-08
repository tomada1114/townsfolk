import Foundation
import FoundationModels
import os

/// Writes one scene end to end (requirements §3.2, §3.11): assembles the prompt from the
/// caller's values and the store within the model's context budget, makes the call
/// through ``LanguageModelProviding``, checks what comes back, retries a refusal with the
/// caller's next seed, and leaves out what keeps being refused.
///
/// It never decides when a scene runs, who speaks, or which seed comes first — the engine
/// (#19) and founding (#20) pass those in (`docs/architecture.md` › Principles) — and it
/// stores no scene: a ``WrittenScene`` is the caller's to time and store. Its only writes
/// are the left-out flags (REQ-011). An actor because it remembers refusal streaks across
/// turns, in memory only.
public actor SceneWriter {
    /// What one fitting of the prompt to the budget came to.
    private enum Fit {
        case fits(ScenePrompt)
        case skip(SceneSkipReason)
    }

    /// What one call came to.
    private enum Reply {
        case content(GeneratedContent)
        case failed(SceneSkipReason)
        case overflow
        case refused
    }

    /// One turn's state: its context, the calls made, and the cap on recent posts once an
    /// overflow has halved them.
    private struct Turn {
        var context: SceneContext
        var calls = 0
        var postCap: Int?
    }

    /// An overflow is retried with the posts divided by this (requirements.md:351).
    private static let overflowDivisor = 2
    /// Bisection splits the range of post counts still in question in two.
    private static let bisectionDivisor = 2

    private let model: any LanguageModelProviding
    private let store: TownStore
    private let tuning: Tuning
    private var postStreaks = RefusalStreaks<Post.ID>()
    private var nameStreaks = RefusalStreaks<Interest.ID>()

    /// Creates a writer calling `model` and reading `store`, under `tuning`'s budget,
    /// retry, and left-out values.
    public init(model: any LanguageModelProviding, store: TownStore, tuning: Tuning = .default) {
        self.model = model
        self.store = store
        self.tuning = tuning
    }

    /// Logs a skipped turn — its reason and how many calls it took, never a text — and
    /// returns it.
    private static func skip(_ reason: SceneSkipReason, calls: Int) -> SceneOutcome {
        AppLog.scenes.info(
            "scene skipped: \(String(describing: reason), privacy: .public) after \(calls, privacy: .public) calls",
        )
        return .skipped(reason)
    }

    /// Writes one scene for `request`, as of `date` in town time: the recent posts are
    /// those of the window before it.
    ///
    /// A skipped turn is an answer, not an error: the model unavailable, a store read
    /// failing, the prompt not fitting, every seed refused, or a scene the rules discard
    /// each return ``SceneOutcome/skipped(_:)`` with its reason, logged.
    ///
    /// One turn at a time per writer: a caller must not start a second `write` on the same
    /// writer before the first returns. The actor keeps the calls data-race free, but each
    /// suspends at every token count, model call, and store write, so two overlapping turns
    /// would interleave the shared refusal streaks — counting one refusal against the other
    /// turn's context, or resetting a streak mid-count. The engine (#19) writes one scene
    /// after another (`docs/architecture.md` › Principles, "One writer at a time"), so the
    /// writer adds no queue of its own.
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled — never mapped to
    ///   a skip (`designing-errors` › Cancellation propagates).
    public func write(_ request: SceneRequest, at date: Date) async throws -> SceneOutcome {
        try Task.checkCancellation()
        guard model.availability == .available else {
            return Self.skip(.unavailable, calls: 0)
        }
        var turn: Turn
        do throws(TownStoreError) {
            let limit = max(1, min(tuning.generation.maxRecentPosts, model.contextSize))
            turn = try await Turn(context: SceneContext.read(
                from: store, at: date, limit: limit, yourPosts: request.yourPostContext,
            ))
        } catch {
            return Self.skip(.storeReadFailed(error), calls: 0)
        }
        let retries = max(0, tuning.generation.refusalRetriesPerTurn)
        for seed in request.seeds.prefix(1 + retries) {
            let extractNames: Bool
            do throws(TownStoreError) {
                extractNames = try await shouldExtractNames(from: seed)
            } catch .cancelled {
                throw CancellationError()
            } catch {
                return Self.skip(.storeReadFailed(error), calls: turn.calls)
            }
            if let outcome = try await attempt(
                seed,
                of: request,
                turn: &turn,
                extractNames: extractNames,
            ) {
                return outcome
            }
        }
        return Self.skip(.refused, calls: turn.calls)
    }

    /// Writes from one seed, retrying once with half the posts after an overflow; `nil`
    /// when the call was refused and the next seed should be tried.
    private func attempt(
        _ seed: SceneSeed,
        of request: SceneRequest,
        turn: inout Turn,
        extractNames: Bool,
    ) async throws -> SceneOutcome? {
        while true {
            try Task.checkCancellation()
            let builder = ScenePromptBuilder(
                request: request,
                seed: seed,
                context: turn.context,
                tuning: tuning,
                extractNames: extractNames,
            )
            let prompt: ScenePrompt
            switch try await fit(builder, cap: turn.postCap) {
            case let .fits(fitted):
                prompt = fitted

            case let .skip(reason):
                return Self.skip(reason, calls: turn.calls)
            }
            turn.calls += 1
            switch try await call(prompt) {
            case let .content(content):
                postStreaks.reset(prompt.yourPosts)
                nameStreaks.reset(prompt.names)
                let validation = SceneValidation(
                    request: request,
                    seed: seed,
                    labels: prompt.labels,
                    tuning: tuning,
                    extractNames: extractNames,
                )
                let outcome = validation.outcome(for: content)
                if case let .skipped(reason) = outcome {
                    return Self.skip(reason, calls: turn.calls)
                }
                return outcome

            case let .failed(reason):
                return Self.skip(reason, calls: turn.calls)

            case .overflow:
                guard turn.postCap == nil, prompt.postsCarried > 0 else {
                    return Self.skip(.overflow, calls: turn.calls)
                }
                turn.postCap = prompt.postsCarried / Self.overflowDivisor

            case .refused:
                await recordRefusal(of: prompt, in: &turn.context)
                return nil
            }
        }
    }

    private func shouldExtractNames(from seed: SceneSeed) async throws(TownStoreError) -> Bool {
        guard case let .yourPost(post, true, _) = seed else {
            return false
        }
        return try await !store.hasResponse(to: post.id)
    }

    /// The prompt with the most of the newest recent posts — at most `cap` — whose
    /// instructions and prompt, counted by the port, fit the context size minus the
    /// output reserve (REQ-005). Counting is monotonic in the posts carried, so the count
    /// is found by bisection rather than one post at a time.
    private func fit(_ builder: ScenePromptBuilder, cap: Int?) async throws -> Fit {
        let budget = model.contextSize - tuning.generation.outputTokenReserve
        let available = min(cap ?? .max, builder.context.recentPosts.count)
        do {
            let full = builder.prompt(keeping: available)
            if try await tokens(in: full) <= budget {
                return .fits(full)
            }
            guard try await tokens(in: builder.prompt(keeping: 0)) <= budget else {
                return .skip(.overflow)
            }
            var fitting = 0
            var overflowing = available
            while overflowing - fitting > 1 {
                let middle = (fitting + overflowing) / Self.bisectionDivisor
                if try await tokens(in: builder.prompt(keeping: middle)) <= budget {
                    fitting = middle
                } else {
                    overflowing = middle
                }
            }
            return .fits(builder.prompt(keeping: fitting))
        } catch let error as ModelCallError {
            return .skip(error == .unavailable ? .unavailable : .modelFailed)
        } catch let error as CancellationError {
            throw error
        } catch {
            // Beyond the port's promise; mapped rather than thrown, so `write` throws only
            // cancellation.
            return .skip(.modelFailed)
        }
    }

    private func tokens(in prompt: ScenePrompt) async throws -> Int {
        try await model.tokenCount(instructions: prompt.instructions, prompt: prompt.prompt)
    }

    private func call(_ prompt: ScenePrompt) async throws -> Reply {
        do {
            return try await .content(model.respond(
                instructions: prompt.instructions,
                prompt: prompt.prompt,
                schema: SceneDraft.generationSchema,
            ))
        } catch let error as ModelCallError {
            return switch error {
            case .contextSizeExceeded:
                .overflow

            case .other:
                .failed(.modelFailed)

            case .refused:
                .refused

            case .unavailable:
                .failed(.unavailable)
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            // Beyond the port's promise; mapped rather than thrown, so `write` throws only
            // cancellation.
            return .failed(.modelFailed)
        }
    }

    /// Adds one to the streak of your posts and names in a refused prompt, and leaves out
    /// each whose streak reached `Tuning.generation.refusalsBeforeLeftOut`, each in its
    /// own transaction (REQ-011). A flag that fails to store is logged and tried again at
    /// the next refusal.
    private func recordRefusal(of prompt: ScenePrompt, in context: inout SceneContext) async {
        let threshold = tuning.generation.refusalsBeforeLeftOut
        for post in postStreaks.refused(prompt.yourPosts, threshold: threshold) {
            do {
                try await store.excludePost(post)
                postStreaks.reset([post])
                context.leaveOut(post: post)
                AppLog.scenes
                    .info(
                        "left out a post of yours after \(threshold, privacy: .public) refusals in a row",
                    )
            } catch {
                AppLog.scenes
                    .error(
                        "could not leave out a post: \(String(describing: error), privacy: .public)",
                    )
            }
        }
        for name in nameStreaks.refused(prompt.names, threshold: threshold) {
            do {
                try await store.excludeInterest(name)
                nameStreaks.reset([name])
                context.leaveOut(name: name)
                AppLog.scenes
                    .info("left out a name after \(threshold, privacy: .public) refusals in a row")
            } catch {
                AppLog.scenes
                    .error(
                        "could not leave out a name: \(String(describing: error), privacy: .public)",
                    )
            }
        }
    }
}
