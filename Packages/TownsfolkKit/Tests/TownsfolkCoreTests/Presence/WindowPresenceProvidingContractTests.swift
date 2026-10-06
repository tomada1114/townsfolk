import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Breaks the first promise: every stream it hands out has already finished, empty.
private struct SilentProvider: WindowPresenceProviding {
    @MainActor
    func presenceUpdates() -> AsyncStream<WindowPresence> {
        AsyncStream { $0.finish() }
    }
}

/// Breaks the second promise: the first observer gets the current value, and every later
/// one gets a stream that has already finished.
private final class FirstObserverOnlyProvider: WindowPresenceProviding {
    private let fake: FakeWindowPresenceProvider

    init(presence: WindowPresence) {
        fake = FakeWindowPresenceProvider(scripted: [presence])
    }

    @MainActor
    func presenceUpdates() -> AsyncStream<WindowPresence> {
        fake.observationCount == 0 ? fake.presenceUpdates() : AsyncStream { $0.finish() }
    }
}

/// The fake half of the `WindowPresenceProviding` contract suite: the same
/// ``WindowPresenceProvidingContract`` that `TownsfolkPlatformTests` runs against the AppKit
/// adapter under `just test-local` runs here against ``FakeWindowPresenceProvider``, on
/// every `just test` and in CI, so the fake cannot drift from the port's promises.
@MainActor
@Suite("WindowPresenceProviding contract, against the fake")
struct WindowPresenceProvidingContractTests {
    @Test(arguments: [
        [PresenceFixtures.seen],
        [PresenceFixtures.hidden],
        [PresenceFixtures.asleep, PresenceFixtures.seen],
        [PresenceFixtures.seen, PresenceFixtures.hidden, PresenceFixtures.seen],
    ])
    func `the fake keeps the contract`(script: [WindowPresence]) async {
        await WindowPresenceProvidingContract.check(FakeWindowPresenceProvider(scripted: script))
    }

    @Test
    func `the contract observes twice and lets both observations go`() async {
        let provider = FakeWindowPresenceProvider(scripted: [PresenceFixtures.seen])
        await WindowPresenceProvidingContract.check(provider)
        #expect(provider.observationCount == 2)
        #expect(provider.liveObserverCount == 0)
    }

    // The contract's own oracle: a provider that breaks a promise must be reported, or
    // `check(_:)` would pass anything, the real adapter included.

    @Test
    func `a provider whose stream ends before any value is reported twice`() async {
        let violations = await WindowPresenceProvidingContract.violations(
            of: SilentProvider(),
            within: .seconds(5),
        )
        #expect(violations.count == 2)
        #expect(violations.first?.hasPrefix("observing yields no current value") == true)
    }

    /// The fake with nothing scripted yields nothing until a push, which never comes — the
    /// outcome does not depend on how short the wait is.
    @Test
    func `a provider that waits for a change before its first value is reported`() async {
        let violations = await WindowPresenceProvidingContract.violations(
            of: FakeWindowPresenceProvider(scripted: []),
            within: .milliseconds(1),
        )
        #expect(violations.count == 2)
    }

    @Test
    func `a provider that serves only its first observer is reported`() async {
        let violations = await WindowPresenceProvidingContract.violations(
            of: FirstObserverOnlyProvider(presence: PresenceFixtures.seen),
            within: .seconds(5),
        )
        #expect(violations == [
            "a second observer, while the first still observes, gets no first value",
        ])
    }
}
