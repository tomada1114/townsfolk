import SwiftUI
import TownsfolkCore

/// Layout metrics for ``SettingsView``, drawn from the design lock.
private enum Layout {
    static let width = DesignLock.Window.settingsWidth
}

/// A helper line under a control: `.callout` in `SecondaryText`.
private struct HelperText: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(DesignLock.Palette.secondaryText)
    }
}

/// The Settings window's one pane, which the `Settings` scene in `App/` holds and ⌘,
/// opens (ux-flows S5): your name, speed, and keep-moving, in that order, each applied the
/// moment it changes.
///
/// It renders ``SettingsViewModel`` and decides nothing.
public struct SettingsView: View {
    @State private var model: SettingsViewModel
    @FocusState private var isNameFocused: Bool

    public var body: some View {
        Form {
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
        .onDisappear { model.paneClosed() }
        .accessibilityIdentifier("settingsPane")
    }

    private var nameField: some View {
        TextField(text: Binding(get: { model.nameField }, set: { model.nameEdited($0) })) {
            Text(model.nameTitle)
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
                Text(model.speedName(speed)).tag(speed)
            }
        } label: {
            Text(model.speedTitle)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("settingsSpeedPicker")
    }

    private var keepMovingToggle: some View {
        Toggle(isOn: Binding(
            get: { model.keepsMovingInOtherApps },
            set: { model.keepsMovingChanged($0) },
        )) {
            Text(model.keepsMovingTitle)
        }
        .accessibilityIdentifier("settingsKeepMovingToggle")
    }

    /// Shares the app root explicitly with the Settings scene.
    public init(model: AppModel) {
        _model = State(initialValue: model.settings)
    }

    /// Creates the pane over `model`; a preview hands in a model already in a state; the app uses
    /// the root-model initializer.
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

#Preview("Default, dark") {
    pane(previewModel("dark"))
        .preferredColorScheme(.dark)
}

#Preview("Name error, dark") {
    pane(previewModel("nameErrorDark") { $0.nameSubmitted("Tomoyuki the Wandering Baker") })
        .preferredColorScheme(.dark)
}
