import SwiftUI
import TownsfolkUI

/// Application entry point — wiring only. All real code lives in Packages/TownsfolkKit.
///
/// This is also the composition root: the one place that knows both halves of a port.
/// It constructs each `TownsfolkPlatform` adapter and hands it to a `TownsfolkCore` view
/// model, so nothing below `App/` depends on which implementation answers
/// (`docs/architecture.md` › Layers). The town window takes no port yet.
@main
struct TownsfolkApp: App {
    var body: some Scene {
        // One `Window`, not a `WindowGroup`: as the primary scene it offers no
        // File › New Window, and closing it quits the app (ADR-0001).
        Window(Text(verbatim: "Townsfolk"), id: "town") {
            RootView()
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
