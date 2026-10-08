import SwiftUI
import TownsfolkCore
import TownsfolkPlatform
import TownsfolkUI

/// The composition root: adapter construction, scene wiring, and app activity input.
@main
struct TownsfolkApp: App {
    private static let townWindowID = "town"
    @State private var model: AppModel
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some Scene {
        Window(Text(verbatim: model.windowTitle), id: Self.townWindowID) {
            RootView(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    Task { await model.appActivityChanged(isActive: phase == .active) }
                }
        }
        .defaultSize(RootView.defaultSize)
        .commands {
            TownCommands(model: model)
            CommandGroup(replacing: .help) {
                // No help book: retain the system Help search without a dead Help item.
            }
        }
        Settings {
            SettingsView(model: model)
        }
    }

    init() {
        let provider = SystemLanguageModelProvider()
        #if DEBUG
            let scope = AppLaunchScope(testRunID: ProcessInfo.processInfo
                .environment["TOWNSFOLK_LAUNCH_TEST_ID"])
        #else
            let scope = AppLaunchScope()
        #endif
        let testDefaults = scope.settingsSuiteName.flatMap { UserDefaults(suiteName: $0) }
        let defaults = testDefaults ?? .standard
        let tuning = Tuning.default
        _model = State(initialValue: AppModel(
            availability: AvailabilityViewModel(provider: provider),
            settings: SettingsViewModel(defaults: defaults, tuning: tuning),
        ) {
            // Failed test-defaults construction must never found a town using real settings.
            guard scope.settingsSuiteName == nil || testDefaults != nil else {
                throw TownComposition.defaultsUnavailable
            }
            return try TownComposition.open(
                provider: provider,
                defaults: defaults,
                tuning: tuning,
                scope: scope,
            )
        })
    }
}
