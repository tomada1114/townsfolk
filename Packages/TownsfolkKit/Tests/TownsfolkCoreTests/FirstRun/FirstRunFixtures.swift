import Foundation
import Observation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// The names a first-run model asked its founding factory for, in order; each screen
/// it makes never founds.
@MainActor
final class FoundingRequests {
    private(set) var names: [String] = []

    func make(_ name: DisplayName) -> FoundingViewModel {
        names.append(name.value)
        return FirstRunFixtures.idleFounding(name)
    }
}

/// Values the first-run suites share: founding screens over #20's founder and the fake
/// model, and a way to wait for a view model's state without polling.
enum FirstRunFixtures {
    /// A name of exactly `count` characters, so a boundary test states its length rather
    /// than a literal someone has to count.
    static func name(ofLength count: Int) -> String {
        String(repeating: "a", count: count)
    }

    /// A fake answering `answers` in order, each call waiting for
    /// ``FakeLanguageModelProvider/releaseHeld()`` so a test can look between the steps.
    static func heldFake(_ answers: [FoundingFixtures.Answer]) -> FakeLanguageModelProvider {
        ModelFixtures.heldFake(outcomes: FoundingFixtures.outcomes(answers))
    }

    /// A founding screen founding as `name` with #20's founder over `fake` and `store`,
    /// waiting on a clock that never moves.
    @MainActor
    static func founding(
        _ fake: FakeLanguageModelProvider,
        store: TownStore,
        name: DisplayName,
    ) throws -> FoundingViewModel {
        try founding(fake, store: store, name: name, clock: EngineClock())
    }

    /// A founding screen founding as `name` with #20's founder over `fake` and `store`,
    /// waiting on `clock`.
    @MainActor
    static func founding(
        _ fake: FakeLanguageModelProvider,
        store: TownStore,
        name: DisplayName,
        clock: any Clock<Duration>,
    ) throws -> FoundingViewModel {
        try FoundingViewModel(
            displayName: name,
            founder: founder(fake, store: store),
            store: store,
            clock: clock,
        )
    }

    /// A founding screen in its first state that never founds — for the tests that only
    /// need one to exist.
    @MainActor
    static func idleFounding(_ name: DisplayName) -> FoundingViewModel {
        FoundingViewModel(previewing: name, finished: [], isSlow: false, phase: .founding)
    }

    /// S3's three lines in order, as (words, done?) pairs — the shape the expectations
    /// compare.
    @MainActor
    static func lines(of model: FoundingViewModel) -> [(String, Bool)] {
        model.steps.map { ($0.title.resolved(in: .english), $0.isDone) }
    }

    /// `Tomo`, the name most tests found as.
    static func tomo() throws -> DisplayName {
        try DisplayName("Tomo")
    }
}

/// Returns once `condition` holds, waking on each change to what it reads rather than
/// polling — for state a task on the main actor sets after the test's own step.
@MainActor
func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            _ = withObservationTracking {
                condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}
