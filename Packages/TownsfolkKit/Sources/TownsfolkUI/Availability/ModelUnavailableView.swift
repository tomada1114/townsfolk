import SwiftUI
import TownsfolkCore

/// Layout metrics for ``ModelUnavailableView``, drawn from the design lock.
private enum Layout {
    static let margin = DesignLock.Spacing.extraLarge
    static let blockSpacing = DesignLock.Spacing.extraLarge
}

/// The full-window form's content for one notice: the warning symbol, the message as the
/// state's heading in `.title3`, and the button where there is one.
struct ModelUnavailableContent: View {
    let notice: AvailabilityNotice

    var body: some View {
        VStack(spacing: Layout.blockSpacing) {
            Image(systemName: AvailabilityLayout.problemSymbol)
                .font(.title3)
                .accessibilityHidden(true)
            Text(notice.message)
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("modelUnavailableMessage")
            if let action = notice.action {
                NoticeActionButton(action: action)
            }
        }
        .foregroundStyle(.primary)
        .padding(Layout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modelUnavailableView")
    }
}

/// The model-unavailable state as the whole window, shown at first run in place of
/// founding (ux-flows S7). With the model available it renders nothing; where it goes is
/// the root view's choice.
///
/// It renders ``AvailabilityViewModel`` and decides nothing.
public struct ModelUnavailableView: View {
    private let model: AvailabilityViewModel

    public var body: some View {
        // A container that exists in every state, unlike a `Group`, whose modifiers reach
        // only its children: with no notice there would be none, and nothing would refresh.
        VStack(spacing: 0) {
            if let notice = model.notice {
                ModelUnavailableContent(notice: notice)
            }
        }
        .modifier(RefreshesWhenActive(model: model))
    }

    /// Creates the full-window form over `model`.
    public init(model: AvailabilityViewModel) {
        self.model = model
    }
}

// MARK: - Previews

/// The full-window form for `availability` at the minimum window size, or a note to the
/// developer when the model is available and nothing is shown.
@MainActor
@ViewBuilder
private func fullWindowPreview(_ availability: ModelAvailability) -> some View {
    if let notice = AvailabilityNotice(availability) {
        ModelUnavailableContent(notice: notice)
            .frame(width: AvailabilityLayout.previewWidth, height: AvailabilityLayout.previewHeight)
    } else {
        Text(verbatim: "Preview: the model is available, so nothing is shown.")
    }
}

#Preview("Full window, Apple Intelligence off") {
    fullWindowPreview(.appleIntelligenceOff)
}

#Preview("Full window, model not ready") {
    fullWindowPreview(.modelNotReady)
}

#Preview("Full window, not eligible") {
    fullWindowPreview(.deviceNotEligible)
}

#Preview("Full window, Apple Intelligence off, dark") {
    fullWindowPreview(.appleIntelligenceOff)
        .preferredColorScheme(.dark)
}

#Preview("Full window, model not ready, dark") {
    fullWindowPreview(.modelNotReady)
        .preferredColorScheme(.dark)
}

#Preview("Full window, not eligible, dark") {
    fullWindowPreview(.deviceNotEligible)
        .preferredColorScheme(.dark)
}
