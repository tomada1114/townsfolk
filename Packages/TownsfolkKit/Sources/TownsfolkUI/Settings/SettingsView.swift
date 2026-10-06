import SwiftUI
import TownsfolkCore

/// Layout metrics for ``SettingsView``, drawn from the design lock.
private enum Layout {
    static let width = DesignLock.Window.settingsWidth
}

/// A helper line under a control: `.callout` in `SecondaryText` (ADR-0008 › Type).
private struct HelperText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.callout)
            .foregroundStyle(DesignLock.Palette.secondaryText)
    }
}

/// The Settings window's one pane, which the `Settings` scene in `App/` holds and ⌘,
/// opens (ux-flows S5): language, your name, speed, and keep-moving, in that order, each
/// applied the moment it changes.
///
/// It renders ``SettingsViewModel`` and decides nothing. Every string arrives resolved in
/// the app's language and is drawn with `Text(verbatim:)`, never `Text(resource)`, which
/// would ignore the language the app is set to (ADR-0007 › Amended 2026-10-06).
public struct SettingsView: View {
    @State private var model: SettingsViewModel
    @FocusState private var isNameFocused: Bool

    public var body: some View {
        Form {
            Section {
                languagePicker
                HelperText(text: model.languageHelp)
            }
            Section {
                nameField
                if let error = model.nameError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("settingsNameError")
                }
            }
            Section {
                speedPicker
                HelperText(text: model.speedHint)
                    .accessibilityIdentifier("settingsSpeedHint")
            }
            Section {
                keepMovingToggle
                HelperText(text: model.keepsMovingHelp)
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.width)
        .accessibilityIdentifier("settingsPane")
    }

    private var languagePicker: some View {
        Picker(selection: Binding(get: { model.language }, set: { model.languageChosen($0) })) {
            ForEach(SettingsViewModel.languageChoices, id: \.self) { language in
                // Each language's own name, the same in every app language.
                Text(verbatim: language.nativeName).tag(language)
            }
        } label: {
            Text(verbatim: model.languageTitle)
        }
        .accessibilityIdentifier("settingsLanguagePicker")
    }

    private var nameField: some View {
        TextField(text: Binding(get: { model.nameField }, set: { model.nameEdited($0) })) {
            Text(verbatim: model.nameTitle)
        }
        .focused($isNameFocused)
        .onSubmit { model.nameSubmitted(model.nameField) }
        .onChange(of: isNameFocused) { _, isFocused in
            // Leaving the field submits it, as Return does (ux-guidelines › Forms).
            if !isFocused {
                model.nameSubmitted(model.nameField)
            }
        }
        .accessibilityIdentifier("settingsNameField")
    }

    private var speedPicker: some View {
        Picker(selection: Binding(get: { model.speed }, set: { model.speedChosen($0) })) {
            ForEach(SettingsViewModel.speedChoices, id: \.self) { speed in
                Text(verbatim: model.speedName(speed)).tag(speed)
            }
        } label: {
            Text(verbatim: model.speedTitle)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("settingsSpeedPicker")
    }

    private var keepMovingToggle: some View {
        Toggle(isOn: Binding(
            get: { model.keepsMovingInOtherApps },
            set: { model.keepsMovingChanged($0) },
        )) {
            Text(verbatim: model.keepsMovingTitle)
        }
        .accessibilityIdentifier("settingsKeepMovingToggle")
    }

    /// Creates the pane over `model`; `App/` takes the default, which reads
    /// `UserDefaults.standard`, and a preview hands in a model already in a state.
    public init(model: SettingsViewModel = SettingsViewModel()) {
        _model = State(initialValue: model)
    }
}

// MARK: - Previews

/// A model over a preview-only `UserDefaults` suite, emptied first and then put in a
/// state through its own actions, so a preview never reads or writes the app's settings.
@MainActor
private func previewModel(
    _ name: String,
    _ configure: ((SettingsViewModel) -> Void)? = nil,
) -> SettingsViewModel? {
    let suiteName = "SettingsViewPreview.\(name)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return nil
    }
    defaults.removePersistentDomain(forName: suiteName)
    let model = SettingsViewModel(defaults: defaults)
    model.nameSubmitted("Tomo")
    configure?(model)
    return model
}

/// The pane over `model`, or a note to the developer when the preview suite could not
/// be made.
@MainActor
@ViewBuilder
private func pane(_ model: SettingsViewModel?) -> some View {
    if let model {
        SettingsView(model: model)
    } else {
        Text(verbatim: "Preview: could not create a UserDefaults suite.")
    }
}

#Preview("Default") {
    pane(previewModel("default"))
}

#Preview("Slow") {
    pane(previewModel("slow") { $0.speedChosen(.slow) })
}

#Preview("Fast") {
    pane(previewModel("fast") { $0.speedChosen(.fast) })
}

#Preview("Name error") {
    pane(previewModel("nameError") { $0.nameSubmitted("Tomoyuki the Wandering Baker") })
}

#Preview("Keep moving off") {
    pane(previewModel("keepMovingOff") { $0.keepsMovingChanged(false) })
}

#Preview("Japanese") {
    pane(previewModel("japanese") { $0.languageChosen(.japanese) })
}

#Preview("Default, dark") {
    pane(previewModel("dark"))
        .preferredColorScheme(.dark)
}

#Preview("Name error, dark") {
    pane(previewModel("nameErrorDark") { $0.nameSubmitted("Tomoyuki the Wandering Baker") })
        .preferredColorScheme(.dark)
}
