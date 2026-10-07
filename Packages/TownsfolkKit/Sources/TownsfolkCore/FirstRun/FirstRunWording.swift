import Foundation

/// Every word the first-run screens show (ux-flows S2, S3), as String Catalog resources.
/// ``FirstRunViewModel`` and ``FoundingViewModel`` hand each to the view.
///
/// Computed, so each read builds a fresh resource; `package`, so `LocalizationTests` can
/// list every key without the app seeing them.
package enum FirstRunWording {
    /// S2's heading.
    package static var welcome: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.welcome",
            defaultValue: "A small town is waiting for you.",
            bundle: .module,
            comment: "First run: the heading of the screen that asks for the person's name.",
        )
    }

    /// The question above the name field, and the field's label.
    package static var namePrompt: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.name.prompt",
            defaultValue: "What should the town call you?",
            bundle: .module,
            comment: "First run: the question above the name field, also the field's label.",
        )
    }

    /// The helper under the name field.
    package static var nameHelp: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.name.help",
            defaultValue: "Residents see this name on your posts.",
            bundle: .module,
            comment: "First run: helper text under the name field.",
        )
    }

    /// The one plain line about what writes the town.
    package static var machineryNote: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.machineryNote",
            defaultValue: "Its residents are written by Apple's on-device model, right on this Mac.",
            bundle: .module,
            comment: """
            First run: the one line that says the town's people are written by Apple's \
            on-device language model, which runs on this Mac only.
            """,
        )
    }

    /// The button that keeps the name and starts founding.
    package static var continueTitle: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.continue",
            defaultValue: "Continue",
            bundle: .module,
            comment: "First run: the default button that keeps the typed name and founds the town.",
        )
    }

    /// S3's heading while the town is founded.
    package static var foundingHeading: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.founding.heading",
            defaultValue: "Finding you a town…",
            bundle: .module,
            comment: "Founding: the heading while the person's town is being made, step by step.",
        )
    }

    /// The line added under the steps once founding has run for a while.
    package static var slow: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.founding.slow",
            defaultValue: "This is taking longer than usual.",
            bundle: .module,
            comment: "Founding: added under the steps once founding has run for a minute.",
        )
    }

    /// What S3 shows in place of the steps after founding failed.
    package static var failed: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.founding.failed",
            defaultValue: "Couldn't find you a town this time.",
            bundle: .module,
            comment: "Founding: shown in place of the steps when founding failed after every retry.",
        )
    }

    /// The button that founds again after a failure.
    package static var tryAgain: LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.founding.tryAgain",
            defaultValue: "Try Again",
            bundle: .module,
            comment: "Founding: the default button that starts founding again after it failed.",
        )
    }

    /// The line under the name field while the name is too long.
    package static func over(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.name.over",
            defaultValue: "\(count) over",
            bundle: .module,
            comment: """
            First run: shown under the name field while the name is too long. The argument \
            is how many characters over the limit it is.
            """,
        )
    }

    /// S3's line for `step`.
    package static func step(_ step: FoundingProgress) -> LocalizedStringResource {
        switch step {
        case .town:
            LocalizedStringResource(
                "firstRun.founding.step.town",
                defaultValue: "Drawing the streets",
                bundle: .module,
                comment: "Founding: the first step's line, checked once the town itself exists.",
            )

        case .residents:
            LocalizedStringResource(
                "firstRun.founding.step.residents",
                defaultValue: "Meeting the neighbors",
                bundle: .module,
                comment: "Founding: the second step's line, checked once the first residents exist.",
            )

        case .firstScene:
            LocalizedStringResource(
                "firstRun.founding.step.firstScene",
                defaultValue: "Saying hello",
                bundle: .module,
                comment: "Founding: the third step's line, checked once the residents' first posts exist.",
            )
        }
    }

    /// What VoiceOver says for a step's symbol: done, or not yet.
    package static func stepStatus(isDone: Bool) -> LocalizedStringResource {
        if isDone {
            LocalizedStringResource(
                "firstRun.founding.step.done",
                defaultValue: "Done",
                bundle: .module,
                comment: "Founding: VoiceOver label of a step's check mark, once the step is finished.",
            )
        } else {
            LocalizedStringResource(
                "firstRun.founding.step.pending",
                defaultValue: "Not yet",
                bundle: .module,
                comment: "Founding: VoiceOver label of a step's dotted circle, while the step is not finished.",
            )
        }
    }

    /// The polite announcement once the town is founded.
    package static func movedTo(town: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "firstRun.founding.announcement.movedTo",
            defaultValue: "You moved to \(town).",
            bundle: .module,
            comment: """
            Founding: VoiceOver announcement once the person's town is founded. The argument \
            is the town's name.
            """,
        )
    }
}
