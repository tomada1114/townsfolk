import Testing
import TownsfolkCore

/// The promises ``TownsfolkCore/WindowPresenceProviding`` makes, checked against any
/// implementation of it (`.claude/rules/testing.md` › One Contract Suite per Port).
///
/// `TownsfolkCoreTests` runs ``check(_:)`` against ``FakeWindowPresenceProvider`` on every
/// `just test` and in CI; `TownsfolkPlatformTests` runs it against the AppKit
/// `WindowPresenceProvider` under `.requiresLocalMachine` (`just test-local`). Every clause
/// is one the port's `///` states; a new clause is stated there first.
@MainActor
package enum WindowPresenceProvidingContract {
    /// How long ``check(_:)`` waits for a first value before calling it missing.
    ///
    /// Only a bound on failure, never a condition of passing: a provider that keeps the
    /// promise yields its first value without waiting for anything, so it is there long
    /// before this runs out, and one that yields nothing would yield nothing however long
    /// the wait.
    static let firstValueTimeout = Duration.seconds(firstValueTimeoutSeconds)
    private static let firstValueTimeoutSeconds = 5

    /// A description of every broken promise, empty when `provider` keeps them all.
    ///
    /// Separate from ``check(_:)`` so a test can hand it a provider that breaks a promise
    /// and see the contract notice — the proof it is not vacuous.
    package static func violations(
        of provider: some WindowPresenceProviding,
        within timeout: Duration,
    ) async -> [String] {
        var broken: [String] = []
        let first = provider.presenceUpdates()
        if await firstValue(of: first, within: timeout) == nil {
            broken.append("observing yields no current value within \(timeout), before any change")
        }
        // Observed while `first` is still alive: each observer is promised its own first
        // value, not a share of one stream.
        let second = provider.presenceUpdates()
        if await firstValue(of: second, within: timeout) == nil {
            broken.append("a second observer, while the first still observes, gets no first value")
        }
        withExtendedLifetime(first) {
            // Keeps the first observation open until the second has been checked.
        }
        return broken
    }

    /// Records an issue for every promise `provider` breaks.
    package static func check(_ provider: some WindowPresenceProviding) async {
        let broken = await violations(of: provider, within: firstValueTimeout)
        #expect(
            broken.isEmpty,
            "\(type(of: provider)) breaks the WindowPresenceProviding contract: \(broken)",
        )
    }

    /// The first element of `stream`, or `nil` when it finishes or `timeout` passes first.
    ///
    /// Losing the race cancels the reading task, which ends that observation the way a
    /// consumer that stops listening would.
    package static func firstValue(
        of stream: AsyncStream<WindowPresence>,
        within timeout: Duration,
    ) async -> WindowPresence? {
        await withTaskGroup(of: WindowPresence?.self) { group in
            group.addTask {
                var values = stream.makeAsyncIterator()
                return await values.next()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let winner = await group.next().flatMap(\.self)
            group.cancelAll()
            return winner
        }
    }
}
