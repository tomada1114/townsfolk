import Foundation
import Synchronization

/// A clock a test moves by hand, with the wall-clock date that moves with it, so the
/// timeline's waits run without real time passing (`designing-core-logic` › Inject time).
///
/// It also counts the sleeps that actually suspended: the timeline goes back to sleep
/// only once it has finished reacting to a wake, so a test that waits for the next sleep
/// with ``waitForSleep(_:)`` sees every state change that wake caused, with no polling.
final class ManualClock: Clock {
    /// A point on the clock: how far it has been advanced since it was made.
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

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        var sleepers: [Sleeper] = []
        var cancelled: Set<Int> = []
        var sleepsStarted = 0
        var waiters: [Waiter] = []

        /// Takes out the waiters whose count has been reached.
        mutating func readyWaiters() -> [Waiter] {
            let ready = waiters.filter { $0.count <= sleepsStarted }
            waiters.removeAll { $0.count <= sleepsStarted }
            return ready
        }
    }

    private static let attosecondsPerSecond = 1e18

    /// The date the clock reads before it is first advanced.
    let start: Date
    private let state = Mutex(State())

    var now: Instant {
        state.withLock(\.now)
    }

    var minimumResolution: Duration {
        .zero
    }

    /// The wall-clock date the clock reads now: ``start`` plus every advance.
    var date: Date {
        let components = now.offset.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / Self
            .attosecondsPerSecond
        return start.addingTimeInterval(seconds)
    }

    /// How many sleeps have suspended so far.
    var sleepsStarted: Int {
        state.withLock(\.sleepsStarted)
    }

    init(start: Date) {
        self.start = start
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(id: id, deadline: deadline, continuation: continuation)
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                state.cancelled.insert(id)
                let found = state.sleepers.first { $0.id == id }
                state.sleepers.removeAll { $0.id == id }
                return found
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    private func register(
        id: Int,
        deadline: Instant,
        continuation: CheckedContinuation<Void, any Error>,
    ) {
        enum Outcome {
            case cancelled
            case due
            case suspended([Waiter])
        }
        let outcome = state.withLock { state -> Outcome in
            if state.cancelled.contains(id) {
                return .cancelled
            }
            if deadline <= state.now {
                return .due
            }
            state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
            state.sleepsStarted += 1
            return .suspended(state.readyWaiters())
        }
        switch outcome {
        case .cancelled:
            continuation.resume(throwing: CancellationError())

        case .due:
            continuation.resume()

        case let .suspended(waiters):
            for waiter in waiters {
                waiter.continuation.resume()
            }
        }
    }

    /// Moves the clock on by `duration`, waking every sleep whose deadline it reaches.
    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let reached = state.now
            let due = state.sleepers.filter { $0.deadline <= reached }
            state.sleepers.removeAll { $0.deadline <= reached }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    /// Returns once `count` sleeps in all have suspended.
    func waitForSleep(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let isReady = state.withLock { state in
                if state.sleepsStarted >= count {
                    return true
                }
                state.waiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if isReady {
                continuation.resume()
            }
        }
    }

    /// Moves the clock on by `duration` and returns once the sleeper it woke has gone
    /// back to sleep — the timeline has finished reacting to the wake. `duration` must
    /// reach the timeline's next deadline, or nothing wakes and this never returns.
    func advanceAndWait(by duration: Duration) async {
        let next = sleepsStarted + 1
        advance(by: duration)
        await waitForSleep(next)
    }
}
