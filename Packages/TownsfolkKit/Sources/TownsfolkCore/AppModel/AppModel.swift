import Foundation
import Observation

/// The one root model, shared explicitly by the town window, Settings, and commands.
/// It routes the existing screens and owns one cancellable engine run. Store and engine
/// construction remains in the composition root's factory, including reopening after a
/// move or a failed deletion. Construction starts no task and writes nothing.
@MainActor
@Observable
public final class AppModel {
    /// The root surface. Store failure has no approved copy: the root remains present
    /// with an empty surface, and logs the safe error case rather than founding over it.
    public enum Route: String, Sendable {
        /// The store has not finished opening.
        case opening
        /// A town with its timeline, optionally with the availability banner.
        case town
        /// S2, asking your name.
        case firstRun
        /// S3, including the announcement before handing over to the town.
        case founding
        /// S7, replacing first run while the model is unavailable.
        case unavailable
        /// The store could not open or read; no founding starts.
        case storeUnavailable
    }

    /// The availability model shared by S7 and the banner.
    public let availability: AvailabilityViewModel
    /// The Settings scene's model, shared instead of constructed by the view.
    public let settings: SettingsViewModel
    /// The current store and models, replaced together on reopening.
    public private(set) var session: AppTownSession?
    /// Last town read from the store, after its founding announcement has been posted.
    public private(set) var town: Town?
    /// The input #29 replaces with window presence in App alone.
    public private(set) var isActive = false
    /// Whether a run is owned, including while its cancellation is being awaited.
    public private(set) var isEngineRunning = false
    /// A reopened store cannot start until the previous engine has stopped.
    public private(set) var isReopening = false
    @ObservationIgnored private var storeGeneration = 0
    @ObservationIgnored private let factory: @MainActor () throws -> AppTownSession
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    @ObservationIgnored private var isOpening = false
    @ObservationIgnored private var isReadingFoundedTown = false
    @ObservationIgnored private var isWindowOpen = false
    @ObservationIgnored private var hasStoreFailure = false
    @ObservationIgnored private var lastRoute: Route?
    @ObservationIgnored private var lastSpeed: Speed
    @ObservationIgnored private var synchronizedFounding: FoundingViewModel?

    /// The current screen, derived from the retained models so a typed name survives S7.
    public var route: Route {
        if hasStoreFailure {
            return .storeUnavailable
        }
        guard let session else {
            return .opening
        }
        if town != nil {
            return .town
        }
        if availability.isUnavailable {
            return .unavailable
        }
        return session.firstRun.founding == nil ? .firstRun : .founding
    }

    /// The scene's title uses the stored town name, never a logged name.
    public var windowTitle: String {
        town?.name ?? TimelineViewModel.untitled
    }

    private var shouldRun: Bool {
        town != nil && !availability
            .isUnavailable && isActive && !hasStoreFailure && !isReopening && isWindowOpen
    }

    /// Creates the root with no I/O; ``open()`` performs the first store read.
    public init(
        availability: AvailabilityViewModel,
        settings: SettingsViewModel,
        factory: @escaping @MainActor () throws -> AppTownSession,
    ) {
        self.availability = availability
        self.settings = settings
        self.factory = factory
        lastSpeed = settings.speed
    }

    /// Opens the factory once. Repeated appearance of the root keeps the same models.
    public func open() async {
        guard !Task.isCancelled else {
            return
        }
        isWindowOpen = true
        if session != nil {
            await stateChanged()
            return
        }
        guard !isOpening, !hasStoreFailure else {
            return
        }
        isOpening = true
        let generation = storeGeneration
        defer { isOpening = false }
        do {
            let opened = try factory()
            let storedTown = try await opened.store.town()
            guard !Task.isCancelled, generation == storeGeneration else {
                return
            }
            session = opened
            town = storedTown
        } catch {
            guard !Task.isCancelled, generation == storeGeneration else {
                return
            }
            recordStoreFailure(error)
        }
        await stateChanged()
    }

    /// The app became active or inactive. Every activation rechecks model availability;
    /// cancellation finishes before another engine task can start.
    public func appActivityChanged(isActive: Bool) async {
        self.isActive = isActive
        if isActive {
            availability.refresh()
        }
        await stateChanged()
    }

