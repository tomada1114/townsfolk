import Foundation

/// Every word the Settings pane shows, as String Catalog resources in the process's
/// locale. ``SettingsViewModel`` sets each to the app language and resolves it; a view
/// never reads these (ADR-0007 › Amended 2026-10-06).
///
/// Computed, so each read builds a fresh resource; `package`, so `LocalizationTests` can
/// list every key without the app seeing them.
package enum SettingsWording {
    /// The language picker's label.
    package static var languageTitle: LocalizedStringResource {
        LocalizedStringResource(
            "settings.language.title",
            defaultValue: "Language",
            bundle: .module,
            comment: "Settings: the label of the picker that chooses the app's language.",
        )
    }

    /// The helper under the language picker.
    package static var languageHelp: LocalizedStringResource {
        LocalizedStringResource(
            "settings.language.help",
            defaultValue: "Menus switch the next time Townsfolk opens.",
            bundle: .module,
            comment: """
            Settings: helper text under the language picker. The app's own text switches at \
            once; the menus macOS provides switch at the next launch.
            """,
        )
    }

    /// The name field's label.
    package static var nameTitle: LocalizedStringResource {
        LocalizedStringResource(
            "settings.name.title",
            defaultValue: "Your name",
            bundle: .module,
            comment: "Settings: the label of the field holding the person's own name in the town.",
        )
    }

    /// The speed picker's label.
    package static var speedTitle: LocalizedStringResource {
        LocalizedStringResource(
            "settings.speed.title",
            defaultValue: "Speed",
            bundle: .module,
            comment: "Settings: the label of the segmented control choosing how often the town posts.",
        )
    }

    /// The keep-moving toggle's label.
    package static var keepsMovingTitle: LocalizedStringResource {
        LocalizedStringResource(
            "settings.keepsMoving.title",
            defaultValue: "Keep the town moving while I use other apps",
            bundle: .module,
            comment: """
            Settings: the label of the toggle that lets the town keep running while another \
            app is in front, as long as its window is visible.
            """,
        )
    }

    /// The helper under the keep-moving toggle.
    package static var keepsMovingHelp: LocalizedStringResource {
        LocalizedStringResource(
            "settings.keepsMoving.help",
            defaultValue: "When off, the town rests unless its window is active.",
            bundle: .module,
            comment: "Settings: helper text under the keep-moving toggle. \"Rests\" means the town pauses.",
        )
    }

    /// The line under the name field after an invalid name was submitted, naming the
    /// accepted length.
    package static func nameError(length: ClosedRange<Int>) -> LocalizedStringResource {
        let shortest = length.lowerBound
        let longest = length.upperBound
        return LocalizedStringResource(
            "settings.name.error",
            defaultValue: "Use \(shortest)–\(longest) characters.",
            bundle: .module,
            comment: """
            Settings: shown under the name field when the submitted name is empty or too \
            long. The arguments are the fewest and the most characters a name may have.
            """,
        )
    }

    /// One segment of the speed picker.
    package static func speedName(_ speed: Speed) -> LocalizedStringResource {
        switch speed {
        case .slow:
            LocalizedStringResource(
                "settings.speed.slow",
                defaultValue: "Slow",
                bundle: .module,
                comment: "Settings: the slowest speed, a segment of the speed control.",
            )

        case .normal:
            LocalizedStringResource(
                "settings.speed.normal",
                defaultValue: "Normal",
                bundle: .module,
                comment: "Settings: the default speed, a segment of the speed control.",
            )

        case .fast:
            LocalizedStringResource(
                "settings.speed.fast",
                defaultValue: "Fast",
                bundle: .module,
                comment: "Settings: the fastest speed, a segment of the speed control.",
            )
        }
    }

    /// The helper under the speed picker: about how often a post arrives at `speed`
    /// (requirements §3.4).
    package static func speedHint(_ speed: Speed) -> LocalizedStringResource {
        switch speed {
        case .slow:
            LocalizedStringResource(
                "settings.speed.hint.slow",
                defaultValue: "About one new post every 15 minutes.",
                bundle: .module,
                comment: "Settings: helper under the speed control while Slow is chosen.",
            )

        case .normal:
            LocalizedStringResource(
                "settings.speed.hint.normal",
                defaultValue: "About one new post every 3 minutes.",
                bundle: .module,
                comment: "Settings: helper under the speed control while Normal is chosen.",
            )

        case .fast:
            LocalizedStringResource(
                "settings.speed.hint.fast",
                defaultValue: "About one new post every 30 seconds.",
                bundle: .module,
                comment: "Settings: helper under the speed control while Fast is chosen.",
            )
        }
    }
}
