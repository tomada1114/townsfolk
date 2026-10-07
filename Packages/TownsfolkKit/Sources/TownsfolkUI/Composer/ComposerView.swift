import SwiftUI
import TownsfolkCore

/// Layout metrics for ``ComposerView`` and its parts, drawn from the design lock.
private enum Layout {
    /// Between the chip, the field, and the counter.
    static let gap = DesignLock.Spacing.extraSmall
    /// The side of the chip's square ✕ button, the size of every icon button.
    static let iconButtonSide = DesignLock.Timeline.replyButtonSide
}

/// The replying chip: the reply symbol, "Replying to {name} "{text}"" cut to one line,
/// and a ✕ that leaves reply mode. VoiceOver reads it "Replying to {name}: {text}".
private struct ReplyChip: View {
    let title: LocalizedStringResource
    let reading: LocalizedStringResource
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: Layout.gap) {
            Label {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: "arrowshape.turn.up.left")
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(reading))
            .accessibilityIdentifier("replyChip")
            Spacer(minLength: 0)
            Button(action: cancel) {
                Label(ComposerViewModel.cancelReplyTitle, systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: Layout.iconButtonSide, height: Layout.iconButtonSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(Text(ComposerViewModel.cancelReplyTitle))
            .accessibilityIdentifier("cancelReplyButton")
        }
        .font(.callout)
        .foregroundStyle(DesignLock.Palette.secondaryText)
    }
}

/// The counter under the field: "{n} left" in SecondaryText, or "{n} over" in the primary
/// color with a warning symbol, so color is never the only sign.
private struct CounterLabel: View {
    let counter: ComposerCounter

    var body: some View {
        Group {
            if counter.isOver {
                Label(counter.title, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.primary)
            } else {
                Text(counter.title)
                    .foregroundStyle(DesignLock.Palette.secondaryText)
            }
        }
        .font(.callout)
        .accessibilityIdentifier("composerCounter")
    }
}

/// The composer (ux-flows S1 and its Replying variant): one line where you post as
/// yourself, the replying chip above it while you reply, and the counter under it near
/// the limit.
///
/// It renders ``ComposerViewModel`` and decides nothing: Return posts, Esc leaves reply
/// mode and then the composer, and the model's focus requests move the keyboard focus.
/// The placeholder is drawn in SecondaryText through the field's prompt, which the system
/// field honors (`docs/design/design-direction.md` › Measured contrast). It adds no
/// animation of its own.
struct ComposerView: View {
    let model: ComposerViewModel
    /// The town's name, for the placeholder.
    let townName: String
    @FocusState private var isFocused: Bool

    var body: some View {
        let placeholder = ComposerViewModel.placeholder(townName: townName)
        VStack(alignment: .leading, spacing: Layout.gap) {
            if let chip = model.replyChip, let reading = model.replyChipReading {
                ReplyChip(title: chip, reading: reading) {
                    model.cancelReplyChosen()
                }
            }
            TextField(
                text: Binding(get: { model.text }, set: { model.textChanged(to: $0) }),
                prompt: Text(placeholder).foregroundStyle(DesignLock.Palette.secondaryText),
            ) {
                Text(placeholder)
            }
            .font(.body)
            .focused($isFocused)
            .onSubmit {
                Task { await model.returnPressed() }
            }
            .onExitCommand {
                model.escapePressed()
            }
            .accessibilityIdentifier("composerField")
            if let counter = model.counter {
                CounterLabel(counter: counter)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onChange(of: model.focusRequest) {
            isFocused = true
        }
        .onChange(of: model.focusLeaveRequest) {
            isFocused = false
        }
    }
}
