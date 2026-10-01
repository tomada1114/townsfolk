import SwiftUI

/// Layout metrics for ``SettingsView``, drawn from the design lock.
private enum Layout {
    static let width = DesignLock.Window.settingsWidth
}

/// The Settings window's one pane, which the `Settings` scene in `App/` holds and ⌘,
/// opens.
///
/// A placeholder with no text until Settings' controls land.
public struct SettingsView: View {
    public var body: some View {
        Form {
            // Settings' controls go here, in the system form's own spacing.
        }
        .formStyle(.grouped)
        .frame(width: Layout.width)
        .accessibilityIdentifier("settingsPane")
    }

    public init() {
        // Public so `App/` can build it; the pane has no state to take yet.
    }
}

#Preview("Empty") {
    SettingsView()
}

#Preview("Empty, dark") {
    SettingsView()
        .preferredColorScheme(.dark)
}
