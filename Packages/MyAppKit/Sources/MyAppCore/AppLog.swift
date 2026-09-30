import os

/// This app's unified-log entry point: one subsystem, one `Logger` per concern.
///
/// `MyAppCore` is allowed to `import os`. The Core ban list holds UI frameworks and the
/// OS-integration frameworks an adapter reaches for; `os` is neither — it is Apple's
/// logging facility, it pulls in no AppKit, and it works unchanged on every platform
/// Core is meant to serve, so keeping logging behind a port would buy nothing and cost
/// every call site an injection (`docs/architecture.md` › Logging). `MyAppUI`,
/// `MyAppPlatform`, and `App/` log through these same loggers, which they already see
/// by importing `MyAppCore`.
///
/// Never `print`, `debugPrint`, or `NSLog` under `Sources/` or `App/`: a `.app` launched
/// the way users launch it has nowhere to send stdout, so those lines vanish exactly
/// when they would matter. `.swiftlint.yml`'s `no_print_in_sources` rejects them.
/// Anything user-derived that reaches a log message carries a privacy annotation —
/// see ``FrontmostAppViewModel/refresh()`` for the worked example.
public enum AppLog {
    /// The subsystem every logger below is created with: this app's bundle identifier,
    /// and the value `just logs` filters the stream on.
    ///
    /// A literal rather than `Bundle.main.bundleIdentifier`, which answers for the test
    /// runner under `swift test` and for the preview agent in an Xcode preview — log
    /// lines would scatter across subsystems nothing is watching. It is spelled here
    /// once and nowhere else in Swift; `scripts/bootstrap.sh` rewrites it with the same
    /// placeholder replacement that rewrites `project.yml`, and `AppLogTests` fails if
    /// the two ever disagree.
    public static let subsystem = "com.example.MyApp"

    /// The frontmost-application concern: ``FrontmostAppProviding`` and its view model.
    ///
    /// One category per concern, named for the concern rather than for a type, so
    /// `log stream --predicate 'category == "frontmost-app"'` narrows the stream to one
    /// story. A new concern adds a `Logger` here instead of building one inline.
    public static let frontmostApp = Logger(subsystem: subsystem, category: "frontmost-app")
}
