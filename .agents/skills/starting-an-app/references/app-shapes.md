# App shapes: windowed and menu-bar agent

Two shapes cover most macOS apps started from this template. Choose one before writing
features. The difference is only three files — `project.yml`, `App/MyAppApp.swift`, and
`LaunchUITests/LaunchTests.swift` — but it decides what the launch guarantee *is*, and
therefore what `just uitest` is able to assert at all.

| | Windowed (what the template ships) | Menu-bar agent |
|---|---|---|
| Dock tile, app switcher, ⌘Tab | yes | no |
| Main menu, ⌘Q, ⌘, | yes | no — the status item is the whole surface |
| `project.yml` key | none | `INFOPLIST_KEY_LSUIElement: YES` |
| Scene | `WindowGroup` | `MenuBarExtra` |
| Launch guarantee | a window appears | a status item appears |
| `XCUIApplication().state` after `launch()` | `.runningForeground` | `.runningBackground` |
| `just smoke` | unchanged | unchanged — it asserts the process stays alive, never a window |

Everything else is identical: the three targets and the one-way dependency direction,
ports and adapters, the coverage floor, signing, and every gate.

## Windowed: read the shipped files, not a copy

The template **is** the windowed reference, so it is not duplicated here — a copy would
be the first thing to go stale. Read `App/MyAppApp.swift` (a `WindowGroup` holding
`ContentView`) and `LaunchUITests/LaunchTests.swift` (wait for `app.windows.firstMatch`,
then click through the counter). The app target needs no shape-specific `project.yml`
key: `GENERATE_INFOPLIST_FILE: YES` with no `LSUIElement` entry *is* the regular shape.

## Menu-bar agent

Every block in this section was applied to a clone of this template and proven there:
`just build`, `just uitest`, and `just smoke` pass with exactly this text, and
`just lint` (SwiftFormat plus SwiftLint `--strict` with every opt-in rule) accepts it.
Copy it verbatim; the `NSStatusItem` variant further down was proven by `just build`
and `just lint` only.

### 1. `project.yml` — one key

