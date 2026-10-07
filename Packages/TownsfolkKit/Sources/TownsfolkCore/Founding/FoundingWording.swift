import Foundation

/// The words founding writes into the town's log, as String Catalog resources.
///
/// `package`, so `LocalizationTests` can list every key without the app seeing them.
package enum FoundingWording {
    /// The founding row, the timeline's first: "You moved to Maplewood."
    package static func movedTo(town: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "founding.event.movedTo",
            defaultValue: "You moved to \(town).",
            bundle: .module,
            comment: """
            Timeline: the first row of every town, stored when it is founded. The argument is \
            the town's name.
            """,
        )
    }
}
