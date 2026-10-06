import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// The fake's own behavior beyond the contract: the scripted values in order, pushes
/// reaching every live observer, and an ended observer being let go — what the engine's
/// tests (#29) will lean on.
@MainActor
@Suite("FakeWindowPresenceProvider")
struct FakeWindowPresenceProviderTests {
    @Test
    func `an observer receives the script in order, then each push`() async {
        let provider = FakeWindowPresenceProvider(scripted: [
            PresenceFixtures.seen,
            PresenceFixtures.covered,
        ])
        var values = provider.presenceUpdates().makeAsyncIterator()

        #expect(await values.next() == PresenceFixtures.seen)
        #expect(await values.next() == PresenceFixtures.covered)
        provider.push(PresenceFixtures.asleep)
        #expect(await values.next() == PresenceFixtures.asleep)
    }

    @Test
    func `a push reaches every live observer`() async {
        let provider = FakeWindowPresenceProvider(scripted: [PresenceFixtures.seen])
        var first = provider.presenceUpdates().makeAsyncIterator()
        var second = provider.presenceUpdates().makeAsyncIterator()
        #expect(await first.next() == PresenceFixtures.seen)
        #expect(await second.next() == PresenceFixtures.seen)

        provider.push(PresenceFixtures.covered)

        #expect(await first.next() == PresenceFixtures.covered)
        #expect(await second.next() == PresenceFixtures.covered)
        #expect(provider.observationCount == 2)
        #expect(provider.liveObserverCount == 2)
    }

    @Test
    func `a dropped stream is let go, and a push after it reaches no one`() {
        let provider = FakeWindowPresenceProvider(scripted: [PresenceFixtures.seen])
        observeAndDrop(provider)

        #expect(provider.observationCount == 1)
        #expect(provider.liveObserverCount == 0)
        provider.push(PresenceFixtures.covered)
        #expect(provider.liveObserverCount == 0)
    }

    @Test
    func `with nothing scripted the first value is the first push`() async {
        let provider = FakeWindowPresenceProvider(scripted: [])
        var values = provider.presenceUpdates().makeAsyncIterator()
        provider.push(PresenceFixtures.asleep)
        #expect(await values.next() == PresenceFixtures.asleep)
    }

    @Test
    func `presence values compare by all three facts`() {
        #expect(PresenceFixtures.seen == WindowPresence(
            isWindowVisible: true,
            isAppActive: true,
            isMacAwake: true,
        ))
        #expect(PresenceFixtures.seen != PresenceFixtures.covered)
        #expect(PresenceFixtures.covered != PresenceFixtures.asleep)
        #expect(Set([PresenceFixtures.seen, PresenceFixtures.seen, PresenceFixtures.covered])
            .count == 2)
    }

    private func observeAndDrop(_ provider: FakeWindowPresenceProvider) {
        _ = provider.presenceUpdates()
    }
}
