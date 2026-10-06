# The design lock: fields and where they land

The design lock is one table of values, recorded in this app in
`docs/design/design-direction.md` › Design lock and mirrored in `TownsfolkUI`'s
`DesignLock` (see the `designing-ui` skill for when it is written and how it changes).
This file lists the fields that table fixes; the alternatives weighed for each go in that
document's decision ledger.

Every field is either a value or the words "system default". "System default" is a real
decision — often the right one for a first version — and saying it explicitly stops the
next implementer from inventing a value. A field left out is a gap, not a default: list
it under that document's open items until it is decided.

## Fields

| Field | What "decided" looks like | Where it lands in code |
|---|---|---|
| Accent color | "System default", or one color with its Any and Dark variants given as sRGB values, and what it is used for (prominent buttons, selection) | `App/Assets.xcassets/AccentColor.colorset` |
| Custom colors | Each named color, its purpose, and its Any and Dark variants — or "none; semantic system colors only" | One Color Set each in `Packages/TownsfolkKit/Sources/TownsfolkUI/Resources/Colors.xcassets`, read with `Color(_:bundle: .module)` so a `#Preview` resolves it |
| Type | The text styles the app uses and for what (`.title` for a window's heading, `.body` for content, `.footnote` for secondary facts); any fixed-size display style and why; a custom font and its license, or "system font only" | `.font(...)` at the call site; a fixed display size in the view's `Layout` enum |
| Spacing scale | A short list of spacing values (for example 4, 8, 16, 32 points) and which one separates what — control from control, group from group, content from window edge | Each view's private `Layout` enum draws only from this scale |
| Density | Regular or compact; `.controlSize` and list row style if not the default | A modifier on the scene's root view, so every screen inherits it |
| Corner radius | "System default", or the values for cards and containers | `Layout` enum, from the scale |
| Symbols | SF Symbols only, or where custom images are allowed; the rendering mode (monochrome, hierarchical, palette, multicolor) per context | `Image(systemName:)`, `Label`, `.symbolRenderingMode(...)` |
| Materials | Where a material or vibrancy is used (a sidebar, a popover) and where it is not | `.background(.regularMaterial)` and friends, at the named places only |
| Window sizing | The main window's minimum size, and default size if not the minimum; a panel's fixed size for a menu-bar agent | The root view's `.frame(minWidth:minHeight:)`; `.defaultSize(...)` on the scene in `App/` |
| Motion | "System transitions only", or which custom animations exist and what each communicates; behavior under Reduce Motion | `withAnimation` / `.animation` at the call site, gated on `accessibilityReduceMotion` |
| Copy style | Title case or sentence case per element type (buttons, menu items, window titles, labels, alerts); the app's voice in one sentence | The English values in `Localizable.xcstrings`, returned by Core view models (`localizing-the-app`) |
| App icon | Who supplies it and in which format, or "placeholder until distribution" | `App/Assets.xcassets/AppIcon.appiconset` |

## Sharing values between views

The template keeps each view's metrics in a `private enum Layout` beside the view
(`RootView`, `SettingsView`), because `no_magic_numbers` — on through `.swiftlint.yml`'s
`opt_in_rules: all` — rejects a bare number in a view body. That stays the rule while
only one view uses a value. Once a second view needs the same spacing or radius, move
the lock's values into one internal type in `TownsfolkUI` — here it is `DesignLock` —
and have each `Layout` enum refer to it. They never go in `TownsfolkCore`: they are presentation, and Core
does not import SwiftUI.

## A design lock, sketched

```markdown
## Design lock

- Accent color: system default. Nothing in the app depends on its hue.
- Custom colors: none; semantic system colors only.
- Type: system font; `.title2` for a window heading, `.body` for content, `.footnote`
  for secondary facts. One fixed display size (48 pt, rounded, bold) for the main value.
- Spacing scale: 4, 8, 16, 32 pt. 8 between related controls, 16 between groups, 32
  from content to the window edge.
- Density: regular.
- Symbols: SF Symbols only, hierarchical rendering in toolbars.
- Window sizing: minimum 320 × 240 pt; opens at the minimum.
- Motion: system transitions only; none added.
- Copy style: title case for buttons, menu items, and window titles; sentence case for
  labels and alerts.
- App icon: placeholder until distribution is decided.
```

Keep the sketch's level of detail: values and one reason each, not a style guide. The
reasoning that beat the alternatives belongs in the decision ledger, and anything the
owner has not settled goes under the open items, never filled in from habit.

## What does not belong in the lock

- The app shape and the scenes it has — `starting-an-app`, recorded in
  `docs/architecture.md`.
- A single screen's layout — that is the screen's own pull request, built against the
  lock.
- Anything the HIG already fixes for every Mac app (standard shortcuts, the menu order);
  the lock records only this app's choices on top of it.
