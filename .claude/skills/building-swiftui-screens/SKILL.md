---
name: building-swiftui-screens
description: >
  Covers writing a SwiftUI view in MyAppUI as a thin renderer over a MyAppCore
  @Observable view model: how the view receives and holds its model (@State, a plain
  property, @Bindable, a Binding built from an action), what logic may and may not sit
  in body, #Preview per state, accessibility identifiers for LaunchUITests,
  accessibility labels, Reduce Motion, keyboard reachability, and how a screen is
  verified. Use when adding or changing a view, a subview, or a preview under
  Packages/MyAppKit/Sources/MyAppUI, wiring a view to a view model in App/, adding an
  accessibilityIdentifier, or fixing an accessibility_label_for_image or
  no_magic_numbers violation in a view.
---

# Building SwiftUI Screens

**Owns:** how a view in `MyAppUI` is written — how it gets its view model, what it may
contain, its previews, and its accessibility wiring. **Does not own:** the view model's
shape, state, and actions (`designing-core-logic`); what the screen looks like — color,
type, spacing, the design lock (`designing-ui`); an OS integration behind a port
(`integrating-system-apis`); the app's scenes and shape (`starting-an-app`); launching
the app and the evidence a pull request carries (`running-the-app`).

## The rule, and why

A view renders Core state and forwards user intent to a Core action; it decides nothing.
`MyAppUI` is outside the coverage floor — `scripts/coverage.sh` measures `MyAppCore`
only, because SwiftUI layout is not what `swift test` can assert — so any branch that
lives in a view is a branch no gate tests.
Keeping it in the view model is what makes the 80% floor on `MyAppCore` honest
(`docs/architecture.md` › "Where new code goes"). `ContentView` over `CounterViewModel`
and `FrontmostAppViewModel` is the worked example; copy its shape.

- A view is a `struct` in `MyAppUI` importing `SwiftUI` and `MyAppCore`, and never
  `MyAppPlatform`. Enforced by: `ArchitectureBoundaryTests`' sibling-import tests.
- It is `public` only when `App/` constructs it; a subview used inside `MyAppUI` stays
  internal.

## Getting the view model

- **The view that owns the model** holds it in `@State private var model`, set in its
  initializer with `_model = State(initialValue: model)`, and takes the model as an
  initializer parameter so previews and `App/` can inject a state:
  `init(model: CounterViewModel = CounterViewModel())`. A default argument is only for a
  model that needs no port.
- **A model that needs a port** cannot be built in `MyAppUI`: its adapter lives in
  `MyAppPlatform`, which this module must not import. `App/`, the composition root,
  builds it and passes it down — `ContentView`'s optional
  `frontmostApp: FrontmostAppViewModel?`, which previews simply leave out.
- **A subview that only reads** takes the model as a plain `let` property. With
  `@Observable`, SwiftUI re-renders a view when a property its `body` read changes, with
  no property wrapper needed.
- **A control that needs a `Binding`** (a `TextField`, a `Toggle`) cannot bind straight
  to the model: state is `public private(set)` and changes only through actions
  (`designing-core-logic` › "Action-shaped view models"). Build the binding from the
  action — `Binding(get: { model.query }, set: { model.queryChanged(to: $0) })`.
  `@Bindable` cannot reach a `private(set)` property, and widening the setter to let it
  would bypass the action.
