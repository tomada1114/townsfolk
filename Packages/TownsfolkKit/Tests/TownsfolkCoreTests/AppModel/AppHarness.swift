import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@MainActor
struct AppHarness {
    let model: AppModel
    let provider: FakeLanguageModelProvider
    let defaults: UserDefaults
    let suiteName: String
    let probe: AppRunProbe

    static func session(
        store: TownStore,
        defaults: UserDefaults,
        probe: AppRunProbe,
    ) -> AppTownSession {
        AppTownSession(
            store: store,
            screens: AppTownSession.Screens(
                firstRun: FirstRunViewModel(
                    defaults: defaults,
                    founding: FirstRunFixtures.idleFounding,
                ),
                timeline: TimelineViewModel(store: store, displayName: nil, eventSymbols: [:]),
                composer: ComposerViewModel(store: store) { StoreFixtures.morning },
                statusLine: StatusLineViewModel(store: store, eventSymbols: [:]),
            ),
            run: { try await probe.run() },
            speedChanged: { probe.speedChanged() },
        )
    }
}

@MainActor
private func withApp(
    availability: ModelAvailability,
    displayName: String?,
    _ body: (AppHarness, TownStore) async throws -> Void,
) async throws {
    let suite = "AppModelTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settingsStore = SettingsStore(defaults: defaults)
    settingsStore.displayName = try displayName.map { try DisplayName($0) }
    try await withStore { store, _ in
        let provider = FakeLanguageModelProvider(
            availability: availability,
            contextSize: WritingFixtures.roomyContextSize,
            outcomes: [],
            holdsResponses: false,
        )
        let probe = AppRunProbe()
        let model = AppModel(
            availability: AvailabilityViewModel(provider: provider),
            settings: SettingsViewModel(defaults: defaults),
        ) { AppHarness.session(store: store, defaults: defaults, probe: probe) }
        try await body(
            AppHarness(
                model: model,
                provider: provider,
                defaults: defaults,
                suiteName: suite,
                probe: probe,
            ),
            store,
        )
        await model.windowClosed()
    }
}

@MainActor
func withApp(_ body: (AppHarness, TownStore) async throws -> Void) async throws {
    try await withApp(availability: .available, displayName: nil, body)
}

@MainActor
func withApp(
    availability: ModelAvailability,
    _ body: (AppHarness, TownStore) async throws -> Void,
) async throws {
    try await withApp(availability: availability, displayName: nil, body)
}

@MainActor
func withApp(
    displayName: String,
    _ body: (AppHarness, TownStore) async throws -> Void,
) async throws {
    try await withApp(availability: .available, displayName: displayName, body)
}

@MainActor
func foundingRoot(app: AppHarness, store: TownStore) throws -> AppModel {
    try foundingRoot(
        app: app,
        store: store,
        fake: FoundingFixtures.fake(FoundingFixtures.happyPath),
    )
}

@MainActor
func foundingRoot(
    app: AppHarness,
    store: TownStore,
    fake: FakeLanguageModelProvider,
) throws -> AppModel {
    let founding = try FirstRunFixtures.founding(fake, store: store, name: FirstRunFixtures.tomo())
    let firstRun = FirstRunViewModel(defaults: app.defaults) { _ in founding }
    let session = AppHarness.session(store: store, defaults: app.defaults, probe: app.probe)
    return AppModel(
        availability: AvailabilityViewModel(provider: fake),
        settings: app.model.settings,
    ) {
        AppTownSession(
            store: store,
            screens: AppTownSession.Screens(
                firstRun: firstRun,
                timeline: session.timeline,
                composer: session.composer,
                statusLine: session.statusLine,
            ),
            run: { try await app.probe.run() },
            speedChanged: { app.probe.speedChanged() },
        )
    }
}
