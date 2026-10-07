import SwiftUI
import TownsfolkCore

/// Layout metrics for ``FirstRunView``, drawn from the design lock.
private enum Layout {
    static let margin = DesignLock.Spacing.extraLarge
    static let blockSpacing = DesignLock.Spacing.extraLarge
    static let lineSpacing = DesignLock.Spacing.small
    /// The same cap as the timeline's text column, so a wide window centers the form.
    static let maxWidth = DesignLock.Timeline.textColumnMaxWidth
    /// A problem's symbol, beside "{n} over" so the text never relies on color.
    static let problemSymbol = "exclamationmark.triangle"
    static let previewWidth = DesignLock.Window.minimumWidth
    static let previewHeight = DesignLock.Window.minimumHeight
}

/// S2's content (ux-flows S2): the heading, the name field with its question and helper,
/// "{n} over" while the name is too long, the one line about the machinery, and Continue —
/// the default button, enabled only for a valid name.
struct NameEntryView: View {
    let model: FirstRunViewModel
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockSpacing) {
            Text(model.welcome)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            nameBlock
            Text(model.machineryNote)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(model.continueTitle) {
                    model.continuePressed()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinue)
                .accessibilityIdentifier("firstRunContinueButton")
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
        .frame(maxWidth: Layout.maxWidth)
        .padding(Layout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isNameFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("firstRunNameEntry")
    }

    /// The question, the field, "{n} over" while the name is too long, and the helper.
    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: Layout.lineSpacing) {
            Text(model.namePrompt)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            nameField
            if let over = model.overLimit {
                Label(over, systemImage: Layout.problemSymbol)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("firstRunNameOver")
            }
            Text(model.nameHelp)
                .font(.callout)
                .foregroundStyle(DesignLock.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        TextField(text: Binding(get: { model.nameField }, set: { model.nameEdited($0) })) {
            Text(model.namePrompt)
        }
        .labelsHidden()
        .focused($isNameFocused)
        .onSubmit { model.continuePressed() }
        .accessibilityIdentifier("firstRunNameField")
    }
}

/// First run before a town exists (ux-flows S2 → S3): your name, then the town being
/// founded with it. A name already stored opens straight on S3.
///
/// It renders ``FirstRunViewModel`` and decides nothing. Placing it in the window, and
/// S7 in its place while the model is unavailable, is the owner's (#27).
public struct FirstRunView: View {
    @State private var model: FirstRunViewModel

    public var body: some View {
        // A container that exists in both states, so the identifier always has a home.
        VStack(spacing: 0) {
            if let founding = model.founding {
                FoundingView(model: founding)
            } else {
                NameEntryView(model: model)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("firstRunView")
    }

    /// Creates first run over `model`, which `App/` builds with the founder and the store,
    /// and a preview builds in a state.
    public init(model: FirstRunViewModel) {
        _model = State(initialValue: model)
    }
}

// MARK: - Previews

/// A model over a preview-only `UserDefaults` suite, emptied first, with `typed` in the
/// name field, so a preview never reads or writes the app's settings.
@MainActor
private func previewModel(_ name: String, typed: String) -> FirstRunViewModel? {
    let suiteName = "FirstRunViewPreview.\(name)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return nil
    }
    defaults.removePersistentDomain(forName: suiteName)
    let model = FirstRunViewModel(defaults: defaults) { displayName in
        FoundingViewModel(previewing: displayName, finished: [], isSlow: false, phase: .founding)
    }
    model.nameEdited(typed)
    return model
}

/// S2 over `model` at the minimum window size, or a note to the developer when the
/// preview suite could not be made.
@MainActor
@ViewBuilder
private func namePreview(_ model: FirstRunViewModel?) -> some View {
    if let model {
        FirstRunView(model: model)
            .frame(width: Layout.previewWidth, height: Layout.previewHeight)
    } else {
        Text(verbatim: "Preview: could not create a UserDefaults suite.")
    }
}

#Preview("S2, empty") {
    namePreview(previewModel("empty", typed: ""))
}

#Preview("S2, valid") {
    namePreview(previewModel("valid", typed: "Tomo"))
}

#Preview("S2, over the limit") {
    namePreview(previewModel("over", typed: "Bartholomew Fairweath"))
}

#Preview("S2, empty, dark") {
    namePreview(previewModel("emptyDark", typed: ""))
        .preferredColorScheme(.dark)
}

#Preview("S2, valid, dark") {
    namePreview(previewModel("validDark", typed: "Tomo"))
        .preferredColorScheme(.dark)
}

#Preview("S2, over the limit, dark") {
    namePreview(previewModel("overDark", typed: "Bartholomew Fairweath"))
        .preferredColorScheme(.dark)
}
