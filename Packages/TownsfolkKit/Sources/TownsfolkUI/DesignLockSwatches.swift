import SwiftUI

/// Both Color Sets side by side. In the canvas they render clear, because the preview
/// host has no copy of the app's asset catalog (ADR-0008 › Amended); the swatches show
/// the colors once the Color Sets move into a `TownsfolkUI` resource catalog.
private struct DesignLockSwatches: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignLock.Spacing.small) {
            // Developer-facing names in a preview, never shown in the app: verbatim, so
            // they stay out of the String Catalog a translator works from.
            Text(verbatim: "SecondaryText")
                .foregroundStyle(DesignLock.Palette.secondaryText)
            Rectangle()
                .fill(DesignLock.Palette.lamplight)
                .frame(height: DesignLock.Spacing.extraLarge)
                .overlay { Text(verbatim: "Lamplight") }
        }
        .padding(DesignLock.Spacing.large)
        .frame(width: DesignLock.Window.defaultWidth)
    }
}

#Preview("Design lock colors") {
    DesignLockSwatches()
}

#Preview("Design lock colors, dark") {
    DesignLockSwatches()
        .preferredColorScheme(.dark)
}
