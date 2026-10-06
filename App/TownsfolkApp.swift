import SwiftUI
import TownsfolkCore
import TownsfolkPlatform
import TownsfolkUI

/// Application entry point — wiring only. All real code lives in Packages/TownsfolkKit.
///
/// This is also the composition root: the one place that knows both halves of a port.
/// It constructs each `TownsfolkPlatform` adapter and hands it to a `TownsfolkCore` view
/// model, so nothing below `App/` depends on which implementation answers
/// (`docs/architecture.md` › Layers). Window presence has no consumer yet — the engine
/// takes it in #29 — so for now every value is only logged.
@main
struct TownsfolkApp: App {
    /// The town `Window` scene's `id`, which SwiftUI also gives its `NSWindow` as the
    /// `identifier` the presence adapter looks the window up by (ADR-0006 › Amended).
    private static let townWindowID = "town"

    private let presence = WindowPresenceProvider(windowIdentifier: townWindowID)

    var body: some Scene {
        // One `Window`, not a `WindowGroup`: as the primary scene it offers no
        // File › New Window, and closing it quits the app (ADR-0001).
        Window(Text(verbatim: "Townsfolk"), id: Self.townWindowID) {
            RootView()
                .task {
                    for await value in presence.presenceUpdates() {
                        AppLog.presence.debug("""
                        presence visible=\(value.isWindowVisible, privacy: .public) \
                        active=\(value.isAppActive, privacy: .public) \
                        awake=\(value.isMacAwake, privacy: .public)
                        """)
                    }
                }
        }
        .defaultSize(RootView.defaultSize)
        .commands {
            CommandGroup(replacing: .help) {
                // Empty on purpose: there is no help book (ux-flows S8), so the
                // "Townsfolk Help" item would only open a "Help isn't available" alert.
                // The system keeps the Help menu's search field.
            }
        }

        Settings {
            SettingsView()
        }
    }
}
