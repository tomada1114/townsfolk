# Townsfolk — Screens and Flows

- **Source:** [requirements.md](requirements.md), signed off 2026-09-30. Section numbers
  (§) refer to it.
- **Platform:** macOS, one main window (SwiftUI), a Settings window, popovers, alerts,
  and the menu bar.
- **Not here:** app-wide UX policy — states, feedback, motion, validation, accessibility,
  and language rules — lives in [ux-guidelines.md](../design/ux-guidelines.md). This document cites
  it and does not restate it. Colors, type, and spacing come from the design lock.

Wireframe copy is English; every string also ships in Japanese (§3.10).

## 1. Screen inventory

| # | Surface | Kind | Serves |
|---|---|---|---|
| S1 | Town window | the one main window | §3.2, §3.3, §3.5, §3.6, §3.7, §3.8 |
| S2 | First run | content of S1 before a town exists | §3.1 |
| S3 | Founding | a state of S1 (first run and after moving) | §3.1, §3.9 |
| S4 | Resident profile | popover on a resident's name | §3.12 |
| S5 | Settings | Settings window, ⌘, | §3.4, §3.7, §3.10 |
| S6 | Move confirmation | alert | §3.9 |
| S7 | Model unavailable | full-window state at first run; a banner in S1 later | §3.11 |
| S8 | Menu bar | menus | every command |

The About panel is the standard one; there is no help book.

## 2. The window

- One window, titled with the town's name ("Townsfolk" until a town exists).
- Default 380 × 680 pt, minimum 320 × 440 pt, resizable; size and position are restored.
- The text column is capped at 560 pt; a wider window centers it.
- Shrinking: the status line truncates first, then quote lines; post text always wraps
  and is never truncated.
- No toolbar buttons: every command lives in the menu bar (S8); Settings opens with ⌘,.
- Closing the window quits the app (§3.7).

## 3. Wireframes

### S1 Town window

```
┌────────────────────────────────────────┐
│ ● ● ●            Maplewood             │ ← title: the town's name
├────────────────────────────────────────┤
│ ☂ Rain since noon · the bakery's new b…│ ← status line (§3.3), one line
│ ┌────────────────────────────────────┐ │
│ │ Say something to Maplewood…        │ │ ← composer, one line; ⌘N focuses
│ └────────────────────────────────────┘ │
├────────────────────────────────────────┤
│ ↩ Mika: "The new bread sold out aga…"  │ ← quote of the older post this
│ ┃ Jun · 1m                             │   group replies to (one line)
│ ┃ Told you. Get there before eight.    │ ← a scene: one group, oldest →
│ ┃ Sora · now                           │   newest, joined by a thread line
│ ┃ Or ask Mika to save you one?         │
│ ────────────────────────────────────── │
│ ☂ It started raining. · 12:02          │ ← event row
│ ────────────────────────────────────── │
│ Tomo (you) · 25m                       │ ← your post: a group of its own
│ Learning Rust today. Wish me luck.     │
│ ────────────────────────────────────── │
│ ┃ Mika · 40m                           │
│ ┃ The oven made a goose noise again.   │
│ ┃ Jun · 38m                            │
│ ┃ Is that… good?                       │
│                  ⋮                     │ ← older entries load on scroll
└────────────────────────────────────────┘
```

- **Order:** newest group at the top. A group is one scene (1–3 posts, §3.2) or one post
  of yours. Inside a group, posts run oldest → newest; while a scene is being revealed,
  its group grows downward one post at a time.
- **Post row:** name, relative time, text. A resident's name opens S4 on click; your own
  name carries "(you)" and opens nothing.
- **Quote line:** a group that replies to an older post starts with a one-line quote of
  it (`↩ Name: "text…"`). A group that starts a new topic has none.
- **Event rows** (events and moves, §3.6): one line with the time, set apart from
  groups, with no thread line; they cannot be replied to.
- **Actions:** hovering a post shows ↩ Reply at its trailing edge. Posts are also
  selectable with the keyboard (§4), and ⌘R replies to the selected one.
- Nothing ever says a scene is being written (§4 of the requirements).

#### S1 variants

**Replying** (after ↩ Reply or ⌘R):

