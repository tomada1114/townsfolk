import Foundation
import Observation

/// S3, the town being founded (ux-flows S3; requirements §3.1): "Finding you a town…" and
/// three lines, each checked as #20's ``Founder`` reports that step finished — the town,
/// the residents, the first scene — and nothing else about progress.
///
/// After 60 s of founding, "This is taking longer than usual." joins the steps; there is
/// no cancel, since quitting is always possible and keeps nothing. A failure after the
/// founder's last attempt shows "Couldn't find you a town this time." with Try Again,
/// which founds afresh. Success reports the new town in ``town`` — the owner then opens
/// S1 (#27) — and asks the view to announce "You moved to {town}." politely. An
/// unavailable model is ``Phase/unavailable(_:)``, apart from a failure, so the owner
/// shows S7 instead.
///
/// ``run()`` is the one action that waits: the view runs it from `.task(id: attempt)`, so
/// SwiftUI cancels it with the view and starts it again after Try Again. One run at a
/// time, as the founder requires. Construction reads and writes nothing. Your name and the
/// town's are never logged.
@MainActor
@Observable
public final class FoundingViewModel {
    /// Where founding stands.
    public enum Phase: Sendable, Equatable {
        /// The founder gave up after its last attempt; Try Again founds afresh.
        case failed
        /// The town is stored; the owner opens S1.
        case founded
        /// Founding runs, or is about to — the steps show.
        case founding
        /// The model is unavailable for this reason; the owner shows S7, and Try Again
        /// founds afresh once the model is back.
        case unavailable(ModelAvailability)
    }

    /// How long founding runs before the slow line shows (ux-guidelines › States).
    public static let defaultSlowAfter = Duration.seconds(secondsBeforeSlow)
    private static let secondsBeforeSlow = 60
    /// The steps in the order S3 lists them, which is the order the founder takes them.
    private static let stepOrder: [FoundingProgress] = [.town, .residents, .firstScene]

    /// The name the town is founded for.
    public let displayName: DisplayName
    /// Where founding stands.
    public private(set) var phase: Phase
    /// Whether founding has run for the slow wait or longer in this attempt.
    public private(set) var isSlow: Bool
    /// The new town once founded, read back from the store; `nil` before, and if that
    /// read failed.
    public private(set) var town: Town?
    /// The polite announcement for VoiceOver once the town is founded, or `nil` before.
    public private(set) var announcement: LocalizedStringResource?
    /// Counts up on each Try Again, so the view's `.task(id:)` starts a fresh run.
    public private(set) var attempt = 0
    /// The steps the founder reported finished in this attempt.
    private var finished: Set<FoundingProgress>

    /// `nil` for a preview, which never founds.
    @ObservationIgnored private let founder: Founder?
    @ObservationIgnored private let store: TownStore?
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let slowAfter: Duration
    @ObservationIgnored private var isRunning = false

    // MARK: Wording

    /// "Finding you a town…", S3's heading while the steps show.
    public var heading: LocalizedStringResource {
        FirstRunWording.foundingHeading
    }

    /// The three lines, in order, each checked once its step finished.
    public var steps: [FoundingStepLine] {
        Self.stepOrder.map { step in
            FoundingStepLine(
                step: step,
                title: FirstRunWording.step(step),
                isDone: finished.contains(step),
            )
        }
    }

    /// The line under the steps once founding is slow; `nil` before, and once it ended.
    public var slowNotice: LocalizedStringResource? {
        phase == .founding && isSlow ? FirstRunWording.slow : nil
    }

    /// What S3 shows in place of the steps after founding failed; `nil` otherwise.
    public var failureMessage: LocalizedStringResource? {
        phase == .failed ? FirstRunWording.failed : nil
    }

    /// The button shown with ``failureMessage``.
    public var tryAgainTitle: LocalizedStringResource {
        FirstRunWording.tryAgain
    }

    /// Creates S3 founding a town for `displayName`.
    ///
    /// - Parameters:
    ///   - displayName: Your name, already stored in the settings.
    ///   - founder: #20's founder; nothing else may use it, or its scene writer, while
    ///     founding runs.
    ///   - store: The store `founder` writes to, read once for the new town's name.
    ///   - clock: What the slow wait sleeps on.
    ///   - slowAfter: How long founding runs before the slow line shows
    ///     (ux-guidelines › States: 60 s). Not a † starting value, so not in ``Tuning``.
    public init(
        displayName: DisplayName,
        founder: Founder,
        store: TownStore,
        clock: any Clock<Duration> = ContinuousClock(),
        slowAfter: Duration = defaultSlowAfter,
    ) {
        self.displayName = displayName
        self.founder = founder
        self.store = store
        self.clock = clock
        self.slowAfter = slowAfter
        phase = .founding
        isSlow = false
        finished = []
    }

    /// Creates S3 already in a state, with no founder behind it — for a preview, and for a
    /// test of what the screen shows. ``run()`` does nothing.
    package init(
        previewing displayName: DisplayName,
        finished: Set<FoundingProgress>,
        isSlow: Bool,
        phase: Phase,
    ) {
        self.displayName = displayName
        founder = nil
        store = nil
        clock = ContinuousClock()
        slowAfter = .zero
        self.phase = phase
        self.isSlow = isSlow
        self.finished = finished
    }

    // MARK: Actions

    /// Founds the town, checking each line as its step finishes and turning slow after
    /// the slow wait, until the founder returns. Does nothing unless the steps show and
    /// no other run is going.
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled — the view went
    ///   away, or the app is quitting — with nothing stored and the screen left as it was.
    public func run() async throws {
        guard let founder, phase == .founding, !isRunning else {
            return
        }
        isRunning = true
        defer { isRunning = false }
        let watch = Task { await self.watchForSlow() }
        defer { watch.cancel() }
        let outcome = try await founder.found(displayName: displayName) { step in
            await self.stepFinished(step)
        }
        await ended(outcome)
    }

    /// Try Again, after a failure or once the model is back: clears the steps and the slow
    /// line and asks the view for a fresh run. Does nothing while founding runs or once it
    /// succeeded.
    public func tryAgainPressed() {
        switch phase {
        case .failed, .unavailable:
            break

        case .founding, .founded:
            return
        }
        finished = []
        isSlow = false
        phase = .founding
        attempt += 1
    }

    // MARK: Founding

    private func stepFinished(_ step: FoundingProgress) {
        guard phase == .founding else {
            return
        }
        finished.insert(step)
    }

    /// Sleeps for the slow wait, then marks founding slow — unless founding ended first,
    /// which cancels the sleep.
    private func watchForSlow() async {
        // A cancelled sleep is founding ending first, not a failure.
        guard await (try? clock.sleep(for: slowAfter)) != nil,
              !Task.isCancelled,
              isRunning,
              phase == .founding
        else {
            return
        }
        isSlow = true
    }

    private func ended(_ outcome: FoundingOutcome) async {
        switch outcome {
        case .founded:
            let founded = await foundedTown()
            town = founded
            phase = .founded
            if let founded {
                announcement = FirstRunWording.movedTo(town: founded.name)
            }

        case .failed:
            phase = .failed

        case let .unavailable(reason):
            phase = .unavailable(reason)
        }
    }

    /// The town just founded, or `nil` when the store cannot read it back; it is stored
    /// all the same, so the owner still opens S1.
    private func foundedTown() async -> Town? {
        guard let store else {
            return nil
        }
        do {
            return try await store.town()
        } catch {
            AppLog.founding.error(
                "the founded town could not be read: \(String(describing: error), privacy: .public)",
            )
            return nil
        }
    }
}
