/// Everything tied to one open town store. The composition root builds a fresh value
/// each time the store is opened, so moving away never reuses a closed engine or screen.
@MainActor
public struct AppTownSession {
    /// Screen models built together over the same store.
    public struct Screens {
        /// Name entry and founding.
        public let firstRun: FirstRunViewModel
        /// Timeline reading.
        public let timeline: TimelineViewModel
        /// Your posts.
        public let composer: ComposerViewModel
        /// Town status.
        public let statusLine: StatusLineViewModel
        let foundingSpeed: @MainActor () -> Speed?

        /// Keeps screen wiring in App. `foundingSpeed` returns the speed captured when
        /// the founding factory creates its model, so late observation cannot mistake
        /// an earlier name-entry setting for a change during founding. Omitting it keeps
        /// the root's initial-speed fallback for existing callers.
        public init(
            firstRun: FirstRunViewModel,
            timeline: TimelineViewModel,
            composer: ComposerViewModel,
            statusLine: StatusLineViewModel,
            foundingSpeed: @escaping @MainActor () -> Speed? = { nil },
        ) {
            self.firstRun = firstRun
            self.timeline = timeline
            self.composer = composer
            self.statusLine = statusLine
            self.foundingSpeed = foundingSpeed
        }
    }

    /// The current town's persistence boundary.
    public let store: TownStore
    /// Name entry and founding over this store.
    public let firstRun: FirstRunViewModel
    /// The town's reading surface.
    public let timeline: TimelineViewModel
    /// Posts remain writable even when the model is unavailable.
    public let composer: ComposerViewModel
    /// The status line shares the timeline's event-symbol lookup.
    public let statusLine: StatusLineViewModel
    let run: @MainActor () async throws -> Void
    let speedChanged: @MainActor () async -> Void
    let foundingSpeed: @MainActor () -> Speed?

    /// Binds the store and screens to the engine actions. The closures let tests observe
    /// lifecycle without introducing a second engine implementation or a new port.
    public init(
        store: TownStore,
        screens: Screens,
        run: @escaping @MainActor () async throws -> Void,
        speedChanged: @escaping @MainActor () async -> Void,
    ) {
        self.store = store
        firstRun = screens.firstRun
        timeline = screens.timeline
        composer = screens.composer
        statusLine = screens.statusLine
        foundingSpeed = screens.foundingSpeed
        self.run = run
        self.speedChanged = speedChanged
    }
}
