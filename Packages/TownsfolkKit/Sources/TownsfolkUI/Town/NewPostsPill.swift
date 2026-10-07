import SwiftUI

/// The pill above the rows counting posts that arrived while you read older ones: the
/// system glass button style's capsule, the window's one material.
struct NewPostsPill: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.up")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("newPostsPill")
    }
}
