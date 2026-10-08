import Foundation

/// The words the engine writes into the town's log — the move rows — as String Catalog
/// resources (`docs/design/ux-guidelines.md:133`: "moved in", "moved away").
///
/// `package`, so `LocalizationTests` can list every key without the app seeing them.
package enum EngineWording {
    /// A move-in row: "Ren moved in."
    package static func movedIn(name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "engine.event.movedIn",
            defaultValue: "\(name) moved in.",
            bundle: .module,
            comment: """
            Timeline: the row stored when a new resident moves into town. The argument is \
            the resident's name.
            """,
        )
    }

    /// A move-out row: "Jun moved away."
    package static func movedAway(name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "engine.event.movedAway",
            defaultValue: "\(name) moved away.",
            bundle: .module,
            comment: """
            Timeline: the row stored when a resident moves out of town. The argument is the \
            resident's name.
            """,
        )
    }
}
