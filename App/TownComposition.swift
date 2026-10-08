import Foundation
import TownsfolkCore

/// Wiring for one open store; reused after moving away without keeping closed models.
@MainActor
enum TownComposition {
    nonisolated static let cannotOpenCode: Int32 = 14
    static let defaultsUnavailable = TownStoreError.cannotOpen(code: cannotOpenCode)

    static func open(
        provider: any LanguageModelProviding,
        defaults: UserDefaults,
        tuning: Tuning,
        scope: AppLaunchScope,
    ) throws -> AppTownSession {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first else {
            throw TownStoreError.cannotOpen(code: cannotOpenCode)
        }
        let store = try TownStore(
            directory: scope.townDirectory(
                applicationSupport: support,
                temporary: FileManager.default.temporaryDirectory,
            ),
            tuning: tuning,
        )
        let seeds = try SeedTables.load()
        let engine = try makeEngine(
            store: store,
            provider: provider,
            seeds: seeds,
            scope: scope,
            tuning: tuning,
        )
        return AppTownSession(
            store: store,
            screens: screens(
                town: (store: store, engine: engine),
                provider: provider,
                defaults: defaults,
                seeds: seeds,
                tuning: tuning,
            ),
            run: { try await engine.run() },
            speedChanged: { await engine.speedChanged() },
        )
    }

    nonisolated static func makeEngine(
        store: TownStore,
        provider: any LanguageModelProviding,
        seeds: SeedTables,
        scope: AppLaunchScope,
        tuning: Tuning,
    ) throws -> TownEngine {
        // The engine owns its own UserDefaults object for the same persisted domain.
        // Sending the main actor's object would cross the SettingsStore actor boundary.
        guard let engineDefaults = UserDefaults(suiteName: scope.settingsSuiteName) else {
            throw TownStoreError.cannotOpen(code: cannotOpenCode)
        }
        let writer = SceneWriter(model: provider, store: store, tuning: tuning)
        return TownEngine(
            parts: TownEngine.Parts(
                store: store,
                writer: writer,
                settings: SettingsStore(defaults: engineDefaults, tuning: tuning),
                seedTables: seeds,
                model: provider,
            ),
            world: TownEngine.World(
                thermalState: thermalState,
                clock: ContinuousClock(),
                generator: SystemRandomNumberGenerator(),
            ),
            tuning: tuning,
        )
    }

    private static func screens(
        town: (store: TownStore, engine: TownEngine),
        provider: any LanguageModelProviding,
        defaults: UserDefaults,
        seeds: SeedTables,
        tuning: Tuning,
    ) -> AppTownSession.Screens {
        let (store, engine) = town
        let symbols = Dictionary(uniqueKeysWithValues:
            seeds.eventKinds.map { ($0.id, $0.symbol) }
                + seeds.fixedEventKinds.map { ($0.id, $0.symbol) })
        let firstRun = FirstRunViewModel(defaults: defaults, tuning: tuning) { name in
            FoundingViewModel(
                displayName: name,
                founder: Founder(
                    model: provider,
                    writer: SceneWriter(model: provider, store: store, tuning: tuning),
                    seeds: seeds,
                    store: store,
                    tuning: tuning,
                ),
                store: store,
                speed: SettingsStore(defaults: defaults, tuning: tuning).speed,
                clock: ContinuousClock(),
            )
        }
        return AppTownSession.Screens(
            firstRun: firstRun,
            timeline: TimelineViewModel(
                store: store,
                displayName: SettingsStore(defaults: defaults, tuning: tuning).displayName,
                eventSymbols: symbols,
            ),
            composer: ComposerViewModel(
                write: { post throws(TownStoreError) in
                    let speed = SettingsStore(defaults: defaults, tuning: tuning).speed
                    try await engine.submitYourPost(post, speed: speed)
                },
                tuning: tuning,
            ),
            statusLine: StatusLineViewModel(store: store, eventSymbols: symbols),
        )
    }

    nonisolated static func thermalState() -> ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            .nominal

        case .fair:
            .fair

        case .serious:
            .serious

        case .critical:
            .critical

        @unknown default:
            .serious
        }
    }
}
