---
name: designing-ui
description: >
  Covers how this macOS app looks and feels: craft rules grounded in Apple's Human
  Interface Guidelines (system text styles, semantic and accent colors, light and dark
  appearance, contrast, SF Symbols, window sizing, the menu bar and keyboard shortcuts,
  motion) and the per-app design lock, recorded as an ADR under docs/architecture/, that
  fixes the accent color, type, spacing, density, iconography, and copy style every
  screen obeys. Use when choosing a color, font, spacing value, icon, or window size,
  touching AccentColor.colorset or AppIcon.appiconset, adding a menu command, reviewing
  a screen's visual design, or writing or amending the app's design-lock ADR.
---

# Designing UI

**Owns:** what a screen in this app looks like and how it behaves to the eye and hand —
the craft rules below, and the app's design lock: the short set of visual decisions
every screen obeys, and where they are recorded. **Does not own:** how a view is written
in SwiftUI, its previews, and its accessibility wiring (`building-swiftui-screens`); the
app shape, windowed or menu-bar agent (`starting-an-app`); an ADR's shape, numbering,
and statuses (`recording-architecture-decisions`); where user-visible wording lives —
a Core view model and its String Catalog (`localizing-the-app`).

Apple's Human Interface Guidelines (HIG) are the baseline and are not restated here: this
skill keeps only what this repository decides on top of them, and links the HIG page for
the rest. Every HIG claim below was checked against the page listed under Sources.

## System first, custom by exception

A Mac app earns trust by behaving like the other apps on the Mac. The default answer to
every visual question is the system's, and a departure is a design-lock decision, not a
per-screen one.

- **Type:** use the built-in text styles (`.font(.body)`, `.headline`, `.title`,
  `.footnote`) with the system font. macOS has no Dynamic Type, but system fonts still
  respond to the system's accessibility features; a custom font must be made to do the
  same, and it ships as a bundled resource with a license to check. A size given in
  points is a deliberate display exception, named in the
  view's private `Layout` enum, never a body-text choice.
- **Color:** use semantic colors — `.primary`, `.secondary`, `Color.accentColor`, the
  dynamic system colors — for their stated purpose. Never hard-code a system color's
  value, and never repurpose one (a separator color as text). A custom color is a Color
  Set in `App/Assets.xcassets` with both an Any and a Dark appearance variant; a literal
  RGB value in a view is a review finding.
