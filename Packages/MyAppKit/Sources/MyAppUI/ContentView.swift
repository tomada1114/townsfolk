import MyAppCore
import SwiftUI

/// Layout metrics for ``ContentView``.
private enum Layout {
    static let stackSpacing: CGFloat = 16
    static let valueFontSize: CGFloat = 48
    static let windowPadding: CGFloat = 32
    static let minWindowWidth: CGFloat = 320
    static let minWindowHeight: CGFloat = 240
}

/// The app's single screen: a bounded counter with increment/decrement/reset.
///
/// Deliberately thin — every behavior it renders is owned and unit-tested by
/// `CounterViewModel` in MyAppCore, and so is every word: the view has no localizable
/// literal of its own. A `Text("…")` literal here would be looked up in the app's main
/// bundle, not the package's catalog; the value and the "−" and "+" glyphs are
/// verbatim instead.
public struct ContentView: View {
    @State private var model: CounterViewModel
    /// Present only when the app shell handed one down — the view has no way to build a
    /// ``FrontmostAppViewModel``, because the port's adapter lives in `MyAppPlatform`,
    /// which `MyAppUI` must not import. Previews and tests simply leave it out.
    @State private var frontmostApp: FrontmostAppViewModel?
    @Environment(\.scenePhase)
    private var scenePhase

    public var body: some View {
        VStack(spacing: Layout.stackSpacing) {
            Text(verbatim: String(model.value))
                .font(.system(size: Layout.valueFontSize, weight: .bold, design: .rounded))
                .accessibilityIdentifier("counterValue")
            HStack {
                Button { model.decrement() } label: { Text(verbatim: "−") }
                    .disabled(!model.canDecrement)
                    // The glyph is not a name: VoiceOver reads the label instead.
                    .accessibilityLabel(CounterViewModel.decrementLabel)
                    .accessibilityIdentifier("decrementButton")
                Button(CounterViewModel.resetTitle) { model.reset() }
                    .accessibilityIdentifier("resetButton")
                Button { model.increment() } label: { Text(verbatim: "+") }
                    .disabled(!model.canIncrement)
                    .accessibilityLabel(CounterViewModel.incrementLabel)
                    .accessibilityIdentifier("incrementButton")
            }
            if let frontmostApp {
                Text(frontmostApp.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("frontmostAppLabel")
            }
        }
        .padding(Layout.windowPadding)
        .frame(minWidth: Layout.minWindowWidth, minHeight: Layout.minWindowHeight)
        // The port answers with a snapshot, so the snapshot is retaken every time this
        // scene becomes active — reading it once at launch would pin the label to
        // whoever launched the app. `initial: true` covers the case where the scene is
        // already active on first render.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else {
                return
            }
            frontmostApp?.refresh()
        }
    }

    /// Creates the view over `model` — previews and tests inject alternate
    /// states; the app shell uses the default.
    ///
    /// `frontmostApp` is the worked example of a Core view model over an OS port: the
    /// app shell builds it with a `MyAppPlatform` adapter and hands it down, so this
    /// view renders the answer without knowing where it came from.
    public init(
        model: CounterViewModel = CounterViewModel(),
        frontmostApp: FrontmostAppViewModel? = nil,
    ) {
        _model = State(initialValue: model)
        _frontmostApp = State(initialValue: frontmostApp)
    }
}

#Preview("Default") {
    ContentView()
}

#Preview("At the upper bound") {
    if let counter = try? Counter(value: 100) {
        ContentView(model: CounterViewModel(counter: counter))
    } else {
        // A developer's note in a preview, never shown in the app: verbatim, so it stays
        // out of the String Catalog a translator works from.
        Text(verbatim: "Counter(value: 100) is out of bounds — check Counter's invariants")
    }
}
