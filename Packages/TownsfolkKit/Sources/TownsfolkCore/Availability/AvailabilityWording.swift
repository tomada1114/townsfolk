import Foundation

/// Every word the model-unavailable screen and banner show (ux-flows S7), as String
/// Catalog resources. ``AvailabilityViewModel`` hands each to the view.
///
/// Computed, so each read builds a fresh resource; `package`, so `LocalizationTests` can
/// list every key without the app seeing them.
package enum AvailabilityWording {
    /// The button that opens System Settings while Apple Intelligence is off.
    package static var openSystemSettings: LocalizedStringResource {
        LocalizedStringResource(
            "availability.openSystemSettings",
            defaultValue: "Open System Settings",
            bundle: .module,
            comment: "Model unavailable: the button that opens the System Settings app.",
        )
    }

    /// The message for an unavailable model, or `nil` while it is available.
    package static func message(_ availability: ModelAvailability) -> LocalizedStringResource? {
        switch availability {
        case .available:
            nil

        case .appleIntelligenceOff:
            // No documented URL opens the pane itself, so the message names it
            // (docs/architecture.md › The on-device model).
            LocalizedStringResource(
                "availability.appleIntelligenceOff.message",
                defaultValue: """
                Townsfolk needs Apple Intelligence to write the town. \
                Turn it on in System Settings › Apple Intelligence & Siri.
                """,
                bundle: .module,
                comment: """
                Model unavailable: Apple Intelligence is turned off. "Apple Intelligence & \
                Siri" is the name of the System Settings pane and must match the system's own.
                """,
            )

        case .modelNotReady:
            LocalizedStringResource(
                "availability.modelNotReady.message",
                defaultValue: "The on-device model is still downloading. The town starts when it's ready.",
                bundle: .module,
                comment: "Model unavailable: Apple Intelligence is on but its model is not downloaded yet.",
            )

        case .deviceNotEligible:
            LocalizedStringResource(
                "availability.deviceNotEligible.message",
                defaultValue: "This Mac can't run Apple Intelligence, which Townsfolk needs.",
                bundle: .module,
                comment: "Model unavailable: this Mac cannot run Apple Intelligence at all.",
            )
        }
    }
}
