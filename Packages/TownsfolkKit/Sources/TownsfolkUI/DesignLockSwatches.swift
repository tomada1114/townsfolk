import SwiftUI

/// Both Color Sets side by side, so a look at the canvas answers ADR-0008's open question
/// of whether a `TownsfolkUI` preview resolves the app catalog's colors.
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
