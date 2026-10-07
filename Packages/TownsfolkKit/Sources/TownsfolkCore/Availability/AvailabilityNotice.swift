import Foundation

/// What the window says about an unavailable model, and what it offers to do about it
/// (ux-flows S7). The full-window form and the banner render the same notice.
public struct AvailabilityNotice: Equatable, Sendable {
    /// What a person can do about an unavailable model: a button's title and the URL it
    /// opens.
    public struct Action: Equatable, Sendable {
        /// The button's title.
        public let title: LocalizedStringResource
        /// What the button opens, through SwiftUI's `openURL`.
        public let url: URL
    }

    /// The System Settings app itself. Apple documents no URL for the Apple Intelligence
    /// & Siri pane, so the button opens the app and the message names the pane
    /// (docs/architecture.md › The on-device model).
    public static let systemSettingsURL = URL(
        fileURLWithPath: "/System/Applications/System Settings.app",
        isDirectory: false,
    )

    /// The message, read as the state's heading or the banner's line.
    public let message: LocalizedStringResource
    /// The one thing a person can do, offered only while Apple Intelligence is off.
    public let action: Action?

    /// The notice for `availability`, or `nil` when the model is available and nothing is
    /// shown.
    public init?(_ availability: ModelAvailability) {
        guard let text = AvailabilityWording.message(availability) else {
            return nil
        }
        message = text
        switch availability {
        case .appleIntelligenceOff:
            action = Action(
                title: AvailabilityWording.openSystemSettings,
                url: Self.systemSettingsURL,
            )

        case .available, .modelNotReady, .deviceNotEligible:
            action = nil
        }
    }
}
