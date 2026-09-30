import SwiftUI
import TownsfolkCore
import TownsfolkPlatform
import TownsfolkUI

/// Application entry point — wiring only. All real code lives in Packages/TownsfolkKit.
///
/// This is also the composition root: the one place that knows both halves of a port.
/// It constructs the `TownsfolkPlatform` adapter and hands it to a `TownsfolkCore` view model,
/// so nothing below `App/` — not the view model, not the view — depends on which
/// implementation answers (`docs/architecture.md` › Layers).
@main
struct TownsfolkApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                frontmostApp: FrontmostAppViewModel(provider: WorkspaceFrontmostAppProvider()),
            )
        }
    }
}