    /// Child-screen or availability state changed. Founding hands over only after its
    /// announcement, and an unavailable founding attempt starts over when the model returns.
    public func stateChanged() async {
        guard !isReopening else {
            return
        }
        if let session, let founding = session.firstRun.founding {
            if town == nil, synchronizedFounding !== founding {
                synchronizedFounding = founding
                if let speed = session.foundingSpeed() {
                    lastSpeed = speed
                }
                settings.nameSubmitted(founding.displayName.value)
                displayNameChanged()
            }
            switch founding.phase {
            case .founded:
                await readFoundedTown()

            case .unavailable:
                availability.refresh()
                if !availability.isUnavailable {
                    founding.tryAgainPressed()
                }

            case .arrived, .failed, .founding:
                break
            }
        }
        logRoute()
        await reconcileEngine()
    }

    /// Settings changed speed. Unchanged observations do nothing, and the engine reads
    /// the new stored value before recomputing its due time. Before founding stores a
    /// schedule, the change waits for the handover to the town.
    public func speedChanged() async {
        guard town != nil, lastSpeed != settings.speed else {
            return
        }
        lastSpeed = settings.speed
        await session?.speedChanged()
    }

    /// Settings accepted a name; posts already displayed follow it immediately.
    public func displayNameChanged() {
        session?.timeline.displayNameChanged(settings.displayName)
    }

    /// Rebuilds through the same App factory after the store was closed by moving away,
    /// or after deletion failed. This action does not delete anything itself.
    public func reopen() async {
        guard !isReopening, !isOpening else {
            return
        }
        isReopening = true
        storeGeneration += 1
        await stopEngine()
        session = nil
        synchronizedFounding = nil
        town = nil
        hasStoreFailure = false
        isReopening = false
        await open()
    }

    /// The window task ended; its engine cannot continue behind a closed window.
    public func windowClosed() async {
        isActive = false
        isWindowOpen = false
        storeGeneration += 1
        await stopEngine()
    }

    private func readFoundedTown() async {
        guard town == nil, !isReadingFoundedTown, let session else {
            return
        }
        isReadingFoundedTown = true
        defer { isReadingFoundedTown = false }
        let generation = storeGeneration
        do {
            guard let founded = try await session.store.town(),
                  !Task.isCancelled, generation == storeGeneration
            else {
                return
            }
            // A speed chosen during founding could not update a schedule that did not
            // exist yet. Apply it before publishing the town and allowing its run.
            while lastSpeed != settings.speed {
                let speed = settings.speed
                await session.speedChanged()
                guard !Task.isCancelled, generation == storeGeneration else {
                    return
                }
                lastSpeed = speed
            }
            town = founded
        } catch {
            guard !Task.isCancelled, generation == storeGeneration else {
                return
            }
            recordStoreFailure(error)
        }
    }

    private func reconcileEngine() async {
        if !shouldRun {
            await stopEngine()
        }
        guard shouldRun, engineTask == nil, let session else {
            return
        }
        isEngineRunning = true
        engineTask = Task {
            do { try await session.run() } catch is CancellationError {
            /* The window or availability ended this run. */ } catch {
                AppLog.app.fault("engine run ended unexpectedly")
            }
        }
    }

    private func stopEngine() async {
        guard let task = engineTask else {
            return
        }
        task.cancel()
        await task.value
        if engineTask == task {
            engineTask = nil
            isEngineRunning = false
        }
    }

    private func logRoute() {
        let current = route
        guard current != lastRoute else {
            return
        }
        lastRoute = current
        AppLog.app.info("route: \(current.rawValue, privacy: .public)")
    }

    private func recordStoreFailure(_ error: any Error) {
        guard !(error is CancellationError), error as? TownStoreError != .cancelled else {
            return
        }
        hasStoreFailure = true
        if let failure = error as? TownStoreError {
            AppLog.app.fault("store unavailable: \(String(describing: failure), privacy: .public)")
        } else if let failure = error as? SeedTablesError {
            AppLog.app
                .fault("seed tables unavailable: \(String(describing: failure), privacy: .public)")
        } else {
            AppLog.app.fault("store factory failed")
        }
    }
}
