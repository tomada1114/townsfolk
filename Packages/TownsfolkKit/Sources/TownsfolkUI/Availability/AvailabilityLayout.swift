import SwiftUI
import TownsfolkCore

/// Asks the view model again whenever the window becomes active (ux-flows S7), and once
/// when the view first appears.
struct RefreshesWhenActive: ViewModifier {
    let model: AvailabilityViewModel
    @Environment(\.scenePhase)
    private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.refresh()
            }
        }
    }
}

/// The button a notice offers, a system control in its default style.
struct NoticeActionButton: View {
    let action: AvailabilityNotice.Action
    @Environment(\.openURL)
    private var openURL

    var body: some View {
        Button(action.title) {
            openURL(action.url)
        }
        .accessibilityIdentifier("openSystemSettingsButton")
    }
}

/// Metrics both model-unavailable views share, drawn from the design lock.
enum AvailabilityLayout {
    /// SF Symbols' name for a problem, drawn in the text's own color, never red.
    static let problemSymbol = "exclamationmark.triangle"
    /// The narrowest the town window may get, the width each preview is drawn at.
    static let previewWidth = DesignLock.Window.minimumWidth
    /// The shortest the town window may get, the height each preview is drawn at.
    static let previewHeight = DesignLock.Window.minimumHeight
}
