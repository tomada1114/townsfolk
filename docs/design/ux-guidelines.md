# Townsfolk — UX guidelines

| | |
|---|---|
| Product | Townsfolk — a small fictional town that lives in a window at the edge of your Mac screen |
| Platforms | macOS 27 or later, Apple silicon with Apple Intelligence |
| App type | Social feed, watched ambiently ("Social / community" patterns, plus glanceable display) |
| Related | Requirements: [requirements.md](../product/requirements.md) · Screens and flows: [ux-flows.md](../product/ux-flows.md) · Design direction: [design-direction.md](design-direction.md) (colors, type, spacing, the contrast table) |

Values here are app-wide policy. Screens, layouts, and flows are in ux-flows.md and are
not repeated.

## Principles

- **Glance first** — the top of the window (the status line and the newest group) must
  show that the town moved without anything being read. Decides: new posts arrive at the
  top with a fading tint, times are relative, the status line leads with an ongoing
  event. Gives up: the top of the window holds nothing else — no toolbar, and only
  blocking states may add a banner there.
- **Nothing hurries you** — the app never signals that something is being written or is
  on its way. Decides: scene writing and catch-up are invisible; the only wait ever shown
  is founding a town; there are no toasts, notifications, badges, or sounds. Gives up:
  reassurance that a response is coming.
- **The town speaks as a place** — the UI talks about the town, not the machinery.
  Decides: states are worded in-world; errors and confirmations are plain; the first-run
  screen says once, plainly, that residents are written by Apple's on-device model.
  Gives up: some plainness, and every string needs care in two languages.

## Navigation

One window with no navigation hierarchy and no back stack. The Settings window opens with
⌘,; a resident's profile is a popover; moving away asks through an alert. Nothing nests
deeper than one level.

## Platform conventions

- **macOS:** every command is in the menu bar with its shortcut (ux-flows S8); Settings
  lives in the standard Settings window on ⌘,; the Edit menu's standard items serve the
  composer; the window restores its size and position; Esc cancels reply mode and closes
  a popover; closing the window quits the app. Controls are system controls in their
  default styles, and there is no toolbar.

## States

| State | Trigger | Shows | Primary action | Copy pattern |
|---|---|---|---|---|
| First run | No town exists | S2: language, then your name. S2a carries the one plain line: "Its residents are written by Apple's on-device model, right on this Mac." | Continue | "A small town is waiting for you. Choose its language." |
| Founding | After first run, or after moving away | S3: staged lines checked off as the real steps finish — the only wait the app ever shows | — | "Finding you a town…" · "Drawing the streets" · "Meeting the neighbors" · "Saying hello" |
| Founding slow | Founding passes 60 s | One line added under the steps; no cancel — quitting is always possible | — | "This is taking longer than usual." |
| Founding failed | 3 failed attempts | In place of S3 | Try Again | "Couldn't find you a town this time." |
| Just founded | Founding succeeds | The first event row and the first scene above it | — | "You moved to {town}." |
| Model unavailable | Apple Intelligence off, model downloading, or Mac not eligible | Full window at first run; a banner under the title once a town exists. The timeline stays readable and the composer still posts | Open System Settings (only when turning it on fixes it) | Per reason, ux-flows S7 |
| Resting | The setting is off and another app is active | Replaces the status line | — | "Resting while you're in other apps" |
| Catching up | The window is visible again after a pause of ≥ 4 scene intervals | Groups appear one scene at a time under a header; a divider marks where you left off. No progress display | — | "While you were away" · "You were last here · {relative time}" |
| New posts above | Posts arrive while you are scrolled away from the top | A pill at the top of the timeline | Click, or ⌘↑, to scroll to the top | "↑ {n} new posts" |
| A scene fails or is refused | Any generation failure | Nothing | — | — |
| Your post draws no response | Your post keeps being refused | Nothing; the post stays | — | — |

There is no empty timeline: founding always leaves at least the "You moved to {town}."
row, and there is no offline state because nothing uses the network.

## Feedback and loading

| Rule | Value |
|---|---|
| Wait indicators | Only founding shows one (S3), from its first moment, since it always takes seconds. Scene writing and catch-up never show one — a post simply appears |
| Your post | Appears at once (a local write); there is no pending state |
| Settings | Apply at once; no Save button |
| Destructive actions | One: Move to Another Town…, confirmed by an alert whose default button is Cancel. It is irreversible, so there is no undo |
| Toasts | None; the app has no toast |
| Error placement | Input problems inline under the field; blocking states in place (the model-unavailable banner or full window, founding failed); generation failures invisible |

