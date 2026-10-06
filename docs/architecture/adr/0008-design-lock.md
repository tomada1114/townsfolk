# ADR-0008: Design lock — one lamp in a quiet street

- **Status:** Accepted 2026-09-30
- **Amended:** 2026-09-30 — Open question settled: `Color("SecondaryText")` does not
  resolve in a `TownsfolkUI` `#Preview`. A named color is looked up in the main bundle's
  asset catalog; the preview host, Xcode's `XCPreviewAgent.app`, ships none, and outside
  `Townsfolk.app` both Color Sets resolve to clear with SwiftUI's "No color named
  'SecondaryText' found in asset catalog for main bundle". The Color Sets stay in
  `App/Assets.xcassets`, where the running app resolves them; moving them to a
  `TownsfolkUI` resource catalog, which changes `Package.swift`, is proposed as a
  follow-up (#7).
- **Amended:** 2026-10-06 — The follow-up landed (#37): both Color Sets moved to
  `Packages/TownsfolkKit/Sources/TownsfolkUI/Resources/Colors.xcassets`, the
  `TownsfolkUI` target gained `resources: [.process("Resources")]`, and `DesignLock`
  reads them with `Color(_:bundle: .module)`, so they resolve in a `#Preview` as well as
  in the app. The owner signed off on the `Package.swift` change on 2026-10-06; it adds
  no dependency.
- **Amended:** 2026-10-06 — Open question settled (#10): each event kind's symbol, the
  same in `en.json` and `ja.json` — `weather-turns` `cloud.sun.rain`, `shop-opens`
  `storefront`, `festival` `party.popper`, `lost-pet` `pawprint`, `road-works` `cone`,
  `visitor` `suitcase.rolling`, `power-cut` `bolt.slash`, `market-day` `basket`,
  `snowfall` `snowflake`, `thick-fog` `cloud.fog`, `concert` `music.note`, `fireworks`
  `fireworks`, `sports-day` `figure.run`, `book-fair` `books.vertical` — and the fixed
  kinds `move-in` `house`, `move-out` `figure.walk`, and `founding` `house`, chosen for
  the "You moved to {town}." row. Every name was checked on macOS 27.0 with a throwaway,
  uncommitted Swift script calling `NSImage(systemSymbolName:accessibilityDescription:)`
  for each of the 16 distinct names: all were found, and a made-up name was not. They
  were not opened in the SF Symbols app; how each reads beside an event row is seen once
  the timeline shows one.
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

Every screen needs the same answers to color, type, spacing, density, symbols, motion,
and copy before the second screen is built (`designing-ui` › The design lock). The
kickoff researched them, and the owner approved the result on 2026-09-30:
[`docs/design/design-direction.md`](../../design/design-direction.md) holds the research,
the reference lock, the decision ledger, and the measured contrast. This ADR fixes its
values as the lock, and the research stays there. The UX policy the lock serves is
[`docs/design/ux-guidelines.md`](../../design/ux-guidelines.md) — glance first, nothing
hurries you, one expressive moment when a post arrives, WCAG 2.2 AA with the system focus
ring — and the window's shape is ADR-0001.

## Decision drivers

- A glance from across the desk shows that the town moved.
- System first, custom by exception (`designing-ui`).
- WCAG 2.2 AA for every text pair, in light and dark and with Increase Contrast.
- Nothing hurries you: one expressive moment and no chrome.

## Considered options

1. **A quiet monochrome feed with one warm light** — primary reference Threads; the
   lantern borrowed from Paste; readable metadata from Bluesky.
2. **A small-town newspaper** — cream paper, serif headlines, terracotta and sage, the
   look the neighborhood and cozy-game references pulled toward. It is the
   calm-editorial average, and a fiction of print the app does not need.
3. **Social-feed defaults** — post cards, avatars or initial circles, a brand accent in
   controls. Cards spend a 380 pt window's width, avatars stand in for a Later feature,
   and an amber control would put the brand into buttons.

## Decision

- **Accent color:** system default; `AccentColor.colorset` keeps no value. It appears
  only where system controls put it (the default button, text selection, Settings'
  controls, the focus ring); no custom view uses it, and nothing depends on its hue.
- **Custom colors:** two Color Sets in `TownsfolkUI`'s `Resources/Colors.xcassets`.
  - `SecondaryText` — Any #666666, Dark #A3A3A3, Any High Contrast #4D4D4D, Dark High
    Contrast #C2C2C2. Metadata text and the symbols beside it: post times, "(you)", quote
    lines, event rows, labeled dividers, the resting line, the replying chip, the counter
    and helper text, the composer's placeholder, the profile's details, a past resident's
    name. Never post text, never a fill.
  - `Lamplight` — Any #FFEED6, Dark #3D3221, the High Contrast variants the same.
    Decoration only: the wash behind a newly arrived post, and the app icon's lit window.
    Never text, a symbol, a control, a border, a selection, a lasting surface, or the only
    sign of anything.
  - Everything else is a semantic system color. A problem is shown in the primary label
    color with `exclamationmark.triangle`, never in red.
- **Type:** the system font and its text styles only. `.body` for post text (2 pt extra
  line spacing), the composer, first-run and founding text, and Settings; `.headline`
  for resident names in post headers and the profile's full name; post times in `.body`
  `SecondaryText` after the name; `.callout` for the status line, quote lines, event
  rows, labeled dividers, the replying chip, the counter, helper text, and the profile's
  details; `.title3` for the heading of a full-window state (S2, S3, S7). Nothing larger,
  and nothing below 12 pt.
- **Spacing scale:** 4, 8, 12, 16, 32 pt. 4 between a post's header and its text; 8
  between the posts of a group, between a quote line and its first post, and between the
  status line and the composer; 12 on each side of the hairline between groups and event
  rows; 16 from the window edge to the content, and as the gutter; 32 as the margin of a
  full-window state and between its blocks. The profile popover pads 16 and separates its
  rows by 8; Settings keeps the system form's spacing.
- **Timeline metrics:** the text column, gutter included, is capped at 560 pt and
  centered. The thread line (2 pt, round caps, from a group's first header to its last
  line), a quote line's symbol, and an event row's symbol hang in the 16 pt gutter left
  of one shared text edge. The hover Reply is a 28 × 28 pt borderless button at the
  trailing end of the post's header. The Lamplight wash is a square-cornered band across
  the window's full width.
- **Density:** regular controls (the default `.controlSize(.regular)`). Posts take no fill
  on hover or selection; the selected post is shown by the system focus ring alone.
- **Corner radius:** system default; no custom containers.
- **Symbols:** SF Symbols only, monochrome, at the style and color of the text beside
  them. Resting `moon.zzz`; quote line and Reply `arrowshape.turn.up.left`; the new-posts
  pill `arrow.up`; a founding step done `checkmark`, pending `circle.dotted`; a problem
  `exclamationmark.triangle`; cancelling a reply `xmark`; moving in `house`, moving away
  `figure.walk`. Every event kind in the seed tables names its own symbol (ADR-0007).
- **Materials:** only the new-posts pill (`.buttonStyle(.glass)`), plus what the system
  draws for the title bar, popovers, alerts, and the Settings window. The timeline,
  status line, composer, and banner sit on the opaque canvas.
- **Window sizing:** the main window opens at 380 × 680 pt with a minimum of 320 × 440 pt
  (ADR-0001); the profile popover is 280 pt wide; Settings is one pane, 480 pt wide.
- **Motion:** exactly these custom animations, opacity only: a new post fades in over
  200 ms (ease-out) while its Lamplight wash fades out over 3 s (ease-in); the status line
  crossfades over 200 ms; the pill fades over 150 ms, and its scroll to the top takes
  300 ms; founding check marks fade in over 150 ms. Under Reduce Motion the scroll jumps
  and the fades stay. Popovers, alerts, and the Settings window use the system's own
  transitions.
- **Copy style:** Title Case for menu items and buttons, sentence case for everything
  else; the window title is the town's name. The voice is in-world and gentle, second
  person, with no exclamation marks, and plain in errors and confirmations
  (`ux-guidelines.md` › Language and copy, which also holds the glossary and the Japanese
  register).
- **App icon:** a placeholder while the app is not distributed (ADR-0009). When it is
  made: a small house or a row of houses in graphite and white with one window lit in
  Lamplight amber, layered in Icon Composer for the default, dark, clear, and tinted
  appearances.

Shared values move into one internal type in `TownsfolkUI`, provisionally `DesignLock`,
once a second view needs them (`designing-ui` › `references/design-lock.md`); each view's
private `Layout` enum refers to it. None of it goes in `TownsfolkCore`.

## Consequences

### Positive

- New screens are built against fixed values, and review compares a screenshot with
  this list.
- Every measured text pair passes AA in light, dark, and High Contrast — 14 of 14 in
  `design-direction.md` › Measured contrast.
- The system accent and system controls follow the person's own settings.

### Negative

- The tightest pair is `SecondaryText` over the wash at its strongest (5.05:1 light,
  4.97:1 dark), so a stronger wash re-runs the contrast pass first.
- With no avatars or imagery, residents are told apart by name alone until the Later
  visual identity.

### Follow-ups

- The two Color Sets and the `DesignLock` values, applied when the first screen is built
  — an issue in the backlog.

## Open questions

- The popover and grouped-form backgrounds were approximated (#F2F2F2 / #323232):
  re-measure `SecondaryText` on screenshots of S4 and S5 in both appearances.
- The glass pill's label contrast over light and dark posts, with Reduce Transparency on
  and off, is checked on screenshots.
- If the system text field ignores the composer placeholder's color, the placeholder is
  raised to meet AA rather than shipped in the system's gray.
- Whether the wash is visible enough at a glance from a second display is settled in
  use.

## Sources

- [`docs/design/design-direction.md`](../../design/design-direction.md) — the research,
  the decision ledger, the token values, and the measured contrast, with its own sources
  (Refero styles and screens, and the macOS 27 system colors measured on 2026-09-30).
- Run on this repository's toolchain (macOS 27.0, build 26A428), 2026-10-06 (#10): a
  Swift script passing each symbol name in the seed files to
  `NSImage(systemSymbolName:accessibilityDescription:)` printed "found" for all 16 and
  "MISSING" for `not.a.real.symbol`. The script and its output are in the pull request;
  neither is committed.
- <https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass> — the
  glass button style, macOS 26.0+ — checked 2026-09-30
- <https://developer.apple.com/documentation/swiftui/shapestyle/separator> — "a style
  appropriate for foreground separator or border lines" — checked 2026-09-30
- <https://developer.apple.com/design/human-interface-guidelines/app-icons> — layered
  icons made in Icon Composer, with default, dark, clear, and tinted appearances — checked
  2026-09-30

## Related

- [ADR-0001](0001-app-shape.md) — the window these sizes apply to.
- [ADR-0007](0007-english-and-japanese.md) — the copy style holds in both languages.
- [ADR-0009](0009-not-distributed-yet.md) — why the icon stays a placeholder.