One line in the `MyApp` target's `settings.base`, beside `GENERATE_INFOPLIST_FILE`
(leave the UI-test target's copy of that key alone):

```yaml
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyApp
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSUIElement: YES
```

`INFOPLIST_KEY_LSUIElement` is how a generated Info.plist gets `LSUIElement`; there is
no Info.plist file to edit, and adding one would fight `GENERATE_INFOPLIST_FILE`.
Regenerate with `just generate` — `MyApp.xcodeproj` is generated output, never edited.

### 2. `App/MyAppApp.swift` — the entry point

```swift
import MyAppCore
import MyAppPlatform
import MyAppUI
import SwiftUI

/// Application entry point — wiring only. All real code lives in Packages/MyAppKit.
///
/// A menu-bar agent: `LSUIElement` keeps it out of the Dock and the app switcher, so
/// `MenuBarExtra` is the whole user interface. `.menuBarExtraStyle(.window)` renders
/// the content as a panel; the default `.menu` style renders it as an NSMenu and
/// accepts only menu-shaped content (`Button`, `Divider`, `Text`).
///
/// This is also the composition root: the one place that knows both halves of a port.
@main
struct MyAppApp: App {
    var body: some Scene {
        MenuBarExtra("MyApp", systemImage: "number.circle") {
            ContentView(
                frontmostApp: FrontmostAppViewModel(provider: WorkspaceFrontmostAppProvider()),
            )
        }
        .menuBarExtraStyle(.window)
    }
}
```

The shell still only wires: the scene type and the composition root line are the whole
diff from the windowed entry point. The panel's content is a `MyAppUI` view — here the
template's own `ContentView`, swapped for the app's real view later — and every
decision it renders stays in `MyAppCore`.

### 3. `LaunchUITests/LaunchTests.swift` — the replacement assertion

```swift
import XCTest

/// The agent app's launch guarantee: it starts and puts its item in the menu bar.
///
/// There is no window to wait for — `LSUIElement` makes the status item the app's
/// whole visible surface.
///
/// XCTest by necessity — Apple has not ported UI automation to Swift Testing.
/// All other tests use Swift Testing in Packages/MyAppKit.
final class LaunchTests: XCTestCase {
    private enum Timeout {
        static let statusItemAppears: TimeInterval = 10
    }

    @MainActor
    func testAppLaunchesAndShowsItsStatusItem() {
        // A failed launch assertion should end the test immediately instead of
        // cascading through the remaining waits against a dead app.
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launch()

        // An accessory app never reaches the foreground: `app.windows` stays empty and
        // `app.state` stays `.runningBackground`. The status item is the assertion —
        // it sits in a second `menuBars` element of the app's own accessibility tree,
        // beside the main menu an agent app never shows. Do not add `isHittable`: a
        // background app's status item reports false until something activates the app,
        // which `click()` does for itself.
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: Timeout.statusItemAppears))
    }
}
```

## What XCUITest can and cannot see

Measured on this template, not recalled — re-measure before trusting any of it on a
newer SDK:

- **`app.launch()` works.** It does not hang or fail on an accessory app, even though
  the app never becomes frontmost. `app.state` is `.runningBackground` and
  `app.windows.count` is `0`; neither is worth asserting on.
- **The status item is in the app's own tree**, as
  `app.menuBars.statusItems.firstMatch` — `menuBars` holds two elements, the main menu
  the agent never shows and a second one holding the status item. Its `title` is the
  `systemImage` name (`number.circle` above), not the `MenuBarExtra` label.
- **`isHittable` is `false`** until something activates the app, so an `isHittable`
  assertion fails right after launch. `click()` activates the app itself and works.
- **`.menuBarExtraStyle(.window)` content is invisible to XCUITest.** After clicking
  the status item, `windows`, `popovers`, `sheets`, `groups`, `otherElements`, and
  `staticTexts` are all empty — the panel is not exposed through the app's accessibility
  tree. The launch test therefore stops at "the item exists"; the behavior inside the
  panel is covered by `MyAppCore` view-model tests, which is where it belongs anyway.
- **The default `.menu` style *is* reachable**: after `click()`, its entries appear as
  `app.menuItems[…]`. They are matched **by title**
  (`app.menuItems["Increment"]`) — a SwiftUI `.accessibilityIdentifier` on a menu
  `Button` is dropped, and the element's identifier reads `menuAction:`. If the launch
  test must assert more than the item's existence, that is the price of the `.menu`
  style.

## When `MenuBarExtra` is not enough: `NSStatusItem`

Reach for `MenuBarExtra` first — it is a pure SwiftUI scene and needs no delegate. An
`NSStatusItem` only earns its place when the scene cannot express the requirement: a
custom status-item view, a drag destination, or a right-click menu distinct from the
left-click behavior.

**Where the delegate lives: `MyAppPlatform`, not `App/`.** It imports AppKit, owns
state, and runs at a lifecycle moment — all three make it OS-integration code, which
`docs/architecture.md` ("Ports and adapters") puts in `MyAppPlatform`. `App/` keeps the
one wiring line that names it, and nothing more; anything the delegate has to *decide*
moves into `MyAppCore` behind a port, like every other adapter. (`MyAppUI` is the wrong
home for the same reason it cannot see `MyAppPlatform`: it is the view layer, not the
OS layer.)

`Packages/MyAppKit/Sources/MyAppPlatform/StatusItemAppDelegate.swift`:

```swift
import AppKit

/// Owns an `NSStatusItem` for the cases `MenuBarExtra` cannot express: a custom button
/// view, a drag destination, or a right-click menu distinct from the left-click one.
///
/// It lives in `MyAppPlatform` because it imports AppKit and holds state — the app
/// shell stays wiring only (`docs/architecture.md` › Layers) and declares it with a
/// single `@NSApplicationDelegateAdaptor` line. Anything it has to decide belongs in
/// `MyAppCore` behind a port, the same as any other adapter.
@MainActor
public final class StatusItemAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    /// Required: `NSApplicationDelegateAdaptor` instantiates the type itself.
    override public init() {
        super.init()
    }

    /// Creates the status item once AppKit is running — `NSStatusBar` has no menu bar
    /// to add to before this. The item is retained here; releasing it removes it.
    public func applicationDidFinishLaunching(_: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "number.circle",
            accessibilityDescription: "MyApp",
        )
        statusItem = item
    }
}
```

`applicationDidFinishLaunching(_:)` takes an unnamed parameter on purpose: SwiftLint's
`unused_parameter` rejects a named one it never reads, and the protocol conformance does
not care about the name. In `MyAppApp`, the whole wiring is:

```swift
    @NSApplicationDelegateAdaptor(StatusItemAppDelegate.self)
    private var appDelegate
```

## What an agent app loses, and what to do about it

- **Quitting.** There is no ⌘Q and no app menu, so a locally run agent app has no way
  out until you give it one: `pkill -x MyApp` is the stopgap (verified), a Quit control
  in the menu content is the fix. `NSApplication.shared.terminate(nil)` is AppKit, so it
  goes behind a Core port with a `MyAppPlatform` adapter like any other OS call — do not
  import AppKit into `MyAppUI` for it.
- **Settings.** ⌘, is gone with the app menu. Add a `Settings { SettingsView() }` scene
  beside the `MenuBarExtra` in the same `body` (a `Scene` builder takes both), put
  `SettingsView` in `MyAppUI`, and open it from the menu content with
  `SettingsLink { … }` (macOS 14+, which this template already targets). The skeleton
  above leaves both out — add them when the app has something to configure.
- **Being noticed at all.** An agent app that launches and shows nothing is
  indistinguishable from one that crashed. Keep `just smoke` in the loop: it is the only
  gate that says the Release build stays alive, and it needs no change for this shape.

## What does not change

`scripts/smoke_launch.sh`, `App/MyApp.entitlements`, signing and notarization, the
coverage floor, and the layer rules are all shape-independent. An agent app is still an
ordinary signed app bundle — `LSUIElement` only tells the Dock and the app switcher to
ignore it.
