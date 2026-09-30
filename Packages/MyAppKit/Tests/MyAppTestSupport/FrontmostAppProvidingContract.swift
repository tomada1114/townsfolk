import MyAppCore
import Testing

/// The promises ``MyAppCore/FrontmostAppProviding`` makes, checked against any
/// implementation of it (`.claude/rules/testing.md` › One Contract Suite per Port).
///
/// A fake stands in for the adapter only while both keep the port's promises, so they are
/// written once, here, over the protocol rather than over either implementation.
/// `MyAppCoreTests` runs ``check(_:)`` against ``FakeFrontmostAppProvider`` on every
/// `just test` and in CI; `MyAppPlatformTests` runs it against
/// `WorkspaceFrontmostAppProvider` under `.requiresLocalMachine` (`just test-local`).
/// Every clause is one the port's `///` states; a new clause is stated there first.
package enum FrontmostAppProvidingContract {
    /// How many times ``violations(of:)`` asks: a pull-style port is asked again on every
    /// refresh, so a promise kept only by the first answer is not kept.
    static let askCount = 2

    /// A description of every broken promise, empty when `provider` keeps them all.
    ///
    /// Separate from ``check(_:)`` so a test can hand it a provider that breaks a promise
    /// and see the contract notice — the proof it is not vacuous.
    package static func violations(of provider: some FrontmostAppProviding) -> [String] {
        (1 ... askCount).compactMap { ask in
            guard let answer = provider.currentFrontmostApp(), answer.name.isEmpty else {
                return nil
            }
            return "answer \(ask) of \(askCount) is \(answer), whose name is empty"
        }
    }

    /// Records an issue for every promise `provider` breaks.
    package static func check(_ provider: some FrontmostAppProviding) {
        let broken = violations(of: provider)
        #expect(
            broken.isEmpty,
            "\(type(of: provider)) breaks the FrontmostAppProviding contract: \(broken)",
        )
    }
}
