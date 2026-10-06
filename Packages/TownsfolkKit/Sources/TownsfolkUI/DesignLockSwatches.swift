import SwiftUI

/// Both Color Sets side by side, read from `TownsfolkUI`'s own resource catalog so they
/// render in the canvas as well as in the app.
private struct DesignLockSwatches: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignLock.Spacing.small) {
            // Developer-facing names in a preview, never shown in the app: verbatim, so
            // they stay out of the String Catalog.
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
