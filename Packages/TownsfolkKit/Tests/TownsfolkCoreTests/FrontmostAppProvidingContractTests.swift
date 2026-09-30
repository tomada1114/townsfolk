import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// The fake half of the `FrontmostAppProviding` contract suite: the same
/// ``FrontmostAppProvidingContract`` that `TownsfolkPlatformTests` runs against the real
/// adapter under `just test-local` runs here against ``FakeFrontmostAppProvider``, on
/// every `just test` and in CI, so the fake cannot drift from the port's promises.
@Suite("FrontmostAppProviding contract, against the fake")
struct FrontmostAppProvidingContractTests {
    @Test(arguments: [
        [FrontmostApp(name: "Finder", bundleIdentifier: "com.apple.finder")],
        [FrontmostApp(name: "Some Helper")],
        [nil],
        [],
        [FrontmostApp(name: "Finder"), nil],
        [nil, FrontmostApp(name: "Terminal", bundleIdentifier: "com.apple.Terminal")],
    ])
    func `the fake keeps the contract`(answers: [FrontmostApp?]) {
        FrontmostAppProvidingContract.check(FakeFrontmostAppProvider(answering: answers))
    }

    @Test
    func `the contract asks more than once`() {
        let provider = FakeFrontmostAppProvider(answering: [FrontmostApp(name: "Finder")])
        FrontmostAppProvidingContract.check(provider)
        #expect(provider.callCount == 2)
    }

    // The contract's own oracle: a provider that breaks a promise must be reported, or
    // `check(_:)` would pass anything, the real adapter included.

    @Test
    func `an empty name is reported as a broken promise`() {
        let violations = FrontmostAppProvidingContract.violations(
            of: FakeFrontmostAppProvider(answering: [FrontmostApp(name: "")]),
        )
        #expect(violations.count == 2)
    }

    @Test
    func `an empty name on a later answer is reported too`() {
        let violations = FrontmostAppProvidingContract.violations(
            of: FakeFrontmostAppProvider(answering: [
                FrontmostApp(name: "Finder"),
                FrontmostApp(name: ""),
            ]),
        )
        #expect(violations.count == 1)
        #expect(violations.first?.hasPrefix("answer 2 of 2") == true)
    }
}
