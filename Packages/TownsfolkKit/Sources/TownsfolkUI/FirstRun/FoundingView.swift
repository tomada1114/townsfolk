import SwiftUI
import TownsfolkCore

/// Layout metrics for ``FoundingView``, drawn from the design lock.
private enum Layout {
    static let margin = DesignLock.Spacing.extraLarge
    static let blockSpacing = DesignLock.Spacing.extraLarge
    static let stepSpacing = DesignLock.Spacing.small
    static let symbolGap = DesignLock.Spacing.small
    static let checkFadeIn = DesignLock.Motion.foundingCheckFadeIn
    /// A finished step's symbol (design lock › Symbols).
    static let doneSymbol = "checkmark"
    /// A step not finished yet.
    static let pendingSymbol = "circle.dotted"
    static let previewWidth = DesignLock.Window.minimumWidth
    static let previewHeight = DesignLock.Window.minimumHeight
}

/// One of S3's lines: its symbol, then its words. The check mark fades in over 150 ms —
/// opacity only, so it stays under Reduce Motion — and VoiceOver reads the symbol as
/// done or not yet.
struct FoundingStepRow: View {
    let line: FoundingStepLine

    var body: some View {
        HStack(spacing: Layout.symbolGap) {
            ZStack {
                Image(systemName: Layout.pendingSymbol)
                    .opacity(line.isDone ? 0 : 1)
                    .accessibilityHidden(true)
                Image(systemName: Layout.doneSymbol)
                    .opacity(line.isDone ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .animation(.easeOut(duration: Layout.checkFadeIn), value: line.isDone)
            .accessibilityElement()
            .accessibilityLabel(Text(line.status))
            Text(line.title)
        }
        .font(.body)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("foundingStep.\(line.step)")
    }
}

/// S3's heading, its three lines, and the slow line once it shows.
struct FoundingStepsContent: View {
    let model: FoundingViewModel

    var body: some View {
        Text(model.heading)
            .font(.title3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        VStack(alignment: .leading, spacing: Layout.stepSpacing) {
            ForEach(model.steps) { line in
                FoundingStepRow(line: line)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("foundingSteps")
        if let slow = model.slowNotice {
            Text(slow)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("foundingSlowNotice")
        }
    }
}

/// What S3 shows in place of the steps after founding failed: the message as the
/// heading, and Try Again as the default button.
struct FoundingFailedContent: View {
    let message: LocalizedStringResource
    let model: FoundingViewModel

    var body: some View {
        Text(message)
            .font(.title3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("foundingFailedMessage")
        Button(model.tryAgainTitle) {
            model.tryAgainPressed()
        }
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("foundingTryAgainButton")
    }
}

/// S3's content for one state: the steps, or the failure in their place.
struct FoundingContent: View {
    let model: FoundingViewModel

    var body: some View {
        VStack(spacing: Layout.blockSpacing) {
            if let failure = model.failureMessage {
                FoundingFailedContent(message: failure, model: model)
            } else {
                FoundingStepsContent(model: model)
            }
        }
        .foregroundStyle(.primary)
        .padding(Layout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// S3, the town being founded (ux-flows S3): the lines checked as the real steps finish,
/// the slow line after a minute, and the failure with Try Again. Shown at first run after
/// S2, and again after moving away (#30).
///
/// It renders ``FoundingViewModel`` and decides nothing: `.task(id:)` runs founding for as
/// long as the view is on screen, again after each Try Again, and the end of founding is
/// announced politely before the model reports ``FoundingViewModel/Phase/founded``. Where
/// the window goes next — S1 on `.founded`, S7 while the model is unavailable — is the
/// owner's (#27).
public struct FoundingView: View {
    private let model: FoundingViewModel

    public var body: some View {
        FoundingContent(model: model)
            .task(id: model.attempt) {
                // `run()` throws only `CancellationError`: the view went away, and the
                // screen stays as it was.
                try? await model.run()
            }
            .onChange(of: model.announcement, initial: true) { _, announcement in
                // Posted while S3 is still on screen; only then may the owner leave it.
                if let announcement {
                    // The default announcement priority is the polite one.
                    AccessibilityNotification
                        .Announcement(AttributedString(localized: announcement))
                        .post()
                    model.announcementPosted()
                }
            }
            .accessibilityIdentifier("foundingView")
    }

    /// Creates S3 over `model`, which its owner keeps — ``FirstRunViewModel`` at first
    /// run.
    public init(model: FoundingViewModel) {
        self.model = model
    }
}

// MARK: - Previews

/// S3 in a state, founding as Tomo at the minimum window size, or a note to the
/// developer when the name could not be made.
@MainActor
@ViewBuilder
private func foundingPreview(
    _ finished: Set<FoundingProgress>,
    isSlow: Bool = false,
    phase: FoundingViewModel.Phase = .founding,
) -> some View {
    if let name = try? DisplayName("Tomo") {
        FoundingView(model: FoundingViewModel(
            previewing: name,
            finished: finished,
            isSlow: isSlow,
            phase: phase,
        ))
        .frame(width: Layout.previewWidth, height: Layout.previewHeight)
    } else {
        Text(verbatim: "Preview: could not make the display name.")
    }
}

#Preview("S3, starting") {
    foundingPreview([])
}

#Preview("S3, streets drawn") {
    foundingPreview([.town])
}

#Preview("S3, neighbors met") {
    foundingPreview([.town, .residents])
}

#Preview("S3, said hello") {
    foundingPreview([.town, .residents, .firstScene])
}

#Preview("S3, slow") {
    foundingPreview([.town], isSlow: true)
}

#Preview("S3, failed") {
    foundingPreview([.town], phase: .failed)
}

#Preview("S3, starting, dark") {
    foundingPreview([])
        .preferredColorScheme(.dark)
}

#Preview("S3, streets drawn, dark") {
    foundingPreview([.town])
        .preferredColorScheme(.dark)
}

#Preview("S3, neighbors met, dark") {
    foundingPreview([.town, .residents])
        .preferredColorScheme(.dark)
}

#Preview("S3, said hello, dark") {
    foundingPreview([.town, .residents, .firstScene])
        .preferredColorScheme(.dark)
}

#Preview("S3, slow, dark") {
    foundingPreview([.town], isSlow: true)
        .preferredColorScheme(.dark)
}

#Preview("S3, failed, dark") {
    foundingPreview([.town], phase: .failed)
        .preferredColorScheme(.dark)
}