- **Accent:** `App/Assets.xcassets/AccentColor.colorset` is the one place the app's
  accent is set (`project.yml`'s `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`), and
  the template ships it with no color value. On macOS the app's accent shows only while
  the person's Accent color setting is multicolor; any other choice replaces it. So the
  accent may carry brand, never meaning: nothing may depend on the accent being a
  particular hue.
- **Symbols:** SF Symbols through `Image(systemName:)` or `Label`, before a custom image.
  One rendering mode per context, chosen in the lock, and checked for legibility at the
  size it is drawn.
- **Controls:** standard SwiftUI controls with their default styles. A custom control
  owes the same keyboard, focus, and accessibility behavior the standard one gives free
  (`building-swiftui-screens`), which is why it is rare.

## Appearance and contrast

- Every screen works in light and dark. A color that only reads in one appearance fails
  review even if nobody on the team uses the other.
- Text contrast is at least 4.5:1 against its background, and 7:1 is the target for
  small text on a custom background; system colors meet this on their own and adapt to
  Increase Contrast.
- Never convey state by color alone: pair it with a shape, a symbol, or text. A red
  border without a message or icon is not an error state.
- Motion is optional decoration: nothing a person needs to know is shown only by
  animation, and an animation respects Reduce Motion (`building-swiftui-screens` wires
  it). Prefer the system's own transitions; the lock says whether custom ones are
  allowed at all.

## Windows and layout

- A window sets a minimum size its content survives — `RootView`'s
  `.frame(minWidth:minHeight:)` from its `Layout` enum, which reads `DesignLock.Window` — and the layout adapts from there
  up. Nothing overlaps or clips at the minimum; nothing stretches into an unreadable
  line length at full screen (cap a text column's width instead).
- Align to a small spacing scale fixed in the lock, and let alignment and indentation
  carry hierarchy before color or weight does.
- A menu-bar agent's popover or panel follows the same rules at a fixed size; the shape
  itself is `starting-an-app`'s decision.

## Menus, keyboard, and settings

- Every command the app offers is also in the menu bar, where people look for it, can
  learn its shortcut, and reach it with Full Keyboard Access — even when a button on
  screen does the same thing. In SwiftUI that is a `Commands` group on the scene in
  `App/`, calling the same Core view-model action the button calls.
- Standard menu items keep their standard shortcuts (⌘C, ⌘S, ⌘,); a custom shortcut is
  added only for the most frequent app-specific commands, prefers ⌘ as its modifier,
  and never repurposes a standard one.
- A menu item that cannot act right now is disabled, not hidden.
- Preferences live in SwiftUI's `Settings` scene, which gives the ⌘, item and the
  standard window (`docs/architecture.md`'s "Settings window" paragraph).

## Copy

- Pick one capitalization per element type — title case or sentence case — record it in
  the lock, and apply it everywhere. A menu title of more than one word uses title case.
- Button and menu labels start with a verb naming what happens ("Reset", "Export…");
  a menu item that needs more input before it can complete ends in an ellipsis (…).

## The design lock

The design lock is the app's answer to "what does every screen here look like?" — a
handful of decisions made once so that each new screen is built against them instead of
reinvented. It is small on purpose: accent color, type scale, spacing scale, density,
corner radius, symbol rendering, window sizing, motion policy, and copy style, each either
a value or an explicit "system default".

- **It is an ADR.** Later screens build on it, which is the test
  `recording-architecture-decisions` applies. Write it as that skill says, with the next
  free number in `docs/architecture/adr/` — do not assume one; `starting-an-app`'s first
  decisions may already hold the low numbers — status Proposed, and a row in
  `docs/architecture/README.md`. Only the owner accepts it. Until then screens may be
  built against it only as an experiment.
- **When:** after the app shape is decided (a menu-bar agent's lock differs from a
  windowed app's) and before the second screen. The first screen can be the probe that
  surfaces what the lock needs to say.
- **What it holds and how to fill it:** [references/design-lock.md](references/design-lock.md)
  — the fields, what "decided" looks like for each, and where each value lands in code.
- **Changing it:** a corrected value in an Accepted lock is an amendment; changing the
  direction (a new accent, a denser layout, custom type) is a new ADR that supersedes it.
  Screens already built are then brought into line in their own change.
- **In the template itself** there is no lock: the template ships no ADRs and its UI is
  the system default. A change to the template's own visual defaults updates README's
  Design Philosophy (`updating-docs`) instead.

## Reviewing a screen's design

Before calling a screen done, look at it — `just run` and a screenshot per
`running-the-app` — in both appearances and at the window's minimum size, with Increase
Contrast and Reduce Motion on, and compare it against the lock. No gate sees any of
this: `just build` proves it compiles, and the screenshots in the pull request are the
evidence.

## Sources

All checked 2026-09-28.

- <https://developer.apple.com/design/human-interface-guidelines/typography> — built-in
  text styles; macOS has no Dynamic Type; custom fonts must honor accessibility settings.
- <https://developer.apple.com/design/human-interface-guidelines/color> — semantic
  dynamic colors, no hard-coded system values, the macOS app accent vs. the multicolor
  setting, not relying on color alone.
- <https://developer.apple.com/design/human-interface-guidelines/dark-mode> — adaptive
  colors, Color Set variants, 4.5:1 minimum and 7:1 for small text.
- <https://developer.apple.com/design/human-interface-guidelines/accessibility> —
  Increase Contrast, color-independent cues, Full Keyboard Access.
- <https://developer.apple.com/design/human-interface-guidelines/sf-symbols> — rendering
  modes and legibility.
- <https://developer.apple.com/design/human-interface-guidelines/motion> — motion as
  optional, never the only signal.
- <https://developer.apple.com/design/human-interface-guidelines/windows> — minimum and
  maximum window sizes.
- <https://developer.apple.com/design/human-interface-guidelines/layout> — alignment,
  indentation, adaptive layout.
- <https://developer.apple.com/design/human-interface-guidelines/the-menu-bar> — every
  command in the menu bar, standard shortcuts, disable rather than hide, title case.
- <https://developer.apple.com/design/human-interface-guidelines/writing> — one
  capitalization style per element type.
- <https://developer.apple.com/design/human-interface-guidelines/menus> — verb labels,
  the ellipsis for an item that needs more input.
- <https://developer.apple.com/design/human-interface-guidelines/keyboards> — respect
  standard shortcuts; custom ones only for the most frequent commands, ⌘ first.
- <https://developer.apple.com/design/human-interface-guidelines/buttons> — a text label
  that starts with a verb.
