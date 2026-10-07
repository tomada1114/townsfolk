# Townsfolk — Design direction

- **Status:** research record from the kickoff (2026-09-30), approved by the owner the
  same day. Its [Design lock](#design-lock) section is binding: every screen obeys it,
  `TownsfolkUI`'s `DesignLock` mirrors it in code, and a change to either changes both in
  the same pull request (`designing-ui`).
- **Inputs:** `docs/product/requirements.md`, `docs/product/ux-flows.md`,
  `docs/design/ux-guidelines.md`; the template's `designing-ui` (system first, custom by
  exception) and its design-lock fields.
- **Research:** Refero styles — 5 searches (cozy small-town game sites; social-feed
  products; native Mac app sites; calm, ambient technology; neighborhood bulletin and
  local-newspaper sites), about 40 previews, 3 full styles: Threads (`c88d0a86…`), Paste
  (`1c0fbb80…`), Bluesky (`89560868…`). Refero screens — 3 searches (a reply thread
  joined by a line; a new-posts control above a feed; a profile hover card), 4 screens
  examined (links under Sources): Posts by Read.cv, the Threads following feed, a Threads
  profile hover card, and a Nextdoor community feed. No
  flow research: the flows are settled in `ux-flows.md`. Refero styles describe web
  pages, not native app screens, so they set the visual language only; screen structure
  comes from `ux-flows.md` and the HIG.
- **Measured on macOS 27 (2026-09-30):** the system colors this palette sits on, resolved
  offscreen in light and dark and composited onto the canvas — canvas
  (`textBackgroundColor`) #FFFFFF / #1E1E1E; `labelColor` #272727 / #DDDDDD;
  `secondaryLabelColor` #808080 / #9A9A9A; `separatorColor` #E6E6E6 / #343434; the
  unemphasized selection fill #DCDCDC / #464646. The Increase Contrast system variants
  did not resolve offscreen and are not measured.

## Direction: one lamp in a quiet street

A quiet, monochrome feed that looks as if it came with the Mac: the residents' words in
label color on the system canvas, structure from hairlines and a thread line rather than
cards, one typeface at understated sizes — and a single warm light. Each new post arrives
on a soft amber wash that fades out over three seconds, like a window lighting up down
the street, so a glance from across the desk catches that the town moved. Apart from the
system accent on system controls, nothing else in the window is colored.

### Reference lock

- **Primary reference:** Threads (threads.com, Refero style `c88d0a86`) — a content-first
  monochrome feed: system-ui type at 12–15 px, black text on a light canvas, hairline
  dividers, a compact 4 px rhythm, no heavy shadows, no large headlines.