## Forms and validation

There are two fields, and both have only length rules, so they validate as you type: a
length cannot be wrong too early.

- **Composer:** 1–140 characters after trimming. No counter until 20 remain; then
  "{n} left"; past the limit "{n} over" with a warning symbol, and Return does nothing.
  Input is never cleared or cut. A blank composer ignores Return silently. Return posts;
  pasted line breaks become spaces.
- **Your name, first run:** 1–20 characters after trimming; Continue stays disabled
  until valid; past the limit "{n} over".
- **Your name, Settings:** checked on Return or on leaving the field; if invalid, "Use
  1–20 characters." appears under the field, the previous name stays in effect, and the
  input is kept.

## Motion

- **Amount:** restrained. The one expressive moment is a new post arriving, because it is
  what a glance looks for.
- **A new post at the top** (every post of a scene, and yours): the list makes room
  without sliding, the post fades in over 200 ms (ease-out), and a soft background tint
  fades out over 3 s. The tint's color comes from the design lock.
- **Status line change:** 200 ms crossfade.
- **New-posts pill:** 150 ms fade in and out; its click scrolls to the top over 300 ms.
- **Founding steps:** each check mark fades in over 150 ms.
- Popovers, alerts, and the Settings window use the system's own transitions.
- Only opacity is animated; nothing slides, scales, or bounces.
- **Reduce Motion:** the scroll to the top jumps instead of scrolling; the fades stay,
  since they involve no movement.

## Language and copy

- **UI languages:** English and Japanese, chosen in the app (first run, then Settings)
  and independent of the macOS language. The app's own strings switch at once;
  OS-provided menu items follow at the next launch. No right-to-left languages.
- **Formatting:** relative times, dates, and numbers go through the platform formatters
  with **the app's language as their locale**, never the Mac's current locale —
  otherwise a Japanese UI on an English Mac would print English times.
