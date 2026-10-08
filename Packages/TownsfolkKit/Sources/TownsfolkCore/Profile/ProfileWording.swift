import Foundation

/// Every word the resident profile (ux-flows S4), the name button, and the Town menu's
/// Show Profile (S8) show or read aloud, as String Catalog resources. The fields
/// themselves — a name, an occupation, a worry — are the town's, not wording, and render
/// as written.
///
/// Computed, so each read builds a fresh resource; `package`, so `LocalizationTests` can
/// list every key without the app seeing them.
package enum ProfileWording {
    /// The label of the hobby row.
    package static var hobby: LocalizedStringResource {
        LocalizedStringResource(
            "profile.row.hobby",
            defaultValue: "Hobby",
            bundle: .module,
            comment: "Resident profile: the label of the row naming what the resident does for fun.",
        )
    }

    /// The label of the worry row.
    package static var worry: LocalizedStringResource {
        LocalizedStringResource(
            "profile.row.worry",
            defaultValue: "Worry",
            bundle: .module,
            comment: "Resident profile: the label of the row naming the resident's current worry.",
        )
    }

    /// The label of the relationships row.
    package static var knows: LocalizedStringResource {
        LocalizedStringResource(
            "profile.row.knows",
            defaultValue: "Knows",
            bundle: .module,
            comment: """
            Resident profile: the label of the row listing the other residents this one \
            knows, one per line.
            """,
        )
    }

    /// The label of the interests row.
    package static var into: LocalizedStringResource {
        LocalizedStringResource(
            "profile.row.into",
            defaultValue: "Into",
            bundle: .module,
            comment: """
            Resident profile: the label of the row listing the names you brought up that \
            the resident took up as their own, one per line.
            """,
        )
    }

    /// The Town menu's command showing the selected post's author's profile.
    package static var showProfile: LocalizedStringResource {
        LocalizedStringResource(
            "town.menu.showProfile",
            defaultValue: "Show Profile",
            bundle: .module,
            comment: """
            Menu bar: the Town menu command (⌘I) that opens the profile of the selected \
            post's author.
            """,
        )
    }

    /// What VoiceOver adds after a resident's name in a post header.
    package static var nameHint: LocalizedStringResource {
        LocalizedStringResource(
            "timeline.post.nameHint",
            defaultValue: "Show profile",
            bundle: .module,
            comment: """
            VoiceOver: the hint on a resident's name in a post header, which opens their \
            profile.
            """,
        )
    }

    /// The line under the name: what they do and their life stage.
    package static func summary(occupation: String, ageGroup: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "profile.summary",
            defaultValue: "\(occupation) · \(ageGroup)",
            bundle: .module,
            comment: """
            Resident profile: the line under the name. The arguments are the resident's \
            occupation and age group, as the town wrote them.
            """,
        )
    }

    /// One line of the relationships row.
    package static func knowsLine(name: String, description: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "profile.knows.line",
            defaultValue: "\(name) — \(description)",
            bundle: .module,
            comment: """
            Resident profile: one line of the Knows row. The arguments are the other \
            resident's name and what they are to each other.
            """,
        )
    }

    /// One line of the interests row.
    package static func interestLine(term: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "profile.into.line",
            defaultValue: "\(term) (from you)",
            bundle: .module,
            comment: """
            Resident profile: one line of the Into row. The argument is a name you brought \
            up in a post that the resident took up.
            """,
        )
    }

    /// The last line, for a resident still in town.
    package static func movedIn(date: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "profile.movedIn",
            defaultValue: "Moved in \(date)",
            bundle: .module,
            comment: """
            Resident profile: the last line. The argument is the day they moved in, an \
            abbreviated month and day such as "Sep 30".
            """,
        )
    }

    /// The last line, for a resident who has moved out.
    package static func movedOut(date: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "profile.movedOut",
            defaultValue: "Moved out \(date)",
            bundle: .module,
            comment: """
            Resident profile: the last line for a resident who has left town. The argument \
            is the day they moved out, an abbreviated month and day such as "Oct 12".
            """,
        )
    }
}
