import FoundationModels
import os
import TownsfolkCore

/// The one fake of ``TownsfolkCore/LanguageModelProviding``, shared by every test target.
///
/// A fake, not a mock (`.claude/rules/testing.md` › Fakes, not mocks): it answers from a
/// scripted availability, context size, and queue of outcomes, counts one token per
/// `Character`, and records what it was asked — each call's instructions and prompt, and
/// the most calls it ever had in flight at once, the fact a one-call-at-a-time test reads.
/// `LanguageModelProvidingContract` holds it to the same promises as the adapter.
///
/// Its state sits behind a lock rather than an `@unchecked Sendable`, so the fake is
/// `Sendable` the way the port requires and calls from any task see one queue.
package final class FakeLanguageModelProvider: LanguageModelProviding {
    /// What one ``respond(instructions:prompt:schema:)`` call within the context size
    /// answers.
    package enum Outcome: Equatable, Sendable {
        /// The model wrote this content.
        case content(GeneratedContent)
        /// The call failed with this error.
        case failure(ModelCallError)
    }

    /// One ``respond(instructions:prompt:schema:)`` call, as it was asked.
    package struct Call: Equatable, Sendable {
        package let instructions: String
        package let prompt: String

        package init(instructions: String, prompt: String) {
            self.instructions = instructions
            self.prompt = prompt
        }
    }

    private struct State {
        var availability: ModelAvailability
        var outcomes: [Outcome]
        var calls: [Call] = []
        var inFlight = 0
        var highestInFlight = 0
        var nextHoldID = 0
        var held: [Int: CheckedContinuation<Void, Never>] = [:]
        var cancelledHolds: Set<Int> = []
        var heldWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        /// Takes the waiters whose count is now reached, to be resumed outside the lock.
        mutating func takeSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {
            let satisfied = heldWaiters.filter { $0.count <= held.count }
            heldWaiters.removeAll { $0.count <= held.count }
            return satisfied.map(\.continuation)
        }
    }

    package let contextSize: Int
    private let holdsResponses: Bool
    private let state: OSAllocatedUnfairLock<State>

    /// The answer to the port's availability question; a test may change it mid-run, as
    /// the model finishing its download would.
    package var availability: ModelAvailability {
        get { state.withLock { $0.availability } }
        set { state.withLock { $0.availability = newValue } }
    }

    /// Every ``respond(instructions:prompt:schema:)`` call so far, in the order made,
    /// including one that overflowed or failed; a call from an already-cancelled task is
    /// not made and not recorded.
    package var calls: [Call] {
        state.withLock { $0.calls }
    }

    /// How many ``respond(instructions:prompt:schema:)`` calls are in flight right now.
    package var inFlightCount: Int {
        state.withLock { $0.inFlight }
    }

    /// The most ``respond(instructions:prompt:schema:)`` calls ever in flight at once.
    package var highestInFlight: Int {
        state.withLock { $0.highestInFlight }
    }

    /// Answers `availability` and `contextSize`, and each call within the context size with
    /// the next of `outcomes`. With `holdsResponses`, every call waits once it is recorded
    /// until ``releaseHeld()``, so a test can have several in flight at once.
    package init(
        availability: ModelAvailability,
        contextSize: Int,
        outcomes: [Outcome],
        holdsResponses: Bool,
    ) {
        self.contextSize = contextSize
        self.holdsResponses = holdsResponses
        state = OSAllocatedUnfairLock(initialState: State(
            availability: availability,
            outcomes: outcomes,
        ))
    }

    private static func tokens(instructions: String, prompt: String) -> Int {
        instructions.count + prompt.count
    }

    /// One token per `Character` of `instructions` and of `prompt`. Not `async`: the fake
    /// counts at once, and a synchronous witness still satisfies the port.
    package func tokenCount(instructions: String, prompt: String) throws -> Int {
        try Task.checkCancellation()
        return Self.tokens(instructions: instructions, prompt: prompt)
    }

    /// Records the call, then throws ``ModelCallError/contextSizeExceeded`` when it counts
    /// above ``contextSize`` — leaving the next outcome queued for the retry — and
    /// otherwise answers the next outcome, or ``ModelCallError/other`` once they have run
    /// out.
    package func respond(
        instructions: String,
        prompt: String,
        schema _: GenerationSchema,
    ) async throws -> GeneratedContent {
        try Task.checkCancellation()
        state.withLock { state in
            state.calls.append(Call(instructions: instructions, prompt: prompt))
            state.inFlight += 1
            state.highestInFlight = max(state.highestInFlight, state.inFlight)
        }
        defer { state.withLock { $0.inFlight -= 1 } }
        if holdsResponses {
            await hold()
            try Task.checkCancellation()
        }
        guard Self.tokens(instructions: instructions, prompt: prompt) <= contextSize else {
            throw ModelCallError.contextSizeExceeded
        }
        let outcome = state.withLock { state in
            state.outcomes.isEmpty ? nil : state.outcomes.removeFirst()
        }
        switch outcome {
        case let .content(content):
            return content

        case let .failure(error):
            throw error

        case nil:
            throw ModelCallError.other
        }
    }

    /// Returns once at least `count` calls are held, without polling.
    package func waitUntilHeld(count: Int) async {
        await withCheckedContinuation { continuation in
            let isReached = state.withLock { state in
                guard state.held.count < count else {
                    return true
                }
                state.heldWaiters.append((count, continuation))
                return false
            }
            if isReached {
                continuation.resume()
            }
        }
    }

    /// Lets every call held right now go on to answer; a later call is held again.
    package func releaseHeld() {
        let released = state.withLock { state in
            defer { state.held.removeAll() }
            return Array(state.held.values)
        }
        for continuation in released {
            continuation.resume()
        }
    }

    /// Waits until ``releaseHeld()`` or until the calling task is cancelled.
    private func hold() async {
        let id = state.withLock { state in
            defer { state.nextHoldID += 1 }
            return state.nextHoldID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let toResume = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                    // Cancelled before it could be held: this call goes straight on.
                    guard state.cancelledHolds.remove(id) == nil else {
                        return [continuation]
                    }
                    state.held[id] = continuation
                    return state.takeSatisfiedWaiters()
                }
                for waiting in toResume {
                    waiting.resume()
                }
            }
        } onCancel: {
            let continuation = state.withLock { state in
                guard let held = state.held.removeValue(forKey: id) else {
                    state.cancelledHolds.insert(id)
                    return CheckedContinuation<Void, Never>?.none
                }
                return held
            }
            continuation?.resume()
        }
    }
}
