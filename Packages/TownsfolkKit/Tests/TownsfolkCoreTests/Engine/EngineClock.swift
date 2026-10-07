import os

/// A clock that moves only when a test advances it (`designing-core-logic` › Inject
/// time), so a wait of six fake minutes takes no real time and no `sleep`. A test waits
/// for the engine to start sleeping with ``waitForSleepers(count:)``, then advances.
final class EngineClock: Clock, Sendable {
    /// A point on the fake timeline: how far it lies from where the clock started.
    struct Instant: InstantProtocol {
        let offset: Duration

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }

        func advanced(by duration: Duration) -> Self {
            Self(offset: offset + duration)
        }

        func duration(to other: Self) -> Duration {
            other.offset - offset
        }
    }

    /// How one sleep began.
    private enum Start {
        /// Its task was cancelled before it could wait.
        case cancelled
        /// Its deadline had already passed.
        case due
        /// It waits; these waiters for a count of sleepers are now satisfied.
        case sleeping([CheckedContinuation<Void, Never>])
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        var sleepers: [Int: Sleeper] = [:]
        var cancelled: Set<Int> = []
        var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        /// Takes the waiters whose count of sleepers is now reached.
        mutating func takeSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {
            let satisfied = waiters.filter { $0.count <= sleepers.count }
            waiters.removeAll { $0.count <= sleepers.count }
            return satisfied.map(\.continuation)
        }
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration {
        .zero
    }

    /// How far the clock has been advanced since it started.
    var elapsed: Duration {
        now.offset
    }

    /// How many sleeps are waiting right now.
    var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    /// The earliest deadline any sleep waits for, or `nil` when nothing sleeps.
    var nextDeadline: Duration? {
        state.withLock { state in
            state.sleepers.values.map(\.deadline.offset).min()
        }
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        try Task.checkCancellation()
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let start = state.withLock { state -> Start in
                    if state.cancelled.remove(id) != nil {
                        return .cancelled
                    }
                    guard deadline > state.now else {
                        return .due
                    }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return .sleeping(state.takeSatisfiedWaiters())
                }
                switch start {
                case .cancelled:
                    continuation.resume(throwing: CancellationError())

                case .due:
                    continuation.resume()

                case let .sleeping(waiters):
                    for waiter in waiters {
                        waiter.resume()
                    }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                guard let sleeper = state.sleepers.removeValue(forKey: id) else {
                    state.cancelled.insert(id)
                    return Sleeper?.none
                }
                return sleeper
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock on by `duration`, waking every sleep whose deadline it reaches.
    func advance(by duration: Duration) {
        let woken = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in due.keys {
                state.sleepers.removeValue(forKey: id)
            }
            return due.values.map(\.continuation)
        }
        for continuation in woken {
            continuation.resume()
        }
    }

    /// Moves the clock to the earliest deadline anything sleeps until; returns how far it
    /// moved, or `nil` when nothing sleeps.
    @discardableResult
    func advanceToNextDeadline() -> Duration? {
        guard let deadline = nextDeadline else {
            return nil
        }
        let step = deadline - elapsed
        advance(by: step)
        return step
    }

    /// Returns once at least `count` sleeps are waiting, without polling.
    func waitForSleepers(count: Int) async {
        await withCheckedContinuation { continuation in
            let isReached = state.withLock { state in
                guard state.sleepers.count < count else {
                    return true
                }
                state.waiters.append((count, continuation))
                return false
            }
            if isReached {
                continuation.resume()
            }
        }
    }
}
