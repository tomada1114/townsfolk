# Adding iOS Later

The template is macOS-only on purpose, but it is structured so iOS is an addition,
not a rewrite: `MyAppCore` imports only Observation and `os` (for logging), both
available on iOS, and is already platform-agnostic, and `MyAppUI` is plain SwiftUI.
`MyAppPlatform` is the macOS-only module by design: an iOS target links `MyAppUI` and
supplies its own adapters for the Core ports it needs, and Core is unchanged either
way.

## Runbook

1. **Add the platform to the package** — in `Packages/MyAppKit/Package.swift`:

   ```swift
   platforms: [.macOS(.v14), .iOS(.v17)],
   ```

2. **Add an iOS target in `project.yml`** — either a second thin shell:

   ```yaml
   MyAppIOS:
     type: application
     platform: iOS
     deploymentTarget: "17.0"
     sources: [AppIOS]
     dependencies:
       - package: MyAppKit
         product: MyAppUI
     settings:
       base:
         PRODUCT_BUNDLE_IDENTIFIER: com.example.MyApp.ios
         GENERATE_INFOPLIST_FILE: YES
   ```

   …with an `AppIOS/` folder containing its own `@main` entry point, or a
   single multi-platform target using `supportedDestinations` if you prefer.

3. **Regenerate and audit the UI layer** — `just generate`, then fix anything
   in `MyAppUI` that assumed macOS idioms (window sizes, `.click()`-era
   affordances). Core needs no changes; that is the point of the split.

4. **CI**: add a simulator job to `.github/workflows/ci.yml` — build/test with
   `-destination 'platform=iOS Simulator,name=iPhone 16'`. Simulator builds
   need no signing, so no new secrets.

5. **Defer signing** until you actually ship to devices/TestFlight; simulator
   CI keeps the target honest in the meantime.