- Not used here: `ObservableObject`, `@StateObject`, `@ObservedObject`,
  `@EnvironmentObject`. Initializer parameters, not the environment, carry a model:
  `App/` wires everything explicitly (`designing-core-logic` › "Deliberately not
  adopted").

## What `body` may contain

| Belongs in the view | Belongs in the Core view model |
|---|---|
| Layout, modifiers, and the order things appear in | Whether an action is allowed now (`canIncrement`) |
| `if let` on an optional model or value, to show or omit a part | Any rule, clamp, threshold, or comparison on domain values |
| Calling an action from a `Button`, `.onSubmit`, a menu command | What the action does, and the state it leaves behind |
| *When* to ask again — `.onChange(of: scenePhase)`, `.task` — as `ContentView` refreshes `frontmostApp` on activation | *What* asking again means (`refresh()`) |
| `Text(verbatim:)` for a glyph or an already-formatted number | Every word a person reads, as a `LocalizedStringResource` (`resetTitle`, `label`) — `localizing-the-app` |
| `.disabled(!model.canDecrement)` | Formatting numbers and dates with an injected `Locale` |

- An action that waits is `async`; call it from `.task { await model.load() }` so
  SwiftUI cancels it with the view, or from a `Task { }` inside a button's closure.
- Numbers a view needs — spacing, sizes, minimum window dimensions — go in a
  `private enum Layout` in the view's file, drawn from the design lock's scale
  (`designing-ui`). Enforced by: `.swiftlint.yml`'s `opt_in_rules: all`, which turns on
  `no_magic_numbers`.
- When `body` grows toward SwiftLint's `function_body_length` limit, extract a
  subview `struct` with its own inputs instead of a long computed `some View` property;
  the struct can take exactly the slice of state it renders and has its own preview.

## Previews

- One `#Preview("Name")` per state worth seeing — the default and each boundary or empty
  state — built by injecting a Core view model already in that state, as
  `ContentView`'s "At the upper bound" does. A preview that has to reach a state by
  calling actions is a sign the model wants an initializer that takes that state.
- No `try!` or force unwrap in a preview either (`.claude/rules/swift.md` › Error
  Handling): unwrap with `if let` and render a `Text` explaining the failure, as
  `ContentView`'s second preview does.
- Previews never construct a `MyAppPlatform` adapter; a port-backed model is left out.
  A state reachable only through a port is covered by a Core test with the port's fake
  and seen in the running app.
- A screen with any custom color gets a dark-appearance preview
  (`.preferredColorScheme(.dark)`) beside the light one.
- Previews are not a gate: they compile with the module, so one that stops compiling
  fails `just build`, but nothing checks what they render. Look.

## Accessibility

- **Identifiers are a test contract.** Every control and value `LaunchUITests` or a
  throwaway XCUITest reads carries `.accessibilityIdentifier("camelCaseName")` — stable,
  never localized, never shown to a person. Renaming one breaks `just uitest`, so rename
  the test in the same change (`LaunchTests` reads `counterValue` and clicks
  `incrementButton`).
- **Labels are what VoiceOver says**, and an identifier is not one. Give every control a
  text label from a Core `LocalizedStringResource` (`localizing-the-app`):
  `Button(model.addTitle, systemImage: "plus")` or `Label` rather than a bare `Image`,
  and `.accessibilityLabel(model.decrementLabel)` where the visible text is a glyph or a
  number without context. A decorative image is `Image(decorative:)` or `.accessibilityHidden(true)`.
  Enforced by: `accessibility_label_for_image` (a labelless image) and
  `accessibility_trait_for_button` (an `.onTapGesture` without `.isButton`), both on
  through `opt_in_rules: all`. Neither sees a glyph-only text button — review does.
- **Group** a value and its caption into one element with
  `.accessibilityElement(children: .combine)` when they are read together.
- **Motion:** an animation checks `@Environment(\.accessibilityReduceMotion)` and falls
  back to no animation or a cross-fade; nothing is communicated by motion alone
  (`designing-ui`).
- **Keyboard:** every action is reachable without a pointer — a standard control, a menu
  command with its `.keyboardShortcut` in `App/`'s `Commands`, and a default button
  (`.keyboardShortcut(.defaultAction)`) where a sheet has one.
- **Check it by hand**, because no gate does: Accessibility Inspector (Xcode › Open
  Developer Tool) on the running app, and a pass with VoiceOver on. Say in the pull
  request what was checked.

## Verifying a screen

1. `just test` — the view model's behavior, which is where the logic is.
2. `just build` — the view and its previews compile, under SwiftLint's view rules via
   `just lint`.
3. `just uitest` — when an identifier the launch test reads, or the first screen,
   changed.
4. `just run`, then a screenshot per `running-the-app` in both appearances and at the
   minimum window size — the pull request's evidence of what the view shows.

## Sources

All checked 2026-09-28.

- <https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro>
  — SwiftUI tracks the observable properties `body` reads, without a property wrapper;
  `@Bindable` for bindings.
- <https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier(_:)> —
  an identifier is for testing and not visible to the user.
- <https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion>
  — the Reduce Motion environment value.
- <https://developer.apple.com/documentation/swiftui/previews-in-xcode> — `#Preview`.
- <https://developer.apple.com/design/human-interface-guidelines/accessibility> —
  labels, Full Keyboard Access, not relying on a single cue.
