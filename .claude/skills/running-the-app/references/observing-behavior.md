# Observing behavior with no human at the keyboard

Three ways to watch a running build: a screenshot, a throwaway UI test that drives a
flow, and a launch that starts the app in a known state. Every command here was run
against this template's own app. Write every artifact to a scratch directory outside the
checkout — nothing below belongs in a commit.

## Screenshot

The whole screen, silently:

```bash
screencapture -x /tmp/shot.png
```

One window, without the drop shadow, which needs the window's CGWindowID:

```bash
screencapture -x -o -l "$window_id" /tmp/window.png
```

macOS ships no command that prints that id, so ask CoreGraphics for it. This snippet
prints the id of every on-screen, layer-0 (ordinary, non-panel) window owned by a
process name — save it to your scratch directory, not into the repository:

```swift
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? ""
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in list {
    guard window[kCGWindowOwnerName as String] as? String == owner,
          let number = window[kCGWindowNumber as String] as? Int,
          let layer = window[kCGWindowLayer as String] as? Int, layer == 0
    else { continue }
    print(number)
}
```

```bash
swift /tmp/windowid.swift Townsfolk     # prints one id per window
```

Reading the window list needs no permission; **capturing pixels does**. Screen Recording
is granted to the application that runs `screencapture` — your terminal, or whatever
launched the agent — not to this app, and it is a first-run TCC prompt like any other,
so it belongs in the single up-front ask. A denied grant is worse than an error: the
capture still succeeds and still writes a PNG, showing the desktop where the windows
should be. Look at the file you wrote before believing it.

A menu-bar-only app (`LSUIElement`, `MenuBarExtra` — **BACKGROUND:** `starting-an-app`)
has no ordinary window to capture until its menu is open, and opening that menu is a
click only a human or an accessibility grant can make. Prefer a log line or a Core test
for such a build, and fall back to a full-screen capture with the menu already open.

## Drive a flow with a throwaway XCUITest

`LaunchUITests/` is the only XCTest target (`project.yml`'s `TownsfolkLaunchUITests`, whose
`sources: [LaunchUITests]` takes the whole directory), so a probe is one file plus
`just generate`. The app already carries accessibility identifiers for every control —
`counterValue`, `incrementButton`, `decrementButton`, `resetButton`, `frontmostAppLabel`
(`Packages/TownsfolkKit/Sources/TownsfolkUI/ContentView.swift`) — and a new control needs one
before it can be driven at all.

```swift
// LaunchUITests/ScratchProbeTests.swift — throwaway, never committed
import XCTest

final class ScratchProbeTests: XCTestCase {
    @MainActor
    func testProbe() {
        let app = XCUIApplication()
        app.launchArguments += ["-counterStart", "5"]
        app.launchEnvironment["PROBE_STATE"] = "known-state"
        app.launch()
        app.buttons["incrementButton"].click()
        app.buttons["incrementButton"].click()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "after-two-increments"
        shot.lifetime = .keepAlways
        add(shot)
        // macOS exposes a SwiftUI Text's string as `value` (sometimes `label`) and
        // updates it asynchronously — wait on a predicate covering both, exactly as
        // LaunchUITests/LaunchTests.swift does, instead of reading `.value` right away.
        let counter = app.staticTexts["counterValue"]
        let showsTwo = NSPredicate(format: "label == '2' OR value == '2'")
        let updated = XCTNSPredicateExpectation(predicate: showsTwo, object: counter)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
    }
}
```

Run that one test, keeping the result bundle out of the way of `just uitest`'s own:

```bash
mise exec -- xcodegen generate
xcodebuild test -project Townsfolk.xcodeproj -scheme Townsfolk -destination 'platform=macOS' \
  -derivedDataPath build/dev-derived-data -resultBundlePath build/Probe.xcresult \
  -only-testing:TownsfolkLaunchUITests/ScratchProbeTests
xcrun xcresulttool export attachments --path build/Probe.xcresult --output-path /tmp/att
```

The export writes each attachment under a UUID file name plus a `manifest.json` that
maps it back to `suggestedHumanReadableName` ("after-two-increments_0_….png") and the
test it came from — read the manifest, then look at the PNG. `just uitest` runs the whole
scheme (the launch guarantee included) and writes `build/LaunchUITests.xcresult`; use it
when you want both, `-only-testing:` while iterating.

Two rules about the probe:

- **It is deleted before the pull request**, along with a re-run of `just generate`.
  `LaunchUITests/` holds the launch guarantee and nothing else; a behavior worth keeping
  is a `TownsfolkCore` test against a fake, not a UI test (`.claude/rules/testing.md` ›
  Where a Test Goes). An XCUITest is slow, needs a GUI session, and asserts through the
  accessibility layer — everything a decision test should not be.
- **The first local XCUITest run may prompt for Accessibility** for whatever launched
  `xcodebuild`, exactly as the `just uitest` recipe warns. Same single up-front ask.

## Start the app in a known state

Nothing in this template reads a launch argument or an environment variable today:
`CounterViewModel` always starts at zero, and no `App/` or `TownsfolkCore` code consults
`UserDefaults` or `ProcessInfo`. The two snippets above pass `-counterStart 5` and
`PROBE_STATE` to prove the plumbing, not because the app answers them. **Do not add such
a hook to the app just to observe it** — a state you only need to *look at* is a state a
Core test can construct directly, by handing `ContentView` a view model, exactly as its
`#Preview("At the upper bound")` does.

When a hook is genuinely warranted — a state that is expensive or impossible to reach by
hand, wanted from both a UI probe and by hand — this is the mechanism, verified against a
running build:

```bash
open --env PROBE_STATE=known-state -n \
  build/dev-derived-data/Build/Products/Debug/Townsfolk.app --args -counterStart 5
ps -o command= -p "$(pgrep -f 'Debug/Townsfolk.app/Contents/MacOS/Townsfolk' | head -1)"
```

- `--args` puts everything after it in the process's `argv`, which is also what fills
  `UserDefaults`' argument domain: a `-key value` pair there is what `UserDefaults
  .standard.string(forKey: "key")` reads, ahead of any stored value, for that launch
  only. `--env KEY=value` adds an environment variable, which `ProcessInfo` reads.
  `XCUIApplication.launchArguments` and `.launchEnvironment` are the same two channels
  from a UI test.
- `-n` opens a *new* instance even though one is running, which is how you end up
  watching two builds at once. Quit the verified pid first (`kill -TERM "$pid"`) unless you meant it.
- The hook itself belongs in `TownsfolkCore`, behind one value a view model reads, so the
  same state stays reachable from a Core test. `App/` — the composition root — is where
  the argument is read and turned into that value, and Core never learns where it came
  from.