```
│ ┌────────────────────────────────────┐ │
│ │ ↩ Replying to Mika "The oven made…"✕│ │ ← chip; ✕ or Esc cancels
│ │ Poor oven. Maybe it wants a name?  │ │
│ └────────────────────────────────────┘ │
│                               12 left  │ ← counter near the limit (ux-guidelines › Forms and validation)
```

**Your reply, then the town's response** (2–10 minutes later at Normal, §3.5):

```
│ ↩ Tomo: "Poor oven. Maybe it wants …"  │ ← response group quoting you
│ ┃ Mika · now                           │
│ ┃ It's called Gerald now. Thanks.      │
│ ────────────────────────────────────── │
│ ↩ Mika: "The oven made a goose noise…" │ ← your reply, quoting Mika
│ Tomo (you) · 6m                        │
│ Poor oven. Maybe it wants a name?      │
```

**Coming back after a pause** (§3.7):

```
│ ┃ Sora · now                           │ ← live scenes since you returned
│ ── While you were away ─────────────── │ ← heads the catch-up block
│ ┃ Jun · 1h                             │ ← catch-up groups, times inside
│ ┃ …                                    │   the pause
│ 🏠 Hana moved in above the café. · 1h  │ ← at most 1 event and 1 move
│ ┃ Mika · 2h                            │
│ ┃ …                                    │
│ ── You were last here · 2h ago ─────── │ ← where you left off
│ ┃ (posts from before the pause)        │
```

- Nothing appears until the first catch-up scene is written; the block then grows scene
  by scene. There is no progress display.
- A pause shorter than 4 scene intervals adds no block and no divider.
- Only the latest catch-up block keeps its header and divider.

**New posts while you read older ones:**

```
│          ┌─────────────────┐           │
│          │  ↑ 2 new posts  │           │ ← pill; a click or ⌘↑ scrolls to the top
│          └─────────────────┘           │
```

At the top of the timeline, new groups are inserted directly (ux-guidelines › Motion).

**Resting** (the setting is off and another app is active):

```
│ ☾ Resting while you're in other apps   │ ← replaces the status line
```

**Model unavailable, town exists** (S7 has the messages):

```
├────────────────────────────────────────┤
│ ⚠ Apple Intelligence is off, so the    │
│   town is paused.  [Open System Settings]│ ← banner under the title
├────────────────────────────────────────┤
```

The timeline stays readable and the composer still posts; responses wait until the
model is back.

### S2 First run

**S2a Language**

```
┌────────────────────────────────────────┐
│ ● ● ●            Townsfolk             │
├────────────────────────────────────────┤
│                                        │
│   A small town is waiting for you.     │
│   Choose its language.                 │
│                                        │
│   (•) English                          │
│   ( ) 日本語                            │
│                                        │
│   You can change this later in         │
│   Settings.                            │
│                                        │
│   Its residents are written by Apple's │ ← the one plain line about the
│   on-device model, right on this Mac.  │   machinery (ux-guidelines › Language and copy)
│                                        │
│                          [Continue]    │ ← default button (Return)
└────────────────────────────────────────┘
```

English is preselected; choosing 日本語 switches the screen to Japanese at once.

**S2b Your name**

```
│   What should the town call you?       │
│   ┌──────────────────────────────┐     │
│   │ Tomo                         │     │ ← 1–20 characters, trimmed
│   └──────────────────────────────┘     │
│   Residents see this name on your      │
│   posts.                               │
│                                        │
│   [Back]                  [Continue]   │ ← Continue disabled until valid
```

### S3 Founding

```
┌────────────────────────────────────────┐
│ ● ● ●            Townsfolk             │
├────────────────────────────────────────┤
│                                        │
│         Finding you a town…            │
│         ✓ Drawing the streets          │
│         ◌ Meeting the neighbors        │
│         ◌ Saying hello                 │
│                                        │
└────────────────────────────────────────┘
```

- The lines follow the real steps: town, residents, first scene. It is the one wait the
  app shows, because there is nothing to look at yet.
- On success S1 opens with the event row "You moved to Maplewood." and the first scene
  above it.
- After 3 failed attempts: "Couldn't find you a town this time." with [Try Again].

### S4 Resident profile

