import os
import TownsfolkCore

/// The one fake of ``TownsfolkCore/WindowPresenceProviding``, shared by every test target.
///
/// A fake, not a mock (`.claude/rules/testing.md` › Fakes, not mocks): each observer is
/// handed the scripted values the moment it subscribes, the first of them standing for
/// "the current presence", and ``push(_:)`` stands for a change the OS would report.
/// `WindowPresenceProvidingContract` holds it to the same promises as the AppKit adapter.
///
/// Its live observers sit behind a lock rather than an `@unchecked Sendable`, so the fake
/// is `Sendable` the way the port requires, and a push from any task reaches them all.
package final class FakeWindowPresenceProvider: WindowPresenceProviding {
    private struct State {
        var observers: [Int: AsyncStream<WindowPresence>.Continuation] = [:]
        var observationCount = 0
    }

    /// How many observations have been started so far, ended ones included.
    package var observationCount: Int {
        state.withLock { $0.observationCount }
    }

    /// How many observers are still listening: an observer whose stream is cancelled or
    /// dropped is released, as the port requires.
    package var liveObserverCount: Int {
        state.withLock { $0.observers.count }
    }

    private let script: [WindowPresence]
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Yields `script` to every new observer, in order, before anything is pushed. An empty
    /// script yields nothing first, which breaks the port's contract — useful only to show
    /// the contract noticing.
    package init(scripted script: [WindowPresence]) {
        self.script = script
    }

    @MainActor
    package func presenceUpdates() -> AsyncStream<WindowPresence> {
        let (stream, continuation) = AsyncStream.makeStream(of: WindowPresence.self)
        for presence in script {
            continuation.yield(presence)
        }
        let observer = state.withLock { state in
            defer { state.observationCount += 1 }
            state.observers[state.observationCount] = continuation
            return state.observationCount
        }
        continuation.onTermination = { [state] _ in
            state.withLock { _ = $0.observers.removeValue(forKey: observer) }
        }
        return stream
    }

    /// Delivers `presence` to every observer still listening, as a change would.
    package func push(_ presence: WindowPresence) {
        let observers = state.withLock { Array($0.observers.values) }
        for observer in observers {
            observer.yield(presence)
        }
    }
}
