import Foundation
import os

/// Founds a town (requirements §3.1): after you pick a name, invents the town, its first
/// residents one by one, and a first scene through the on-device model, then stores them
/// all in one transaction, so the timeline is never empty and quitting midway keeps
/// nothing (`docs/architecture.md` › Core flows › Founding).
///
/// Rules draw what the model is told — each resident's axes from the seed tables, the
/// first scene's speakers and seeds — and check what comes back; the model only writes
/// (`docs/architecture.md` › Principles). The first scene goes through ``SceneWriter``,
/// so it obeys the budget, speaker, and refusal rules every later scene does.
///
/// An actor because it owns the random generator and one run's attempt count. One
/// founding at a time per founder: a second `found` started before the first returns
/// would share that count and overlap two turns on the writer, which ``SceneWriter``
/// forbids — the first-run screens (#24) start one founding and wait for it.
public actor Founder {
    /// Why a run ends before storing anything; thrown inside a run and turned into its
    /// ``FoundingOutcome`` at the top, so `CancellationError` passes through untouched.
    private enum Ending: Error {
        case failed
        case unavailable(ModelAvailability)
    }

    /// A profile seed of one resident, as the first scene's retries keep track of them.
    private struct ProfileSeed: Hashable {
        let resident: Resident.ID
        let aspect: SceneSeed.ProfileAspect
    }

    private let model: any LanguageModelProviding
    private let writer: SceneWriter
    private let draw: ResidentSeedDraw
    private let store: TownStore
    private let now: @Sendable () -> Date
    private let tuning: Tuning
    private var generator: any RandomNumberGenerator & Sendable
    /// Failed attempts so far in this run, every step's together.
    private var failures = 0
    /// Combinations of axes that failed in this run, which a redraw avoids while it can.
    private var triedCombinations: Set<Int> = []
    /// Profile seeds already handed to the writer in this run, which a retry avoids while
    /// it can.
    private var triedSceneSeeds: Set<ProfileSeed> = []

    /// Creates a founder.
    ///
    /// - Parameters:
    ///   - model: The model port, asked for the town and each resident.
    ///   - writer: The scene writer, asked for the first scene; it must not be writing
    ///     another scene while founding runs.
    ///   - seeds: The seed tables the residents' axes are drawn from.
    ///   - store: Where the founded town is stored, once everything succeeded.
    ///   - now: The current time, read for the scene's context and the stored times.
    ///   - generator: What every draw is made with.
    ///   - tuning: The founding limits, the resident count, and the attempts allowed.
    public init(
        model: any LanguageModelProviding,
        writer: SceneWriter,
        seeds: SeedTables,
        store: TownStore,
        now: @escaping @Sendable () -> Date = { Date.now },
        generator: any RandomNumberGenerator & Sendable = SystemRandomNumberGenerator(),
        tuning: Tuning = .default,
    ) {
        self.model = model
        self.writer = writer
        draw = ResidentSeedDraw(axes: seeds.residentAxes)
        self.store = store
        self.now = now
        self.generator = generator
        self.tuning = tuning
    }

    private static func outcome(of ending: Ending) -> FoundingOutcome {
        switch ending {
        case .failed:
            AppLog.founding.error("founding failed; nothing was stored")
            return .failed

        case let .unavailable(reason):
            let name = String(describing: reason)
            AppLog.founding.info(
                "founding ended, the model unavailable: \(name, privacy: .public); nothing was stored",
            )
            return .unavailable(reason)
        }
    }

    /// Founds a town for you, named `you`, reporting each of the three steps to
    /// `progress` as it finishes (REQ-005).
    ///
    /// A failed call, a refusal, an answer breaking a limit, a repeated name, or a skipped
    /// first scene is one failed attempt, retried with new seeds; the town and residents
    /// already invented are kept, and only the failed step is retried. Each call starts a
    /// fresh count. The stored schedule's next ordinary scene is due at the founding
    /// time, for the engine's first step to set (#19).
    ///
    /// - Returns: ``FoundingOutcome/founded`` once everything is stored;
    ///   ``FoundingOutcome/failed`` when the failed attempts reach
    ///   `Tuning.founding.foundingAttempts` or the final write fails; and
    ///   ``FoundingOutcome/unavailable(_:)`` when the model is unavailable at the start or
    ///   a call finds it gone, with no further call. Only a founded town stores anything.
    /// - Throws: `CancellationError` when the calling task is cancelled, with nothing
    ///   stored (requirements.md:148).
    public func found(
        displayName you: DisplayName,
        progress: @Sendable (FoundingProgress) async -> Void,
    ) async throws -> FoundingOutcome {
        try Task.checkCancellation()
        failures = 0
        triedCombinations = []
        triedSceneSeeds = []
        let availability = model.availability
        guard availability == .available else {
            return Self.outcome(of: .unavailable(availability))
        }
        AppLog.founding.info("founding started")
        do {
            try await foundTown(you: you, progress: progress)
        } catch let ending as Ending {
            return Self.outcome(of: ending)
        }
        return .founded
    }

    /// The three steps, then the transaction.
    /// - Throws: ``Ending`` when founding ends without a town, or `CancellationError`.
    private func foundTown(
        you: DisplayName,
        progress: @Sendable (FoundingProgress) async -> Void,
    ) async throws {
        let count = tuning.founding.foundingResidentCount
        var seeds = drawSeeds(count: count)
        guard seeds.count == count else {
            AppLog.founding.error(
                "the seed tables cannot seat \(count, privacy: .public) different residents",
            )
            throw Ending.failed
        }

        let town = try await perform(.town) { isRetry in
            if isRetry {
                triedCombinations.formUnion(seeds.map(\.index))
                seeds = drawSeeds(count: count)
            }
            return try await model.inventTown(from: seeds, foundedAt: now(), tuning: tuning)
        }
        await progress(.town)

        var residents: [Resident] = []
        for slot in seeds.indices {
            let resident = try await perform(.residents) { isRetry in
                if isRetry {
                    redraw(&seeds, at: slot)
                }
                return try await model.inventResident(
                    from: seeds[slot],
                    in: town,
                    after: residents,
                    movedInAt: now(),
                )
            }
            residents.append(resident)
        }
        await progress(.residents)

        let scene = try await perform(.firstScene) { _ in
            try await writeFirstScene(you: you, town: town, residents: residents)
        }
        await progress(.firstScene)

        try Task.checkCancellation()
        try await save(town: town, residents: residents, scene: scene)
    }

    /// Runs `attempt` until it succeeds, counting each failure against the run.
    /// - Throws: ``Ending`` once the failures reach the limit or the model is gone, or
    ///   `CancellationError`.
    private func perform<Value>(
        _ step: FoundingProgress,
        _ attempt: (_ isRetry: Bool) async throws -> FoundingAttempt<Value>,
    ) async throws -> Value {
        let name = String(describing: step)
        var isRetry = false
        while true {
            try Task.checkCancellation()
            switch try await attempt(isRetry) {
            case let .done(value):
                AppLog.founding.info("founding step done: \(name, privacy: .public)")
                return value

            case let .failed(reason):
                failures += 1
                let failed = failures
                let limit = tuning.founding.foundingAttempts
                AppLog.founding.info(
                    """
                    founding attempt failed at \(name, privacy: .public): \
                    \(reason.rawValue, privacy: .public) (\(failed, privacy: .public) of \
                    \(limit, privacy: .public))
                    """,
                )
                guard failed < limit else {
                    throw Ending.failed
                }
                isRetry = true

            case .unavailable:
                let reported = model.availability
                // The call found the model gone; if the port already answers available
                // again, it is on its way back.
                throw Ending.unavailable(reported == .available ? .modelNotReady : reported)
            }
        }
    }

    /// Up to `count` different combinations, preferring ones not yet tried — fewer only
    /// when the tables allow fewer.
    private func drawSeeds(count: Int) -> [ResidentSeed] {
        var seeds: [ResidentSeed] = []
        for _ in 0 ..< count {
            guard let seed = draw.draw(
                avoiding: Set(seeds.map(\.index)),
                preferablyAlso: triedCombinations,
                using: &generator,
            ) else {
                break
            }
            seeds.append(seed)
        }
        return seeds
    }

    /// Replaces the seed at `slot`, which just failed, with a combination none of the
    /// others has.
    private func redraw(_ seeds: inout [ResidentSeed], at slot: Int) {
        triedCombinations.insert(seeds[slot].index)
        let others = seeds.indices.filter { $0 != slot }.map { seeds[$0].index }
        if let seed = draw.draw(
            avoiding: Set(others),
            preferablyAlso: triedCombinations,
            using: &generator,
        ) {
            seeds[slot] = seed
        }
    }

    /// Asks the writer for the first scene: 1–3 of the residents speak, about up to three
    /// seeds drawn from their profiles, preferring seeds no earlier attempt handed over.
    private func writeFirstScene(
        you: DisplayName,
        town: Town,
        residents: [Resident],
    ) async throws -> FoundingAttempt<WrittenScene> {
        let lowest = SceneRequest.speakerCount.lowerBound
        let most = max(lowest, min(SceneRequest.speakerCount.upperBound, residents.count))
        let speakerCount = Int.random(in: lowest ... most, using: &generator)
        let speakers = Array(residents.shuffled(using: &generator).prefix(speakerCount))
        let candidates = speakers.flatMap { speaker in
            SceneSeed.ProfileAspect.allCases.map { ProfileSeed(resident: speaker.id, aspect: $0) }
        }
        let fresh = candidates.filter { !triedSceneSeeds.contains($0) }
        let chosen = (fresh.isEmpty ? candidates : fresh).shuffled(using: &generator)
            .prefix(SceneRequest.seedCount.upperBound)
        triedSceneSeeds.formUnion(chosen)
        let request: SceneRequest
        do {
            request = try SceneRequest(
                you: you,
                town: town,
                residents: residents,
                speakers: speakers.map(\.id),
                seeds: chosen.map { .profile($0.resident, $0.aspect) },
            )
        } catch {
            // Only a roster too small to speak gets here.
            return .failed(.sceneSkipped)
        }
        switch try await writer.write(request, at: now()) {
        case let .written(scene):
            return .done(scene)

        case .skipped(.unavailable):
            return .unavailable

        case .skipped:
            return .failed(.sceneSkipped)
        }
    }

    /// Stores the founded town in one transaction, every time set to now.
    /// - Throws: ``Ending/failed`` when the write fails, which leaves the store as it was.
    private func save(town: Town, residents: [Resident], scene: WrittenScene) async throws {
        do {
            let step = try TownStore.FoundingStep(
                town: town,
                residents: residents,
                firstScene: scene,
                foundedAt: now(),
                tuning: tuning,
            )
            try await store.found(step)
            AppLog.founding.info(
                """
                town founded: \(step.residents.count, privacy: .public) residents, \
                \(step.firstScene.posts.count, privacy: .public) posts
                """,
            )
        } catch {
            // A TownValueError or TownStoreError, which carry only fields and codes.
            AppLog.founding.error(
                "could not store the founded town: \(String(describing: error), privacy: .public)",
            )
            throw Ending.failed
        }
    }
}
