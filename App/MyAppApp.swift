import MyAppCore
import MyAppPlatform
import MyAppUI
import SwiftUI

/// Application entry point — wiring only. All real code lives in Packages/MyAppKit.
///
/// This is also the composition root: the one place that knows both halves of a port.
/// It constructs the `MyAppPlatform` adapter and hands it to a `MyAppCore` view model,
/// so nothing below `App/` — not the view model, not the view — depends on which
/// implementation answers (`docs/architecture.md` › Layers).
@main
struct MyAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                frontmostApp: FrontmostAppViewModel(provider: WorkspaceFrontmostAppProvider()),
            )
        }
    }
}
