import os
import TownsfolkCore

/// The one fake of ``TownsfolkCore/FrontmostAppProviding``, shared by every test target.
///
/// A fake, not a mock (`.claude/rules/testing.md` › Fakes, not mocks): a real conforming
/// implementation whose answers are data the test hands it, and whose calls are recorded
/// in a value the test reads afterwards. No expectations are declared up front.
/// `FrontmostAppProvidingContract` holds it to the same promises as the real adapter.
///
/// The call count sits behind a lock rather than an `@unchecked Sendable`, so the fake is
/// `Sendable` the way the port requires whichever actor a test calls it from.
package final class FakeFrontmostAppProvider: FrontmostAppProviding {
    /// How many times ``currentFrontmostApp()`` has been asked so far.
    package var callCount: Int {
        calls.withLock { $0 }
    }

    private let answers: [FrontmostApp?]
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    /// Answers each call in order, repeating the last one once they run out; no answers
    /// at all means every call answers `nil`.
    package init(answering answers: [FrontmostApp?]) {
        self.answers = answers.isEmpty ? [nil] : answers
    }

    package func currentFrontmostApp() -> FrontmostApp? {
        let index = calls.withLock { count in
            defer { count += 1 }
            return min(count, answers.count - 1)
        }
        return answers[index]
    }
}