- **Preserve:**
  1. Content first: post text in the primary label color on an opaque canvas; everything
     else recedes (Threads: content "should remain the focal point").
  2. One typeface at understated sizes, hierarchy by weight: the system font, nothing
     larger than `.title3`, names bold and text regular.
  3. A compact rhythm on a 4 pt base (Threads: "compact visual density … base unit of
     4px").
  4. Flat structure: no cards, fills, or shadows around posts; groups are separated by
     space and a hairline (Threads' Border Light role: "subtle hairline dividers").
  5. A conversation drawn as one group joined by a thread line (Threads; Posts by
     Read.cv).
- **Borrow only:**
  - From Paste (pasteapp.io, `1c0fbb80`): the lantern — one warm amber focal point on an
    otherwise monochrome field, kept to decoration, with actions left to a cool blue
    ("warm brand, cool CTA"). Here it becomes **Lamplight**: the arrival wash now, and
    the lit window of the app icon later.
  - From Bluesky (bsky.app, `89560868`): metadata that stays readable — secondary text
    dark enough to read (Bluesky's Slate Text, not Threads' Muted Gray, which measures
    2.96:1 on white), kept a neutral gray rather than Bluesky's slate blue.
- **Role rules:**
  - **Lamplight** (custom Color Set) is decoration only: the wash behind a newly arrived
    post, fading over 3 s, and the app icon's lit window. Never text, a symbol, a control,
    a border, a selection, or a surface that stays; never the only sign of anything
    (recency is also in the time text). Paste's rule carries over: the amber is "never …
    a button fill".
  - **SecondaryText** (custom Color Set) is for metadata text and the symbols beside it:
    post times, "(you)", quote lines, event rows, labeled dividers, the resting line, the
    replying chip, the counter and helper text, the composer's placeholder, the profile's
    details, and a past resident's name. Never post text, never a fill.
  - **AccentColor** is the system default and appears only where system controls put it
    (the default button, text selection, Settings' controls, the focus ring). No custom
    view uses it, and nothing depends on its hue.
  - **Primary label color** carries post text, names, the status line, and every message
    about a problem — the over-limit counter, inline validation, the model banner — each
    paired with a symbol. Never red.
  - **Separator** draws the hairlines between groups, the labeled dividers, and the
    thread line. These lines are decoration: spacing and the VoiceOver container group
    the posts too.
- **Media strategy:** none in the MVP. The timeline is text only (requirements decision
  log); there are no avatars, monograms, or illustrations, because residents' visual
  identity is a Later feature. Every glyph is an SF Symbol.
- **Reject:**
  - Post cards, fills, and shadows (Threads' and Bluesky's post cards): in a 380 pt
    window they spend width and add chrome.
  - Avatars or initial circles standing in for the Later visual identity.
  - An amber AccentColor or any amber control: it breaks Paste's role rule and would put
    brand into buttons.
  - Threads' violet and Bluesky's blue as custom accents: the system accent already does
    that job and follows the person's setting.
  - Threads' Muted Gray and the system `.secondary` for small text: both fail AA on the
    light canvas.
  - Red error text: systemRed measures 3.57:1 on white.
  - The small-town-newspaper look the neighborhood and cozy-game searches pulled toward —
    cream paper, serif headlines, terracotta and sage: the calm-editorial average, and a
    fiction of print the app does not need.
  - Row fills for hover or keyboard selection: the selected post is shown by the system
    focus ring alone, so every text pair below holds.
  - Glass or translucency behind the timeline; a dark-only look.
  - Emoji as icons: the wireframes' ☂ 🏠 ☾ ⚠ stand for SF Symbols.

## Decision ledger

| Decision | Source | Role rule | Why |
|---|---|---|---|
| Monochrome feed on the opaque system canvas | Threads (primary): black text on a light canvas, content as the focal point | the canvas takes no tint but the transient wash | the residents' words are the product, and a glance from a distance reads them best |
| System font; `.title3` is the largest style | Threads: system-ui only, "avoid large, impactful headlines"; template `designing-ui`: built-in text styles | — | native, follows the system's accessibility text features, no license |
| Post text `.body` with 2 pt extra line spacing | `ux-guidelines.md` (13 pt body); Threads' body line height 1.4 | post text only | 18/13 ≈ 1.4: multi-line posts read without crowding |
| Name `.headline`, then the time in `.body` SecondaryText on the same line | Threads and Bluesky post headers: name weight 600, time muted at a similar size | — | hierarchy by weight; one line per header |
| Supporting lines at `.callout` | Posts by Read.cv: a gray "Replying to" line above a reply; Threads' caption scale | metadata only | quote lines and event rows recede behind the posts |
| `SecondaryText` custom Color Set | measured: `secondaryLabelColor` 3.95:1 on the light canvas (AA needs 4.5:1); Bluesky's Slate Text for metadata | metadata text and its symbols | AA was chosen in `ux-guidelines.md`, and `.secondary` meets it only in dark |
| `Lamplight` custom Color Set: Paste's Honey Glow #FEAB30 at 20% over the light canvas, 14% over the dark one | Paste: one warm focal point, reserved for the brand mark, never a button fill; `ux-guidelines.md` › Motion | decoration only | the one expressive moment, weak enough that text keeps AA over it |
| AccentColor = system default | template `designing-ui` (the accent may carry brand, never meaning); Paste's warm-brand, cool-action split | system controls only | follows the person's accent setting; the warmth stays with the town |
| Hairlines and the thread line in `.separator` | Threads' Border Light role ("subtle hairline dividers") | lines only, decorative | structure without chrome |
| A hanging gutter: the thread line, the quote symbol, and the event symbol sit in a 16 pt gutter left of one shared text edge | template `designing-ui` ("let alignment and indentation carry hierarchy"); the Threads thread line | — | posts, events, and quotes all read down one left edge |
| The selected post is shown by the system focus ring, with no fill | `ux-guidelines.md` (system focus ring only); measured: the unemphasized selection fill takes SecondaryText to 4.19:1 (light) and 3.74:1 (dark) | — | one focus appearance, and text only ever sits on measured backgrounds |
| New-posts pill: the system glass button style (`.glass`, macOS 26+), a capsule | SwiftUI `.glass` ("a Liquid Glass effect based on the button's context"); `ux-guidelines.md` (system controls in their default styles) | the one material in the window | native, independent of the accent hue; Reduce Transparency is the system's job |
| SF Symbols, monochrome, in the color of the text beside them | Threads and Bluesky: outline icons in the text color; template `designing-ui` (one rendering mode per context) | one mode everywhere | color never carries meaning; every symbol comes with words |
| No imagery, avatars, or illustration | requirements decision log (a text-only timeline); visual identity is a Later feature | — | nothing fake stands in for a later feature |
| Problems in primary text with `exclamationmark.triangle` | measured: systemRed 3.57:1 on white | — | AA, and never color alone |
| App icon: one lit window in Lamplight amber on a neutral ground; a placeholder until distribution | Paste's "single lit window" thesis, not its all-amber tile; HIG App icons (Icon Composer, appearance variants) | Lamplight's decoration role | recognizable at a glance without resembling Paste's icon |

## Design lock

The values every screen obeys, one row per design-lock field (`designing-ui` ›
`references/design-lock.md`). Shared values live in one internal type in `TownsfolkUI`,
`DesignLock`, which each view's private `Layout` enum refers to; none of it goes in
`TownsfolkCore`.

| Field | Value |
|---|---|
| Accent color | System default: `AccentColor.colorset` keeps no value. Used by system controls only (default buttons, text selection, Settings' controls, the focus ring). |
| Custom colors | `SecondaryText` — Any #666666, Dark #A3A3A3, Any High Contrast #4D4D4D, Dark High Contrast #C2C2C2: metadata text and its symbols (roles above). `Lamplight` — Any #FFEED6, Dark #3D3221, its High Contrast variants the same values (it is decoration; the stronger High Contrast text colors keep the pairs passing): the arrival wash; the app icon's glow takes its hue. Everything else is a semantic system color. Both Color Sets live in `Packages/TownsfolkKit/Sources/TownsfolkUI/Resources/Colors.xcassets` and are read with `Color(_:bundle: .module)`: a named color in the app's own asset catalog is looked up in the main bundle, which a `#Preview` host (`XCPreviewAgent.app`) does not have, so there it resolves to clear (checked 2026-09-30, #7; moved 2026-10-06, #37). |
| Type | System font only; no fixed sizes. `.body`: post text (2 pt extra line spacing), the composer, first-run and founding text, Settings. `.headline`: resident names in post headers and the profile's full name. Post times: `.body` in SecondaryText after the name ("Jun · 1m"). `.callout`: the status line (primary color; the resting line in SecondaryText), quote lines, event rows, labeled dividers ("While you were away"), the replying chip, the counter, helper text, the profile's details. `.title3`: the heading of a full-window state (S2, S3, S7). Nothing larger, and nothing below 12 pt. |
| Spacing scale | 4, 8, 12, 16, 32 pt. 4 between a post's header and its text; 8 between the posts of a group, between a quote line and its first post, and between the status line and the composer; 12 on each side of the hairline between groups and event rows, and from the composer down to the hairline over the timeline; 4 between the replying chip, the composer's field, and its counter; 16 from the window edge to the content, and as the gutter; 32 as the margin of a full-window state (S2, S3, S7) and between its blocks. The profile popover pads 16 and separates its rows by 8. Settings keeps the system form's spacing. |
| Timeline metrics | The text column, gutter included, is capped at 560 pt and centered. The thread line, a quote line's symbol, and an event row's symbol hang in the 16 pt gutter left of the shared text edge. Thread line: 2 pt wide with round caps, from the group's first header to its last line. Hover ↩ Reply: a 28 × 28 pt borderless button at the trailing end of the post's header line. The Lamplight wash is a square-cornered band across the window's full width, covering the new post's row. |
| Density | A compact rhythm from the spacing scale with regular-size controls (the default `.controlSize(.regular)`; no scene-level modifier). Posts take no fill on hover or selection. |
| Corner radius | System default for every control. No custom containers: the new-posts pill is the glass style's capsule, and the thread line has round caps. |
| Symbols | SF Symbols only, monochrome everywhere, inline at the style and color of the text beside them. Events: every kind in `Resources/SeedTables.json` names its own symbol, and that table is the source of truth; today `weather-turns` `cloud.sun.rain`, `shop-opens` `storefront`, `festival` `party.popper`, `lost-pet` `pawprint`, `road-works` `cone`, `visitor` `suitcase.rolling`, `power-cut` `bolt.slash`, `market-day` `basket`, `snowfall` `snowflake`, `thick-fog` `cloud.fog`, `concert` `music.note`, `fireworks` `fireworks`, `sports-day` `figure.run`, `book-fair` `books.vertical`, and the fixed kinds `move-in` `house`, `move-out` `figure.walk`, and `founding` `house` (the "You moved to {town}." row). Interface: resting `moon.zzz`; quote line and Reply `arrowshape.turn.up.left`; the pill `arrow.up`; a founding step done `checkmark`, pending `circle.dotted`; a problem `exclamationmark.triangle`; cancelling a reply `xmark`. The interface names resolve on macOS 27 (checked 2026-09-30); the event names were checked on macOS 27.0 on 2026-10-06 (Sources). |
| Materials | The new-posts pill only (`.buttonStyle(.glass)`), plus what the system draws for the title bar, popovers, alerts, and the Settings window. The timeline, status line, composer, and banner sit on the opaque canvas. |
| Window sizing | Main window: default 380 × 680 pt, minimum 320 × 440 pt, text column capped at 560 pt (`ux-flows.md` §2; the scene is `docs/architecture.md` › App shape). Profile popover: 280 pt wide. Settings: one pane, 480 pt wide. |
| Motion | Exactly the custom animations in `ux-guidelines.md` › Motion, and no others: a new post fades in over 200 ms (ease-out) while its Lamplight wash fades out over 3 s (ease-in: it lingers, then goes out); the status line crossfades over 200 ms; the pill fades over 150 ms and its scroll to the top takes 300 ms; founding check marks fade in over 150 ms. Opacity only. Under Reduce Motion the scroll jumps; the fades stay. |
| Copy style | Per `ux-guidelines.md` › Language and copy: Title Case for menu items and buttons, sentence case for everything else; the window title is the town's name. Voice: in-world and gentle, second person, no exclamation marks; plain in errors and confirmations. |
| App icon | Placeholder while the app is not distributed (`docs/architecture.md` › Distribution). Direction when made: a small house or a row of houses in graphite and white with one window lit in Lamplight amber — the amber a small focal point, never the whole tile — layered in Icon Composer so macOS can draw its default, dark, clear, and tinted appearances. |

## Measured contrast

Every measured text pair passes AA in light, dark, and High Contrast — 14 of 14 below.
The tightest is SecondaryText on the wash at its strongest (5.05:1 light, 4.97:1 dark),
so a stronger wash re-runs this pass first. With no avatars or imagery, residents are
told apart by name alone until the Later visual identity.

Pairs file: `contrast-pairs.json`, next to this file. Canvas and label values are the
macOS 27 values measured above; the popover and grouped-form backgrounds are
approximated as #F2F2F2 / #323232 and are re-measured on the rendered views during
implementation. The High Contrast rows pair the custom High Contrast variants with the
regular canvas. Not in the table: the separator lines and thread line (decoration), and
the glass pill and focus ring, which the system draws and adapts.

```
name                                                    fg       bg       kind  ratio  required  result
------------------------------------------------------  -------  -------  ----  -----  --------  ------
Light: post text (labelColor) on canvas                 #272727  #FFFFFF  text  14.94  4.50      PASS  
Light: post text on Lamplight at its strongest          #272421  #FFEED6  text  13.56  4.50      PASS  
Light: SecondaryText on canvas                          #666666  #FFFFFF  text  5.74   4.50      PASS  
Light: SecondaryText on Lamplight at its strongest      #666666  #FFEED6  text  5.05   4.50      PASS  
Light: SecondaryText on popover/grouped form (approx.)  #666666  #F2F2F2  text  5.13   4.50      PASS  
Light HC: SecondaryText on canvas                       #4D4D4D  #FFFFFF  text  8.45   4.50      PASS  
Light HC: SecondaryText on Lamplight                    #4D4D4D  #FFEED6  text  7.43   4.50      PASS  
Dark: post text (labelColor) on canvas                  #DDDDDD  #1E1E1E  text  12.27  4.50      PASS  
Dark: post text on Lamplight at its strongest           #E1E0DD  #3D3221  text  9.49   4.50      PASS  
Dark: SecondaryText on canvas                           #A3A3A3  #1E1E1E  text  6.61   4.50      PASS  
Dark: SecondaryText on Lamplight at its strongest       #A3A3A3  #3D3221  text  4.97   4.50      PASS  
Dark: SecondaryText on popover/grouped form (approx.)   #A3A3A3  #323232  text  5.08   4.50      PASS  
Dark HC: SecondaryText on canvas                        #C2C2C2  #1E1E1E  text  9.36   4.50      PASS  
Dark HC: SecondaryText on Lamplight                     #C2C2C2  #3D3221  text  7.03   4.50      PASS  
```

Values measured and rejected (the reasons behind two custom colors and two rules above):

```
fg       bg       kind  ratio  required  result   what it is
#808080  #FFFFFF  text  3.95   4.50      FAIL     system secondaryLabelColor (and placeholder) on the light canvas
#969696  #FFFFFF  text  2.96   4.50      FAIL     Threads' Muted Gray
#FF383C  #FFFFFF  text  3.57   4.50      FAIL     systemRed as text
#666666  #DCDCDC  text  4.19   4.50      FAIL     SecondaryText on the light unemphasized selection fill
#A3A3A3  #464646  text  3.74   4.50      FAIL     SecondaryText on the dark unemphasized selection fill
```

The composer's placeholder is SecondaryText through the field's prompt
(`TextField(text:prompt:label:)`, the prompt's `foregroundStyle`), and the system field
honors that color, so it is the "SecondaryText on canvas" pair above (5.74:1 light,
6.61:1 dark) rather than the system placeholder gray (#808080, 3.95:1): no raised color
was needed (#23). Checked on the field hosted in an `NSHostingView` with a prompt in
SecondaryText's values (Sources); the `#Preview`s themselves are still to be looked at in
both appearances.

## Open

- The popover and grouped-form backgrounds are approximations: re-measure SecondaryText
  on S4 and S5 as rendered, in both appearances.
- The glass pill's label contrast depends on the posts beneath it: check it over light
  and dark content, with Reduce Transparency on and off.
- Whether the wash (20% / 14%) is visible enough at a glance from a second display is
  settled by using the app. A stronger wash re-runs this contrast pass first:
  SecondaryText on the wash is the tightest pair (5.05 light, 4.97 dark).
- The event symbols were checked to exist, not opened in the SF Symbols app; how each
  reads beside an event row is seen once the timeline shows one.
- The app icon's maker and format wait on the distribution decision (the owner's,
  recorded in `docs/architecture.md` › Distribution).

## Sources

Checked 2026-09-30.

- Refero styles: Threads `c88d0a86-bbec-489d-8592-d7860489f05d`, Paste
  `1c0fbb80-f4ca-4c30-8f72-4a8f95a83005`, Bluesky
  `89560868-cf54-4656-8229-e1f1af44838d`.
- Refero screens: <https://refero.design/screens/60c6ef0f-15d3-4277-9579-e2c5720ce6d0>,
  <https://refero.design/pages/c794671f-79b3-4188-b1fb-f178adb38c45>,
  <https://refero.design/pages/ba9e516f-8ba0-4b21-aac6-59a99173e2b0>,
  <https://refero.design/pages/f3d28d98-0718-4e07-b1d7-9c762cc3012a>.
- <https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass> — the
  glass button style, macOS 26.0 and later.
- <https://developer.apple.com/documentation/swiftui/shapestyle/separator> — "a style
  appropriate for foreground separator or border lines".
- <https://developer.apple.com/design/human-interface-guidelines/app-icons> — layered
  icons made in Icon Composer; default, dark, clear, and tinted appearances on macOS.
- Run on macOS 27.0 (26A428), 2026-10-07 (#23): a throwaway, uncommitted Swift script
  hosting a `TextField` in an `NSHostingView`, in the light and dark appearances. With
  the prompt styled #666666 / #A3A3A3, the underlying `NSTextField` carried them as its
  `placeholderAttributedString` foreground color, and its rendered placeholder glyphs
  were darker in light (darkest pixel #797979) and lighter in dark (#B2B2B2) than an
  unstyled prompt's (#888888, #AEAEAE), which leaves a plain `placeholderString` in the
  system placeholder color.
- Run on macOS 27.0 (26A428), 2026-10-06 (#10): a throwaway, uncommitted Swift script
  passing each of the 16 distinct event symbol names to
  `NSImage(systemSymbolName:accessibilityDescription:)` found all of them, and did not
  find a made-up name.