```
          Mika ← click a name (or ⌘I on the selected post)
 ┌──────────────────────────────┐
 │ Mika Tanaka                  │
 │ Baker · 30s                  │
 │ Cheerful, a little stubborn  │
 │ ──────────────────────────── │
 │ Hobby     Film photography   │
 │ Worry     The oven is dying  │
 │ Knows     Jun — old friend   │
 │           Sora — landlady    │
 │ Into      Rust (from you)    │ ← interests taken up from your names
 │ ──────────────────────────── │
 │ Moved in Sep 30              │
 └──────────────────────────────┘
```

Width 280 pt; Esc or a click outside closes it. A past resident shows "Moved out Oct 12"
instead, with the name in the secondary style. Read-only.

### S5 Settings

```
┌────────────────────────────────────────────────┐
│ ● ● ●                Settings                  │
├────────────────────────────────────────────────┤
│  Language      [ English          ▾ ]          │
│                Menus switch the next time      │
│                Townsfolk opens.                │
│                                                │
│  Your name     [ Tomo                 ]        │ ← 1–20 characters
│                                                │
│  Speed         [ Slow | Normal | Fast ]        │
│                About one new post every        │ ← follows the choice: 15 minutes /
│                3 minutes.                      │   3 minutes / 30 seconds
│                                                │
│  [✓] Keep the town moving while I use other    │
│      apps                                      │
│      When off, the town rests unless its       │
│      window is active.                         │
│  ──────────────────────────────────────────── │
│  [Move to Another Town…]                       │
│      Deletes Maplewood and finds you a new     │
│      town.                                     │
└────────────────────────────────────────────────┘
```

One pane, 480 pt wide. Every change applies at once; there is no Save button. Move to
Another Town… is disabled while the model is unavailable or a town is being founded,
with the reason shown under it.

### S6 Move confirmation

```
┌──────────────────────────────────────────┐
│  Move to another town?                   │
│                                          │
│  Everything in Maplewood — its residents,│
│  posts, events, and the names you        │
│  mentioned — will be deleted. This can't │
│  be undone.                              │
│                                          │
│                  [Cancel]  [Move]        │
└──────────────────────────────────────────┘
```

Cancel is the default button; Move is marked destructive. On Move, S1 switches to S3
and then to the new town.

### S7 Model unavailable

| Reason | Message | Action |
|---|---|---|
| Apple Intelligence turned off | Townsfolk needs Apple Intelligence to write the town. Turn it on in System Settings. | [Open System Settings] |
| Model still downloading | The on-device model is still downloading. The town starts when it's ready. | none |
| Mac not eligible | This Mac can't run Apple Intelligence, which Townsfolk needs. | none |

At first run the message fills the window in place of S2/S3; once a town exists it is
the S1 banner. Availability is checked again whenever the window becomes active, and
founding or the town resumes by itself.

### S8 Menu bar

| Menu | Items |
|---|---|
| Townsfolk | About Townsfolk · Settings… ⌘, · Services · Hide Townsfolk ⌘H · Hide Others ⌥⌘H · Show All · Quit Townsfolk ⌘Q |
| Edit | Standard: Undo ⌘Z, Redo ⇧⌘Z, Cut ⌘X, Copy ⌘C, Paste ⌘V, Select All ⌘A |
| Town | New Post ⌘N · Reply ⌘R · Show Profile ⌘I · Scroll to Latest ⌘↑ · — · Move to Another Town… |
| Window | Standard: Minimize ⌘M, Zoom, Bring All to Front |
| Help | Standard, with no help book |

