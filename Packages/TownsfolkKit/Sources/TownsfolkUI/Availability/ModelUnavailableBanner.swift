import SwiftUI
import TownsfolkCore

/// Layout metrics for ``ModelUnavailableBanner``, drawn from the design lock.
private enum Layout {
    static let padding = DesignLock.Spacing.large
    static let spacing = DesignLock.Spacing.small
}

/// The banner's content for one notice: the warning symbol and the message in
/// `.callout`, the button trailing it, or below it when the window is too narrow for one
/// line.
struct ModelUnavailableBannerContent: View {
    let notice: AvailabilityNotice

    var body: some View {
        Group {
            if let action = notice.action {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Layout.spacing) {
                        message.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        NoticeActionButton(action: action)
                    }
                    VStack(alignment: .leading, spacing: Layout.spacing) {
                        message
                        NoticeActionButton(action: action)
                    }
                }
            } else {
                message
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Layout.padding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modelUnavailableBanner")
    }

    private var message: some View {
        Label {
            Text(notice.message)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("modelUnavailableMessage")
        } icon: {
            Image(systemName: AvailabilityLayout.problemSymbol)
        }
        .font(.callout)
        .foregroundStyle(.primary)
    }
}

/// The model-unavailable state as a banner under the town's title once a town exists
/// (ux-flows S1, S7). With the model available it renders nothing. When a message
/// appears, it is announced politely.
///
/// It renders ``AvailabilityViewModel`` and decides nothing.
public struct ModelUnavailableBanner: View {
    private let model: AvailabilityViewModel

    public var body: some View {
        // A container that exists in every state, unlike a `Group`, whose modifiers reach
        // only its children: with no notice there would be none, and nothing would refresh.
        VStack(spacing: 0) {
            if let notice = model.notice {
                ModelUnavailableBannerContent(notice: notice)
            }
        }
        .modifier(RefreshesWhenActive(model: model))
        .onChange(of: model.notice?.message.key, initial: true) { _, key in
            if key != nil, let message = model.notice?.message {
                // The default announcement priority is the polite one; nothing here
                // interrupts (ux-guidelines › Accessibility targets).
                AccessibilityNotification.Announcement(String(localized: message)).post()
            }
        }
    }

    /// Creates the banner over `model`.
    public init(model: AvailabilityViewModel) {
        self.model = model
    }
}

// MARK: - Previews

/// The banner for `availability` at the top of a minimum-size window, or a note to the
/// developer when the model is available and nothing is shown.
@MainActor
@ViewBuilder
private func bannerPreview(_ availability: ModelAvailability) -> some View {
    if let notice = AvailabilityNotice(availability) {
        VStack(spacing: 0) {
            ModelUnavailableBannerContent(notice: notice)
            Spacer()
        }
        .frame(width: AvailabilityLayout.previewWidth, height: AvailabilityLayout.previewHeight)
    } else {
        Text(verbatim: "Preview: the model is available, so nothing is shown.")
    }
}

#Preview("Banner, Apple Intelligence off") {
    bannerPreview(.appleIntelligenceOff)
}

#Preview("Banner, model not ready") {
    bannerPreview(.modelNotReady)
}

#Preview("Banner, not eligible") {
    bannerPreview(.deviceNotEligible)
}

#Preview("Banner, Apple Intelligence off, dark") {
    bannerPreview(.appleIntelligenceOff)
        .preferredColorScheme(.dark)
}

#Preview("Banner, model not ready, dark") {
    bannerPreview(.modelNotReady)
        .preferredColorScheme(.dark)
}

#Preview("Banner, not eligible, dark") {
    bannerPreview(.deviceNotEligible)
        .preferredColorScheme(.dark)
}