- **Relative time:** "now" under a minute, then minutes, then hours up to 23 hours, then
  a short date (the formatter's abbreviated forms in each language). Updated every 60 s.
  Pointing at a time shows the full date and time.
- **Text expansion:** English runs about 50% longer than Japanese for the same string;
  no fixed-width labels or buttons — text wraps or truncates as ux-flows §2 says.
- **Register:** in-world and gentle; the town is a place and you are one of its
  residents. Second person, no exclamation marks. Japanese uses the polite form
  (desu/masu) in UI strings. Errors and confirmations drop the in-world voice and state
  plainly what happened and what to do.
- **Capitalization:** Title Case for menu items and buttons; sentence case for
  everything else. An ellipsis ends a command that asks for more before acting ("Move to
  Another Town…") and an in-world line that is still happening ("Finding you a town…").
- **Buttons:** start with a verb ("Try Again", "Open System Settings", "Move").
- **Destructive confirmation:** names the town and says it cannot be undone (ux-flows S6).
- **Machinery stays out of sight:** the UI never says AI, bot, generate, or model —
  except the one first-run line and the model-unavailable messages, which must name Apple
  Intelligence for you to act on them.

| Use | Don't use | For |
|---|---|---|
| town | world, app, simulation, instance | the place |
| resident | character, bot, AI, agent, NPC | the people who live there |
| post | message, tweet, chat | anything anyone writes |
| reply | comment | a post answering another |
| event | notification, update, alert | something that happens in the town |
| moved in / moved away | spawned, created, removed, deleted | population changes |
| While you were away | catch-up, sync, backfill | the catch-up block |
| resting | paused, idle, stopped | the town not running while its window is visible |
| Finding you a town | generating, loading, creating | founding |
| Move to Another Town… | reset, delete town, new game | starting over |

## Accessibility targets

| Target | This product |
|---|---|
| Level | WCAG 2.2 AA, with one focus appearance everywhere (the spirit of 2.4.13) |
| Focus ring | The system focus ring only; every focusable custom view uses it, and no view draws its own |
| Minimum target size | 28 × 28 pt for icon buttons such as the hover Reply (macOS default control size); never below 20 × 20 pt (macOS minimum) — Apple HIG, Accessibility, checked 2026-09-30 |
| Keyboard | Every function reachable: hover-only actions have menu commands (⌘R, ⌘I); focus order follows the visual order — status line, composer, timeline; checked with Full Keyboard Access |
| Focus not obscured | Scrolling to a focused post leaves room for the new-posts pill (its height + 8 pt) so the pill never covers it |
| VoiceOver | A post reads "{name}, {relative time}: {text}" (yours: "You, …"); a quote line "Replying to {name}: {text}"; a group is a container labeled "Conversation, {n} posts"; an event row "{text}, {time}"; the status line is labeled "Town status" |
| Announcements | Polite only: a response to your post ("{name} replied to you"), the end of founding ("You moved to {town}."), a catch-up once ("{n} posts while you were away"), and the model-unavailable banner appearing. Ordinary posts are not announced — the town posts constantly. Nothing is assertive |
| Color use | Never the only carrier: the arrival tint is decoration (recency is also in the time text); your posts carry "(you)"; event rows carry a symbol and text; the over-limit counter carries a symbol and text |
| Text | System text styles; body at the macOS default of 13 pt and nothing below 10 pt (Apple HIG, checked 2026-09-30) |
| Contrast | 4.5:1 for text up to 17 pt, 3:1 at 18 pt and above or bold; text keeps 4.5:1 over the arrival tint at its strongest. Measured in design-direction.md's "Measured contrast" table |
| Increase Contrast, Reduce Transparency | Honored through system colors and materials; every custom color ships a high-contrast variant |
| Reduce Motion | See Motion |

Verification for the implementing session: a VoiceOver pass through flows F1–F5 of
ux-flows.md; a keyboard-only pass through every flow; screenshots in light and dark, with
Increase Contrast on; one pass in grayscale (System Settings › Accessibility › Display ›
Color Filters).

## App-type rules

- **Keep the read position.** When posts arrive while you are scrolled away from the
  top, the post in view stays put and the pill counts what arrived. A feed that jumps
  loses the reader.
- **Older entries load as you scroll.** The window has no footer to hide, and the read
  position is kept, so a "Load more" button would add nothing.
- **No time-maximizing patterns** — no streaks, notifications, badges, or sounds
  (requirements §2 non-goals).

## Reference products

| Product | Flow studied | Adopted | Rejected | Why |
|---|---|---|---|---|
| Bluesky, Threads, X | Home feed, compose box, conversation display | Newest-first feed; compose box at the top; a conversation shown in order with a thread line; relative times | Algorithmic ordering; counters and engagement prompts | The feed the owner pictures, minus its conveniences |
| AI-populated social feeds and AI town simulations (desk research, 2026-09-30) | How residents' activity, waiting, and absence are shown | A familiar feed; looking at what happened while you were away | Instant mass replies; waits shown as "processing"; typing indicators | Replies arriving instantly and in bulk read as cheap, and visible machinery breaks the town |

## Non-goals

| Not doing | Why | Covered instead by |
|---|---|---|
| Toasts, notifications, badges, sounds | Nothing hurries you; the town moves only while visible | The window itself |
| "Writing…" or progress for scenes and catch-up | Machinery stays out of sight | Posts simply appear; the arrival tint |
| Custom focus rings | One focus appearance everywhere | The system focus ring |
| A tour or tips | First run is two steps; the town explains itself | S2's copy |

## Open items

- Open: whether one status line carries enough at a glance, or needs a second line or
  rotation — settled by using the app (requirements §3.3).
- Settled: the arrival tint is Lamplight, at 20% over the light canvas and 14% over the
  dark one ([ADR-0008](../architecture/adr/0008-design-lock.md)), measured in
  design-direction.md; whether it is visible enough at a glance is settled in use.

## Decision log

| Date | Decided | Rejected options | Why |
|---|---|---|---|
| 2026-09-30 | Settled from the inputs without asking: one window with no navigation; macOS conventions; no accounts; no empty or offline state; the only wait shown is founding; inline input errors; one destructive action behind an alert | — | Requirements and ux-flows already fix these |
| 2026-09-30 | A new post fades in over 200 ms with a background tint fading over 3 s; nothing slides | Appearing with no motion or tint; sliding in from the top | Visible at the edge of sight without pulling the eye while you work |
| 2026-09-30 | Relative times ("now", minutes, hours, then a date), full time on pointing | Clock times; both side by side | Recency is what a glance needs; both crowd a narrow window |
| 2026-09-30 | In-world, gentle copy; plain errors and confirmations; one plain first-run line that residents are written by Apple's on-device model | Standard Mac-app wording | Keeps the town a place, and stays honest about what writes it |
| 2026-09-30 | WCAG 2.2 AA with the system focus ring everywhere | AA alone; AA with selected AAA | A single focus appearance is cheap now and inconsistent if added later |
| 2026-09-30 | Both fields validate live, since their only rules are lengths | Validate on leaving the field; on submit | A length cannot be wrong too early, and live counting shows the limit before it bites |
