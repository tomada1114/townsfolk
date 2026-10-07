import os

/// This app's unified-log entry point: one subsystem, one `Logger` per concern.
///
/// `TownsfolkCore` is allowed to `import os`. The Core ban list holds UI frameworks and the
/// OS-integration frameworks an adapter reaches for; `os` is neither — it is Apple's
/// logging facility, it pulls in no AppKit, and it works unchanged on every platform
/// Core is meant to serve, so keeping logging behind a port would buy nothing and cost
/// every call site an injection (`docs/architecture.md` › Logging). `TownsfolkUI`,
/// `TownsfolkPlatform`, and `App/` log through these same loggers, which they already see
/// by importing `TownsfolkCore`.
///
/// Never `print`, `debugPrint`, or `NSLog` under `Sources/` or `App/`: a `.app` launched
/// the way users launch it has nowhere to send stdout, so those lines vanish exactly
/// when they would matter. `.swiftlint.yml`'s `no_print_in_sources` rejects them.
/// Anything user-derived that reaches a log message carries a privacy annotation —
/// `.claude/rules/swift.md` › Logging says which values are `.private` and which `.public`.
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
    public static let subsystem = "io.github.tomada1114.Townsfolk"

    /// The window-presence concern: every value ``WindowPresenceProviding`` reports. Its
    /// three flags say nothing about the person, so they are logged `.public`.
    ///
    /// One category per concern, named for the concern rather than for a type, so
    /// `log stream --predicate 'category == "presence"'` narrows the stream to one story.
    /// A new concern adds a `Logger` here instead of building one inline.
    public static let presence = Logger(subsystem: subsystem, category: "presence")

    /// The settings concern: each change ``SettingsViewModel`` stores. Your name is never
    /// in it — only whether a submitted name was taken.
    public static let settings = Logger(subsystem: subsystem, category: "settings")

    /// The founding concern: each step finished, each failed attempt with its reason and
    /// counts, and how founding ended — all `.public`. Your name, the town's, a
    /// resident's, and anything else the model wrote are never in it.
    public static let founding = Logger(subsystem: subsystem, category: "founding")

    /// The on-device model concern: availability and the case a failed call maps to, both
    /// `.public` because they are states. No instructions, prompt, or generated text is
    /// ever in it.
    public static let model = Logger(subsystem: subsystem, category: "model")

    /// The scene-writing concern: each skipped turn and each item left out after repeated
    /// refusals, with its reason and counts `.public`. No prompt, post, name, or generated
    /// text is ever in it.
    public static let scenes = Logger(subsystem: subsystem, category: "scenes")

    /// The timeline concern: pages read and reads that failed, as row counts and error
    /// cases, both `.public`. No post text, name, or town name is ever in it.
    public static let timeline = Logger(subsystem: subsystem, category: "timeline")
}
