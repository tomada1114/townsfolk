# Townsfolk — Requirements

- **Status:** Signed off 2026-09-30
- **Platform and stack:** macOS, one window. Built on `tomada1114/macos-app-template`
  (SwiftUI, XcodeGen, the `TownsfolkCore` / `TownsfolkUI` / `TownsfolkPlatform` split, Swift 6
  language mode, strict lint and coverage gates, App Sandbox on). Text is written by
  Apple's on-device model through the Foundation Models framework, called directly: no
  server, no API key, nothing leaves the Mac. Requires macOS 27 or later on an Apple
  silicon Mac with Apple Intelligence turned on — the template targets macOS 14, so the
  new floor is recorded in
  [`docs/architecture.md` › macOS floor](../architecture.md#macos-floor).

Numbers marked † are **starting values**. They live in one `Tuning` type and are
adjusted by using the app; they were deliberately not decided on paper, because only
running the real model on a real Mac can settle them.

## 1. Overview

- **What it is:** a small fictional town that lives in a window at the edge of your Mac
  screen. Its residents — people, text only in this version — post to a shared board
  shaped like a small social feed, and keep conversations going on their own. You
  glance at it for a few seconds while you work and see that the town is moving; when
  you have a minute you read it the way you would open a social app, and now and then
  you post a line as one of the residents. The residents react over the following
  minutes to tens of minutes, one at a time, and a topic can come back later. Events
  happen; people move in and move out. While the window is out of sight the town stops,
  and when you come back it has caught up a little on what happened while you were away.
- **What it is not:** a tool. It does not help you work, manage tasks, or answer
  questions. It exists to be pleasant to watch and to feel linked to what you are doing.
- **Who it is for:** its developer first, at a Mac during work and during breaks. It is
  built so that other people could use it too: every install founds its own town. It is
  in English only.
- **Core interaction:** glance at the timeline and the town's status line and see the
  town moving; occasionally post one line and watch the town respond over time. If
  glancing does not show a living town, nothing else matters.
- **Success** — judged by the owner in daily use; the app measures nothing:
  - you look at it on days you post nothing;
  - it becomes something you keep open at the edge of a screen;
  - finding out what happened while you were away is enjoyable.
- **Principles taken from similar apps** (AI-populated social feeds and AI town
  simulations): a familiar feed needs no learning; checking what happened while you were
  away is a pleasure of its own; the user joins with the same actions as a resident.
  Avoided: instant mass replies (they feel cheap and make every reply worthless), stock
  characters with fixed names and types, mentions of people who do not exist, one
  generation putting words in the wrong speaker's mouth, and waiting that is shown as
  "processing".

## 2. Scope

### MVP

- Founding a town at first run: you choose your display name; the model
  invents the town and its first residents (§3.1)
- A timeline the residents keep writing on their own, scene by scene (§3.2)
- The town's status line: what is going on right now, at a glance (§3.3)
- Speed: Slow, Normal, or Fast (§3.4)
- Your post: one line, new or in reply to a post; the town responds with a delay (§3.5)
- Events, and residents moving in and out (§3.6)
- When the town runs, when it stops, and catching up after a pause (§3.7)
- The town's log, kept on this Mac (§3.8)
- Moving to another town (§3.9)
- Settings: display name, speed, running while you use other apps (§3.10)
- Writing scenes with the on-device model: availability, refusals, limits (§3.11)
- Resident profiles: who is who, on demand (§3.12)

### Later

- **Screenshot input** — hand the town a screenshot of what you are doing (code, a
  comic, a news page) and related topics or residents appear. Expected to become the
  owner's main way of posting, so it is the first thing after this version. Waits
  because the small model's image understanding and its token cost are unverified.
- **A visual identity for residents** — animals living like people, recognizable at a
  glance by look rather than by name (icons, emoji). Waits until text alone has shown
  whether the town is alive.
- **Residents' long-term memory** — remembering events from days ago. This version
  remembers roughly the last day (§3.8). Pulled forward if the town grows stale within
  days.
- **Outside information** — topics from RSS or similar, handled like the names you bring
  up (§3.5), and a topic preference (everyday chat, business news, …). Waits because
  this version makes no network access.
- **Richer residents and staging** — deeper characterization, move-in and move-out
  scenes staged beyond a timeline line (the moves themselves are in the MVP).
- **A resident roster view** — residents side by side, the current speaker highlighted,
  who is most active.
- **External integrations** — letting residents search the web through MCP or an API
  key, with a monthly cap.
- **Residents raising real-world topics** — news, products, and people they bring up on
  their own; needs outside information to avoid confidently stale talk.
- **Deleting your own post** — not in this version; until then a mistaken post is removed
  only by moving to another town. Pulled forward if that becomes a real problem.
- **Mentioning a resident (`@name`)** — addressing a resident directly; waits because it
  pulls the feed toward a chat.
- **Likes** — residents liking posts on their own, and you liking theirs; added when the
  owner wants them.

### Non-goals

- **Being useful** — no task management, no help with work, no accurate answers. The
  town is for watching.
- **Instant replies** — every response is delayed by minutes; there is one generation
  path. A reply within seconds turns the town into a chat app.
- **Running while out of sight** — no menu-bar agent, no background running while the
  window is closed or hidden; the pause and catch-up in §3.7 replace it.
- **Following the time of day** — the town is as lively at 3 a.m. as at noon.
- **Measuring engagement** — no analytics, no metrics, no telemetry.
- **Network access** — none in this version (outside information is Later).
- **Curating residents** — no creating, editing, or removing residents by hand, and no
  approving generated ones. Hand-picked lists run out and make every town the same.
- **Editing your posts** — once residents have responded, an edit would make them wrong.
- **Other reactions** — no reposts, quotes, emoji reactions, or follower counts (likes
  are Later).
- **Feed conveniences** — no searching, filtering, bookmarking, or exporting the log. The
  town borrows a social feed's shape, not its utility features.
- **Several towns, sync, accounts** — one town at a time, on one Mac, with no account.
- **Pulling you back** — no notifications, Dock badges, sounds, streaks, or messages
  that the residents miss you. The town only moves while its window is visible, so there
  is nothing to announce, and a hook that pulls you back is exactly the compulsive use
  this app stays away from.
- **Window extras** — no always-on-top, no showing on every Space, no launch at login,
  no global shortcut (the owner does not want them in this version). If the town stops
  too often because work windows cover it, always-on-top and every-Space are the first
  things to revisit.

## 3. Features

### 3.1 Founding a town

#### Overview
- **Purpose:** start a town unique to this install, asking for as little as possible.
- **Access:** first launch, when no town exists; and after moving away (§3.9).

#### Specifications

| Item | Specification |
|------|---------------|
| Asked of you | Your display name — nothing else |
| Display name | 1–20 characters†, trimmed, required |
| Invented by the model | Town name (≤ 30 characters†), a setting of 2–3 sentences, 3–5 named places†, and 3 residents† |
| A resident | Name, age group, occupation, hobby, a current worry, personality, relationships to other residents |
| Variety | Each resident is seeded from a random combination of axes (occupation, personality, life stage, hobby) drawn from lists shipped with the app; names never repeat within a town |
| After founding | The first scene is written at once, so the timeline is never empty when you first see it |

#### Edge Cases
- **Generation fails or is refused:** retry with new seeds up to 3 times†; if it still
  fails, say so and offer to try again.
- **Apple Intelligence unavailable:** explain what is missing and how to fix it (§3.11);
  no town is founded until the model is available.
- **The app quits mid-founding:** nothing is kept; the next launch founds again with the
  name already chosen.

### 3.2 The timeline

#### Overview
- **Purpose:** the living part — residents posting and replying without you.
- **Access:** the main content of the window.

#### Specifications

| Item | Specification |
|------|---------------|
| Unit of generation | A **scene**: one model call writes 1–3 posts by 1–3 residents, a short exchange |
| Who speaks | Chosen by rules from current residents, never by the model; a scene that names anyone else as a speaker is discarded |
| What they talk about | A seed chosen by rules: something from a resident's profile, an ongoing event, a topic still going, your post (§3.5), or a name you brought up |
| Topic range | Everyday small-town talk, inside the fictional town. Residents never bring up real-world names (news, products, famous people) on their own; they may use names you brought up |
| Invented people | Residents refer only to residents who exist, past residents, and you |
| Replies | A post may reply to an earlier post; the timeline shows which |
| Showing a scene | Its posts appear one at a time, 10–30%† of the scene interval apart (§3.4) |
| Post length | 1–2 sentences, at most 280 characters† |
| Timestamps | Each post carries the time it happened; the town runs on real time |
| While writing | Nothing is shown — no typing indicator, no spinner; posts simply appear |

#### Edge Cases
- **A scene is refused or fails:** it is dropped and never shown (§3.11).
- **Very long history:** see §3.8.

### 3.3 The status line

#### Overview
- **Purpose:** let a few-second glance tell you what is going on without reading posts.
- **Access:** always visible alongside the timeline.

#### Specifications

| Item | Specification |
|------|---------------|
| Source | Ongoing events and the topic tags of recent scenes, filled into templates — no model call of its own |
| Order | An ongoing event first, then the latest topic |
| Length | One line in this version; what does not fit is truncated† (a better overflow is settled in the UX stage and in use) |
| Changes | When an event starts or ends, or a new topic appears; the change should be noticeable at a glance |

### 3.4 Speed

#### Overview
- **Purpose:** let you trade liveliness for heat and battery.
- **Access:** Settings.

#### Specifications

| Speed | A scene about every† | A new post roughly every |
|------|---------------|---------------|
| Fast | 1 minute | 30 seconds |
| Normal (default) | 6 minutes | 3 minutes |
| Slow | 30 minutes | 15 minutes |

- Intervals vary ±50%† so the town never ticks like a clock.
- The interval runs from the last post of the previous scene, so two scenes never
  interleave.
- Speed sets the pace of ordinary scenes; responses to your posts follow §3.5, scaled
  by the same speed.
- A change applies from the next scene. The time of day never changes the pace.

### 3.5 Your post

#### Overview
- **Purpose:** join the town as one of its residents.
- **Access:** a one-line composer in the window; a reply action on any post.

#### Specifications

| Item | Specification |
|------|---------------|
| Kinds | A new post, or a reply to any post in the timeline (a resident's or your own) |
| Length | 1–140 characters†, one line; blank posts are rejected |
| Shown | At once, under your display name |
| Nature | A resident's remark, not an instruction: nobody obeys it |
| Your hidden weight | Slightly more than a resident's — your posts draw responses and linger, but the town never revolves around you |
| First response | 2–10 minutes† after posting at Normal (halved at Fast, doubled at Slow) |
| Further responses | 1–3 response scenes† in total, spread over about an hour† at Normal, with falling likelihood; ordinary scenes on unrelated topics continue in between, in random balance |
| Coming back | For about a day† the post stays a possible seed, picked by 5%† of ordinary scenes, so its topic can return |
| Replying to a resident | That resident speaks first in the first response 70%† of the time |
| Pending responses | Responses are scheduled for at most your 3 latest posts†; a fourth post drops the oldest schedule |
| Names you bring up | Real-world names in your posts (what you study, a comic you read) are kept for the town's life. Residents may talk about them, a resident may take one up as their own interest, and a new resident may be seeded from one |
| Editing, deleting, mentions | Not in this version (§2) |

#### Edge Cases
- **Your post keeps being refused by the model's guardrails:** it simply gets no
  response — nothing is shown — and it is left out of later scenes so the town never
  stalls on it (§3.11).
- **You post while responses to an earlier post are pending:** both schedules run; see
  the cap above.

### 3.6 Events and moves

#### Overview
- **Purpose:** keep the town changing even when nobody talks about anything new.
- **Access:** events and moves appear as their own lines in the timeline and feed the
  status line.

#### Specifications

| Item | Specification |
|------|---------------|
| Event source | A table of event kinds shipped with the app (weather turns, a shop opens, a festival, a lost pet, road works, a visitor, a power cut, …) |
| Frequency | A new event about every 3 hours† of running time, at random |
| Duration | 1–12 hours† of town time, by kind; at most 2† ongoing at once |
| An event | A kind, a one-line description, a start, an end |
| After it ends | It stays in the log as part of the town's history |
| Population | Starts at 3; stays between 3 and 10†; drifts at random, about one move per 1–2 days† of running time; move-ins likelier near the minimum, move-outs near the maximum |
| A newcomer | Invented by the model from random axes (as in §3.1), never repeating a current or past resident; may be seeded from a name you brought up |
| A departure | The resident stops posting; their posts stay; they are remembered as a past resident so no one like them is invented again |
| On the timeline | A move is an event line; residents talk about it in the scenes that follow |

### 3.7 When the town runs

#### Overview
- **Purpose:** run while you could be looking, rest otherwise, and make the rest feel
  like time passed.
- **Access:** automatic; one setting (§3.10).

#### Specifications

| Item | Specification |
|------|---------------|
| Runs | While its window is visible on screen — including when another app is active and the window sits on another display or beside your work |
| Setting | "Keep the town moving while I use other apps" — on by default; off means it runs only while its window is the active one |
| Stops | When the window is not visible (minimized, on another Space, completely covered, screen locked, display asleep), when the Mac sleeps, when the app quits, and — with the setting off — when another app is active. Town time stops with it |
| Closing the window | Quits the app (one window, nothing to keep running) |
| Catch-up size | After a pause of length *t*: min(⌊*t* ÷ (4 × scene interval)⌋, 5)† scenes; responses to your posts that fell due during the pause come first and count toward the cap |
| Catch-up news | After a pause of 2 hours† or more, at most 1 new event and 1 move† |
| Catch-up time | Catch-up posts carry times spread across the pause, so they read as having happened while you were away |
| Short pauses | Under 4 scene intervals nothing is invented; the overdue scene simply runs |

Worked out at Normal: away 30 minutes → 1 scene; away 2 hours or overnight → 5 scenes,
at most about 15 posts.

#### Edge Cases
- **Visible but paused** (the setting is off and another app is active): the window
  shows that the town is resting; how is settled in the UX stage.
- **The clock jumped backwards:** the pause counts as zero.
- **Weeks away:** the cap holds; the town never floods you.
- **How catch-up looks while it is being written:** settled in the UX stage (no
  "processing" display either way).

### 3.8 The town's log

#### Overview
- **Purpose:** keep the town's history on this Mac and let you scroll back through it.
- **Access:** scrolling the timeline.

#### Specifications

| Item | Specification |
|------|---------------|
| Kept | Every post (theirs and yours), event, and move, for the town's whole life |
| Scrolling back | Through the whole history, older entries loaded on demand |
| Volume | Fast, 8 hours a day ≈ 1,000 posts a day; the timeline stays responsive with 100,000+ posts |
| What residents remember | Only what each scene is given: the recent posts that fit the model's context, from roughly the last 24 hours†; ongoing events; resident profiles (including interests they took up); and relevant names you brought up. Nothing older — long-term memory is Later |
| The log and the model | The log is the source of truth; every scene starts a fresh model session built from it, and the session is thrown away |

### 3.9 Moving to another town

#### Overview
- **Purpose:** start over when you do not like the town you got.
- **Access:** Settings → "Move to another town…".

#### Specifications

| Item | Specification |
|------|---------------|
| Confirmation | States that the current town — residents, posts, events, and the names you brought up — is deleted and cannot be restored |
| On confirm | Everything of the current town is deleted, then a new town is founded as in §3.1 with the current display name |
| Old towns | Not kept; there is always exactly one town |

#### Edge Cases
- **The model is unavailable:** moving is disabled, since the old town would be deleted
  with no way to found a new one.

### 3.10 Settings

| Setting | Values | Default | Notes |
|------|---------------|---------|-------|
| Display name | 1–20 characters† | chosen at first run | A change shows everywhere in the UI; what residents already wrote stays as written |
| Speed | Slow, Normal, Fast | Normal | §3.4 |
| Keep the town moving while I use other apps | On, Off | On | §3.7 |
| Move to another town… | — | — | §3.9 |

### 3.11 Writing scenes with the on-device model

#### Overview
- **Purpose:** the rules that keep generation invisible, safe, and never stuck.
- **Access:** none — this is behavior.

#### Specifications

| Item | Specification |
|------|---------------|
| What the model does | Writes text only: scenes, and the invented town, residents, and event descriptions. Timing, speakers, seeds, events, moves, delays, influence, and catch-up are all decided by rules |
| Output | Structured output (a declared schema) for every call: posts with speaker and reply target, topic tags |
| Guardrails | Apple's default level. A refused call is dropped and retried with a different seed, up to 2 times† per turn, then the turn is skipped. The permissive level is not used — it does not apply to structured output |
| Never stuck | Something that keeps causing refusals — 3 in a row† with it in the context — is left out of later contexts |
| Context budget | Read from the model at run time (Apple documents 4,096 tokens; 8,192 has been observed on macOS 27). The prompt is assembled to fit, trimming recent posts first; if the model still reports an overflow, retry once with half as many posts |
| One at a time | Ordinary scenes, responses, and catch-up are written one after another, never in parallel |
| Heat | While the Mac reports a serious or critical thermal state, no scene is written; the town just seems quieter |
| Other failures | The turn is skipped and the next one tries again |
| Unavailable model | Device not eligible, Apple Intelligence turned off, or the model still downloading: the town does not run, the timeline stays readable, and the window says what is missing and how to fix it (a link to the Apple Intelligence settings where that applies). Checked again whenever the window becomes active |

### 3.12 Resident profiles

#### Overview
- **Purpose:** tell who is who in a town made only of text.
- **Access:** pointing at or clicking a resident's name anywhere in the timeline.

#### Specifications

| Item | Specification |
|------|---------------|
| Shows | Name, occupation, hobby, current worry, personality, relationships to other residents, interests taken up from names you brought up, when they moved in |
| Past residents | Marked as moved out, with when |
| Editing | None — residents are never curated (§2) |
| Your own name | Opens nothing in this version |

## 4. Cross-cutting rules

- **Local only.** No network access; all data stays in the app's container on this Mac.
- **Private by construction.** Your posts and all generated text never reach system
  logs, crash reports, or analytics; there are none of the latter.
- **Not a chat.** No instant replies, no typing or "generating" indicators, no read
  receipts; posts appear when they appear.
- **Nothing pulls you back.** No notifications, badges, sounds, or streaks (§2).
- **English only.** The UI and everything the town writes are in English; there is no
  language setting.

## 5. Data

All of it lives in the app's own container on this Mac. A town's data lives as long as
the town and is deleted when you move away (§3.9); removing the app leaves the container
in place, as macOS does. The stored format is versioned, and a format change ships with
a migration ([`docs/architecture.md` › Persistence](../architecture.md#persistence)
decides the store).

| Entity | Fields (limits) |
|------|---------------|
| Town | name (≤ 30), setting (≤ 400), places (3–5, each ≤ 30), founded at |
| Resident | name (≤ 20), age group, occupation, hobby, worry, personality, relationships (0–3: another resident + a one-line description), interests taken up (0–5), status (living here / moved out), moved in at, moved out at |
| Post | author (a resident or you), text (≤ 280; yours ≤ 140), reply target (optional), topic tags (0–3, each ≤ 40), origin (ordinary / response / catch-up / event), happened at |
| Event | kind, description (≤ 120), starts at, ends at, status (ongoing / ended), related resident (optional) — moves are events too |
| Interest (a name you brought up) | term (≤ 40), first mentioned at, last mentioned at, mentions, source posts |
| Schedule | next ordinary scene due, pending responses (post, due at), when the town last ran |
| Settings | display name, speed, keep moving while in other apps |

## 6. Open questions

- **Deferred by the owner:** this version is not distributed; the Mac App Store or a
  signed and notarized DMG is chosen when a release is wanted — if the store,
  "Townsfolk" must also be free as a store name
  ([`docs/architecture.md` › Distribution](../architecture.md#distribution)).
- **Deferred by the owner:** if the app is shared with others, how it stands against the
  Foundation Models acceptable-use requirement that forbids enabling dependency or
  spiraling interactions harmful to mental health. The non-goals in §2 keep it clear of
  engagement hooks; the owner judges it from their own use before anything is shared
  ([`docs/architecture.md` › Distribution](../architecture.md#distribution)).
- **Unknowable until shared:** whether anyone but the owner finds it fun.
- **Settled in use** (starting values above): the three speeds and the heat they cause;
  catch-up size and how it looks; how strong your influence feels and the balance of
  your topics against others; population bounds and move odds; the format, size, and
  growth of the event and resident-axis lists, and how residents are kept from
  repeating; status-line overflow; the shape of the store of names you bring up;
  whether a small model keeps the town fresh for days; how much residents may
  confidently get wrong about real names you bring up (no limit was set); the quality of
  the writing; whether text works at a glance at all.
- **Read at run time / confirmed during implementation:** the context size on the
  owner's Mac (M2, 16 GB, macOS 27.0); whether only the smaller on-device model is
  available on it. The macOS floor is 27.0
  ([`docs/architecture.md` › macOS floor](../architecture.md#macos-floor)).
- **Known gap:** a single mistaken post cannot be removed without moving away (deleting
  is Later).

## 7. Decision log

Decided before this repository existed (2026-09-30):

- 2026-09-30 A town that lives on its own, which you watch at the edge of the screen and
  join as a resident (rejected: a social feed of peers growing alongside you, because it
  judges itself by motivation and becomes a productivity tool; a watch-only diorama,
  because joining is the point)
- 2026-09-30 The goal is fun, not usefulness; success is judged by use and nothing is
  measured (rejected: making "my topic came back later" the bar, because a small model
  with a short memory produces it least reliably)
- 2026-09-30 Glances of seconds and visits of 1–3 minutes, with Slow / Normal / Fast;
  heat and battery accepted (rejected: a digest read once in the morning or evening,
  because the town would stop feeling alive)
- 2026-09-30 You post as a resident with a slightly stronger, hidden influence; the
  balance between your topics and others is random (rejected: a pure spectator; a status
  the town lightly reacts to)
- 2026-09-30 Every response is delayed by minutes to tens of minutes (rejected: the first
  reply instant, because it needs a second generation path; several instant replies,
  because it becomes a chat)
- 2026-09-30 Out of sight means stopped, with a modest catch-up (rejected: frozen with no
  catch-up; a menu-bar agent running all day, because of heat while unwatched)
- 2026-09-30 A timeline plus a status line for glancing, text only (rejected: timeline
  only, because a glance would show only "something changed"; a roster with the speaker
  highlighted — kept as Later)
- 2026-09-30 The time of day is ignored (rejected: quiet nights synced to the clock; a
  faster town clock, because your "today I'll do X" would drift from the town's day)
- 2026-09-30 Swift and SwiftUI on this template, Foundation Models called directly, a
  signed and notarized DMG assumed (rejected: Rust and Tauri driving the `fm` command,
  because structured output through it is unverified and cross-platform buys nothing on
  Apple's model; Python with a local web UI, because it makes a weak desktop app)
- 2026-09-30 Topics are seeded by resident profiles and by events injected by rules
  (rejected: profiles alone, because a small model circles back to the same talk; only
  your posts, because the town would stall on days you post nothing)
- 2026-09-30 The town stays fictional: residents never raise real-world names on their
  own, but may pick up and keep the ones you bring up (rejected: free talk about the
  real world, because a small model invents facts; forbidding the names you bring up,
  because a resident studying what you study is part of the fun)
- 2026-09-30 A fixed workflow, not an agent: the model only writes text, one scene
  (1–3 posts) per call in structured output; the status line comes from tags and event
  state; no daily summary call (rejected: one call per post; one call per half hour;
  a separate summary call; a free-running agent per resident)
- 2026-09-30 The town and its residents are invented by the model from randomly combined
  axes, with no curation (rejected: a hand-written roster, because it runs out and every
  town looks the same)
- 2026-09-30 Default guardrails with structured output; a refused scene is silently
  replaced (rejected: the permissive level, because it does not apply to structured
  output; plain text parsed by hand, because a small model breaks formats)
- 2026-09-30 What only running can tell — heat at Fast, consistency across days, how
  often refusals happen — is noticed in use, not measured by a planned procedure
- 2026-09-30 First run asks for your display name only (rejected: choosing the town's
  mood, because it needs a hand-made list; asking nothing, because a model-chosen name
  for you feels wrong)

Decided in the kickoff hearing:

- 2026-09-30 The name is Townsfolk (rejected: Living Town, Hamlet)
- 2026-09-30 The town runs while its window is visible, even when another app is active;
  a setting limits it to while the window is active (rejected: running while covered,
  because of heat while unseen; a separate pause button)
- 2026-09-30 Your post is new or a reply (rejected for this version: deleting and
  `@mentions` — Later; editing — a non-goal)
- 2026-09-30 Moving away deletes the old town after a confirmation (rejected: a
  read-only archive; switching between several towns)
- 2026-09-30 No always-on-top, every-Space, launch at login, or global shortcut in this
  version (the owner does not want them)
- 2026-09-30 Resident profiles are in the MVP. Likes (residents' and yours) were chosen,
  then moved to Later the same day: added when wanted
- 2026-09-30 Searching, filtering, bookmarking, and exporting the log are non-goals: the
  town takes a social feed's look, not its conveniences (rejected: search as Later)
- 2026-09-30 Signed off by the owner

Decided by the owner after the kickoff:

- 2026-10-06 English only, with no language setting
