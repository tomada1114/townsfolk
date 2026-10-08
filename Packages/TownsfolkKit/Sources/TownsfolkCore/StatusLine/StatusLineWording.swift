import Foundation

/// Every word the status line (ux-flows S1) shows or reads aloud, as String Catalog
/// resources. ``StatusLineViewModel`` hands each to the view, which renders it as it is.
///
/// Computed, so each read builds a fresh resource; `package`, so `LocalizationTests` can
/// list every key without the app seeing them.
package enum StatusLineWording {
    /// What VoiceOver calls the status line; its value is the full line.
    package static var accessibilityLabel: LocalizedStringResource {
        LocalizedStringResource(
            "statusLine.accessibilityLabel",
            defaultValue: "Town status",
            bundle: .module,
            comment: "Status line: what VoiceOver calls the one line at the top of the town window.",
        )
    }

    /// An ongoing event and the latest topic.
    package static func eventAndTopic(event: String, topic: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "statusLine.eventAndTopic",
            defaultValue: "\(event) · \(topic)",
            bundle: .module,
            comment: """
            Status line: the one line at the top of the town window while an event is going \
            on and the town has a recent topic. The first argument is the event's \
            one-line description, the second the topic.
            """,
        )
    }

    /// An ongoing event, with no recent topic.
    package static func event(_ event: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "statusLine.event",
            defaultValue: "\(event)",
            bundle: .module,
            comment: """
            Status line: the one line at the top of the town window while an event is going \
            on and the town has no recent topic. The argument is the event's one-line \
            description.
            """,
        )
    }

    /// The latest topic, with no ongoing event.
    package static func topic(_ topic: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "statusLine.topic",
            defaultValue: "Everyone's talking about \(topic)",
            bundle: .module,
            comment: """
            Status line: the one line at the top of the town window when no event is going \
            on. The argument is what the residents posted about most recently.
            """,
        )
    }

    /// No ongoing event and no recent topic.
    package static func quiet(town: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "statusLine.quiet",
            defaultValue: "A quiet day in \(town)",
            bundle: .module,
            comment: """
            Status line: the one line at the top of the town window when no event is going \
            on and nobody posted about anything recently. The argument is the town's name.
            """,
        )
    }
}