- New Post focuses the composer and leaves reply mode.
- Reply acts on the selected post (a resident's or yours); Show Profile on the selected
  post's author. Both are disabled with no post selected; Show Profile also when the
  post is yours; neither applies to an event row.
- Move to Another Town… is disabled while the model is unavailable or a town is being
  founded.

## 4. Keyboard

| Key | Does |
|---|---|
| ⌘N | Focus the composer (New Post) |
| Return | Post from the composer |
| Esc | Cancel reply mode; again, leave the composer; closes S4 |
| ↑ / ↓ | Move the selection between posts in the timeline |
| Tab / ⇧Tab | Move between the composer and the timeline |
| ⌘R | Reply to the selected post |
| ⌘I | Show the selected post's author's profile |
| ⌘↑ | Scroll to the latest |
| ⌘, | Settings |

Every control is reachable with Full Keyboard Access (ux-guidelines › Accessibility targets).

## 5. Flows

### F1 First run (§3.1)

1. Launch with no town → S2a: choose a language → Continue.
2. S2b: enter your name → Continue.
3. S3: the town is founded → S1 opens with "You moved to {town}." and the first scene.

```
[Launch] -> [S2a Language] -> [S2b Name] -> [S3 Founding] -> [S1 new town]
                 |                               |
                 v                               v (3 failures)
         [S7 model unavailable]        ["Couldn't find you a town"]
                 |                               |
                 v (available)                   v [Try Again]
           [S3 Founding]                   [S3 Founding]
```

### F2 Glance (§3.2–§3.4)

1. The window is visible (or active, with the setting off) and a scene falls due.
2. The scene is written out of sight; its posts appear one at a time in a new group at
   the top.
3. The status line changes when an event starts or ends or a new topic appears.

```
[Scene due] -> [Written] -> [Group appears, post by post] -> [Status line updates]
                   |
                   v (refused / failed / Mac too hot)
         [Retry ≤ 2 with new seeds] -> [Skipped silently] -> [Next scene due]
```

### F3 Post a line (§3.5)

1. ⌘N or a click in the composer → type (1–140 characters) → Return.
2. Your post appears at the top at once.
3. After 2–10 minutes (Normal) the first response group appears, quoting your post; up to
   3 response groups follow over about an hour, with unrelated scenes in between.

```
[Composer] -> [Return] -> [Your post at top] -> (2–10 min) -> [Response group] -> (… ≤ 3)
     |                                                |
     v (blank)                                        v (your post keeps being refused)
[Return does nothing]                          [No response; nothing shown]
```

### F4 Reply to a post (§3.5)

1. Hover a post → ↩ Reply, or select it → ⌘R.
2. The composer shows "Replying to Mika" with a quote → type → Return.
3. Your reply appears as a new group quoting Mika's post; responses follow as in F3,
   with Mika speaking first 70% of the time.

```
[Post] -> [↩ Reply / ⌘R] -> [Composer: "Replying to Mika"] -> [Return] -> [Your group] -> (F3)
                                   |
                                   v (✕ / Esc)
                            [Composer back to a new post]
```

### F5 Come back after a pause (§3.7)

1. The window stops being visible (minimized, covered, another Space, screen locked, Mac
   asleep) — or, with the setting off, another app becomes active. Town time stops; with
   the setting off and the window still visible, S1 shows "Resting".
2. The window is visible (or active) again. If the pause lasted 4 scene intervals or
   more, catch-up groups appear under "While you were away", with "You were last here"
   below them; otherwise the overdue scene simply runs.
3. Live scenes resume above.

```
[Visible] -> [Hidden: town time stops] -> [Visible again] -> pause ≥ 4 intervals?
                                                              | yes             | no
                                                              v                 v
                                                  [Catch-up block]      [Overdue scene]
                                                              |
                                                              v (model unavailable)
                                                [S1 banner; catch-up waits]
```

### F6 Look up a resident (§3.12)

Click a resident's name, or select a post → ⌘I → S4 opens → Esc or a click outside closes.

### F7 Change a setting (§3.10)

⌘, → S5 → change a value → it applies at once: speed from the next scene; language in
the UI at once, in the menus at the next launch, and in everything written from then on;
your name everywhere in the UI.

### F8 Move to another town (§3.9)

1. S5 or the Town menu → Move to Another Town…
2. S6 → Move.
3. The current town is deleted → S3 → S1 with the new town.

```
[Move to Another Town…] -> [S6] -> [Move] -> [Town deleted] -> [S3] -> [S1 new town]
          |                   |
          v (model unavailable) v [Cancel]
     [Disabled, reason shown] [Nothing changes]
```

## 6. Cross-cutting behavior

Per [ux-guidelines.md](../design/ux-guidelines.md):

- **States** — founding, catch-up, resting, and model unavailable, with their copy.
- **Feedback and loading**, **Motion** — how a new post and a changed status line
  arrive, with Reduce Motion honored.
- **Forms and validation** — the composer's 140-character limit and counter; the 1–20
  character name.
- **Accessibility targets** — VoiceOver reading of groups, quote lines, and event rows;
  keyboard reach; contrast.
- **Language and copy** — English and Japanese, switching inside the app, the glossary.
