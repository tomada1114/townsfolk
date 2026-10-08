import Foundation

/// The town engine: the one writer of the town (`docs/architecture.md` › Principles). It
/// decides when an ordinary scene runs, who speaks, which seeds the writer tries, when each
/// post appears, and when the next scene is due; when events start and end and who moves
/// in or away — and stores each step in one transaction; ``SceneWriter`` owns everything
/// inside a scene's model call (requirements §3.2, §3.4, §3.6, §3.11).
///
/// It takes one step at a time. ``step()`` does at most one turn and says what it did;
/// ``run()`` repeats it, waiting on the injected clock until the next due time. A turn ends
/// the events whose end has come, may start an event and move someone, then writes the
/// scene — each call after the one before. A step arriving while another is under way
/// returns ``EngineStep/busy`` at once, so two model calls are never in flight and the
/// writer is never asked for two turns at once.
///
/// Everything it would read from the world is handed in (`designing-core-logic`): the clock
/// it waits on, the current date, its random numbers, and the thermal state. It is not
/// wired into the app here: the composition root builds and starts it (#27), and when it
/// runs is decided by presence and the setting (#29).
public actor TownEngine {
    /// What the engine works with: the town's store, the scene writer, the settings it reads
    /// speed and your name from, the seed tables events and newcomers draw from, and the
    /// model port.
    ///
    /// Not `Sendable`, since ``SettingsStore`` is not: it is handed to the engine whole and
    /// kept there.
    public struct Parts {
        /// The town's log.
        public var store: TownStore
        /// Writes each scene; the engine never overlaps two of its turns.
        public var writer: SceneWriter
        /// Speed and your display name, read at each turn.
        public var settings: SettingsStore
        /// The read-only lists events and newcomers draw from.
        public var seedTables: SeedTables
        /// The model: asked for its availability, an event's description, and a newcomer;
        /// scene calls go through ``writer``.
        public var model: any LanguageModelProviding

        /// Creates the parts an engine works with.
        public init(
            store: TownStore,
            writer: SceneWriter,
            settings: SettingsStore,
            seedTables: SeedTables,
            model: any LanguageModelProviding,
        ) {
            self.store = store
            self.writer = writer
            self.settings = settings
            self.seedTables = seedTables
            self.model = model
        }
    }

    /// What the engine would otherwise read from the world, handed in so a test controls
    /// it (`designing-core-logic` › Inject time, Inject randomness).
    public struct World: Sendable {
        /// The thermal state, read before each scene (`docs/architecture.md` › The
        /// on-device model). No default: one that always answered nominal would quietly
        /// run scenes on a hot Mac.
        public var thermalState: @Sendable () -> ThermalState
        /// What ``TownEngine/run()`` waits on.
        public var clock: any Clock<Duration>
        /// The current date, for due times and the times posts happen.
        public var now: @Sendable () -> Date
        /// Where every draw comes from: seeds, speakers, intervals, reveal gaps, events, and
        /// moves.
        public var generator: any RandomNumberGenerator & Sendable

        /// Creates a world reading `thermalState`, waiting on `clock`, dating by `now`,
        /// and drawing from `generator`.
        public init(
            thermalState: @escaping @Sendable () -> ThermalState,
            clock: any Clock<Duration> = ContinuousClock(),
            now: @escaping @Sendable () -> Date = { Date.now },
            generator: any RandomNumberGenerator & Sendable = SystemRandomNumberGenerator(),
        ) {
            self.thermalState = thermalState
            self.clock = clock
            self.now = now
            self.generator = generator
        }
    }

    /// Where the stored due time was measured from and the jitter draw it was measured
    /// with, so a speed change measures it again with the same draw (REQ-010). Kept in
    /// memory: after a relaunch the draw is unknown until the next turn.
    struct Pending {
        let anchor: Date
        let factor: Double
    }

    let store: TownStore
    let writer: SceneWriter
    let settings: SettingsStore
    let model: any LanguageModelProviding
    let world: World
    let tuning: Tuning
    let pace: ScenePace
    let rules: TownChangeRules
    /// The event kinds events draw from.
    let seedTables: SeedTables
    /// The resident axes newcomers draw from.
    let residentDraw: ResidentSeedDraw
    var generator: any RandomNumberGenerator & Sendable
    var pending: Pending?
    var responseRetryAt: Date?
    /// The move the next scene is about, until a scene is stored (REQ-009 of #25). Kept in
    /// memory, like ``pending``.
    var news: SceneCasting.News?
    /// When the previous turn of this run ran, which the next one measures its running
    /// time from; `nil` before the first, so a turn after launch draws no event or move.
    private var lastTurnAt: Date?
    var isBusy = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    /// The wait ``run()`` is in, cancelled to re-arm it after a speed change.
    var nap: Task<Void, Never>?

    /// Creates an engine over `parts`, reading `world`, under `tuning`'s pace. Creating it
    /// reads and writes nothing.
    public init(parts: sending Parts, world: World, tuning: Tuning = .default) {
        store = parts.store
        writer = parts.writer
        settings = parts.settings
        seedTables = parts.seedTables
        residentDraw = ResidentSeedDraw(axes: parts.seedTables.residentAxes)
        model = parts.model
        self.world = world
        self.tuning = tuning
        pace = ScenePace(tuning: tuning)
        rules = TownChangeRules(tuning: tuning)
        generator = world.generator
    }

    /// Takes one step: runs the due turn — ending events, perhaps starting one and moving
    /// someone, then writing the scene — skips it, or says how long nothing is due. Its
    /// model calls run one after another. A step arriving while another is under way
    /// returns ``EngineStep/busy`` without calling anything (REQ-008).
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled while a call is
    ///   under way; nothing of that call's event, move, or scene is stored (REQ-012). Every
    ///   other failure is an outcome, ``EngineStep/failed(_:)``, or a dropped event or move,
    ///   not a throw.
    public func step() async throws -> EngineStep {
        guard !isBusy else {
            EngineLog.record(.busy)
            return .busy
        }
        isBusy = true
        defer { becomeIdle() }
        let outcome = try await turn()
        EngineLog.record(outcome)
        return outcome
    }

    /// Steps, then waits on the clock until the next due time, again and again. After a
    /// failure, while the model is unavailable, or before a town is founded, it waits one
    /// drawn interval at the current speed before trying again.
    ///
    /// - Throws: `CancellationError` once its task is cancelled, whether it was waiting or
    ///   writing — the only way it returns.
    public func run() async throws {
        let changes = await store.changes()
        let observing = Task {
            for await change in changes {
                if Task.isCancelled {
                    return
                }
                await responseChange(change)
            }
        }
        defer { observing.cancel() }
        while true {
            try Task.checkCancellation()
            switch try await step() {
            case .busy:
                await untilIdle()

            case let .sceneStored(_, nextDue: due), let .skipped(_, nextDue: due):
                try await waitForNextTurn(fallback: due)

            case let .waiting(until: due):
                try await waitForNextTurn(fallback: due)

            case .failed, .modelUnavailable, .notFounded:
                let factor = pace.drawFactor(using: &generator)
                try await wait(seconds: pace.interval(at: settings.speed, factor: factor))
            }
        }
    }

    /// Tells the engine the speed setting changed: the pending due time is measured again
    /// from where it was measured — the last post of the last scene, or the moment a turn
    /// was skipped — at the new speed with the same jitter draw, stored, and ``run()``'s
    /// wait re-armed (REQ-010; requirements.md:210). Posts already stored keep their times.
    /// With no draw known yet in this session, it draws afresh from now.
    ///
    /// Waits for a step under way to finish first. A store failure is logged, and the
    /// next turn uses the new speed anyway.
    /// - Returns: The new due time, or `nil` before a town is founded or when the store
    ///   failed.
    @discardableResult
    public func speedChanged() async -> Date? {
        while isBusy {
            await untilIdle()
        }
        isBusy = true
        defer {
            becomeIdle()
            nap?.cancel()
        }
        let now = currentTime()
        do throws(TownStoreError) {
            guard try await store.schedule() != nil else {
                return nil
            }
            let measured = pending ?? Pending(
                anchor: now,
                factor: pace.drawFactor(using: &generator),
            )
            let due = pace.due(
                after: measured.anchor,
                speed: settings.speed,
                factor: measured.factor,
            )
            try await store.setNextOrdinarySceneDue(due)
            pending = measured
            EngineLog.recordSpeedChange()
            return due
        } catch {
            EngineLog.recordSpeedChangeFailure(error)
            return nil
        }
    }

    /// The current date, to the millisecond the store keeps.
    func currentTime() -> Date {
        ScenePace.wholeMilliseconds(world.now())
    }

    /// One step's work, while this step holds the engine.
    private func turn() async throws -> EngineStep {
        try Task.checkCancellation()
        let now = currentTime()
        let schedule: Schedule?
        do throws(TownStoreError) {
            try await prepareResponses()
            schedule = try await store.schedule()
        } catch {
            return .failed(error)
        }
        guard let schedule else {
            return .notFounded
        }
        var due = schedule.nextOrdinarySceneDue
        if let response = schedule.pendingResponses.first {
            let responseDue = max(response.dueAt, responseRetryAt ?? response.dueAt)
            due = min(due, responseDue)
        }
        do throws(TownStoreError) {
            if let last = try await store.lastScenePostTime() {
                due = max(due, last)
            }
        } catch { return .failed(error) }
        guard due <= now else {
            return .waiting(until: due)
        }
        let running = rules.runningTime(since: lastTurnAt, until: now, speed: settings.speed)
        lastTurnAt = now
        do throws(TownStoreError) {
            try await endEvents(at: now)
        } catch {
            return .failed(error)
        }
        guard model.availability == .available else {
            return .modelUnavailable
        }
        let heat = world.thermalState()
        guard heat.allowsScenes else {
            return await skip(.tooHot(heat), at: now)
        }
        try await changeTown(running: running, at: now)
        let response = schedule.pendingResponses.first.flatMap { pending in
            pending.dueAt <= now && (responseRetryAt.map { $0 <= now } ?? true) ? pending : nil
        }
        return try await writeScene(at: now, response: response)
    }

    /// Draws an event, then a move, after `running` seconds of running time; nothing on a
    /// turn with none, the first after launch (REQ-002, REQ-005 of #25).
    private func changeTown(running: TimeInterval, at now: Date) async throws {
        guard running > 0 else {
            return
        }
        try await drawEvent(running: running, at: now)
        try await drawMove(running: running, at: now)
    }

    /// Waits `seconds` on the clock, or until a speed change re-arms the wait.
    /// - Throws: `CancellationError` when the calling task is cancelled.
    func wait(seconds: TimeInterval) async throws {
        guard seconds > 0 else {
            return
        }
        let clock = world.clock
        let duration = ScenePace.duration(seconds)
        // Cancelled by a speed change as well as by the caller: either way the loop
        // decides what comes next, so the sleep's own CancellationError is not needed.
        let sleeping = Task { _ = try? await clock.sleep(for: duration) }
        nap = sleeping
        await withTaskCancellationHandler {
            await sleeping.value
        } onCancel: {
            sleeping.cancel()
        }
        if nap == sleeping {
            nap = nil
        }
        try Task.checkCancellation()
    }

    /// Returns once no step holds the engine.
    func untilIdle() async {
        guard isBusy else {
            return
        }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    func becomeIdle() {
        isBusy = false
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }
}
