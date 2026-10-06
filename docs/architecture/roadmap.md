# Roadmap

This page records the app's direction: the outcomes it is working toward now, the ones
that come next, and the ones only intended for later. It sits between two other homes
and repeats neither:

- `AGENTS.md`'s `## Product` says what the app is, its core interaction, and its
  non-goals. Nothing here contradicts a non-goal; moving one is the owner's call, made
  in that section first.
- The issue tracker holds the units of work, their priority tiers, and their `blocked:`
  and `on hold` labels (`triaging-issues`). This page links issues by number and never
  copies their bodies.

It records direction and authorizes nothing. An issue is implemented because it is
filed, tiered, and picked, never because a line here names it. It records no decision
either: a hard-to-reverse choice a line depends on is recorded in
[`docs/architecture.md` › Townsfolk on these layers](../architecture.md#decisions) and
linked from here. What has shipped is in `CHANGELOG.md`, not on this page.

The owner decides what the page says; an agent proposes a change to it in a pull
request, and the change lands only once the owner has approved it.

- **Last reviewed:** 2026-09-30

## Now

The outcomes being worked on, one to three of them. Each has its issues filed.

- **A town that lives on its own** — the core interaction: if a glance does not show a
  living town, nothing else matters. First run founds a town, its residents write scenes
  on their own, and the status line, events and moves, and resident profiles show what
  is going on. Issues: tracked in #2. Done when: a fresh install on an Apple
  Intelligence Mac founds a town, and the window left visible at Fast gains a scene about
  every minute, with nothing shown while one is being written.
- **Joining the town** — you take part as one of the residents: your posts and replies,
  and the town answering minutes later. Issues: tracked in #3. Done when: a post at Fast
  draws a group quoting it minutes later, never within seconds.
- **A town that rests and remembers** — it runs only while you could be looking and keeps
  its history: running only while visible, catching up after a pause, the log surviving
  a relaunch, Settings, and moving to another town. Issues: tracked in #4. Done when:
  after 30 minutes or more hidden at Normal, "While you were away" appears, and a
  relaunch keeps the whole history.

## Next

The outcomes that follow once Now's are done. An issue may already exist for one, often
parked as `on hold`; none is required.

- **Screenshot input** — hand the town a screenshot of what you are doing, and related
  topics or residents appear; expected to become the owner's main way of posting, so it
  comes first after this version. Before it moves up: a spike on the on-device model's
  image understanding and token cost, then the new input recorded in
  `docs/architecture.md` — with the Screen Recording permission recorded too if it would
  capture the screen rather than take an image you hand it.

## Later

Direction the app intends to take but has not ordered. No issue is filed for a line
here, apart from a parked one that a line names.

- **A visual identity for residents** — animals living like people, told apart at a
  glance. Brought forward once text alone has shown whether the town is alive.
- **Residents' long-term memory** — remembering events from days ago. Brought forward if
  the town grows stale within days.
- **Outside information** — topics from RSS or similar, and a topic preference. It needs
  network access, a non-goal in this version: a `## Product` change first, then a change
  to [Sandbox posture](../architecture.md#sandbox-posture).
- **Richer residents and staging** — deeper characters, and move-in and move-out scenes
  beyond a timeline line. Brought forward if the town feels thin in use.
- **A resident roster view** — residents side by side, the current speaker highlighted.
  Brought forward if the timeline and the status line are not enough at a glance.
- **External integrations** — residents searching the web through MCP or an API key,
  with a monthly cap. Needs network access, as outside information does, and a recorded
  decision on handling the key.
- **Residents raising real-world topics** — needs outside information first, so their
  talk is not confidently stale.
- **Deleting your own post** — brought forward if a mistaken post that only moving away
  can remove becomes a real problem.
- **Mentioning a resident (`@name`)** — waits because it pulls the feed toward a chat.
- **Likes** — residents' and yours; added when the owner wants them.
- **Others can install it** — the owner's own-use judgment on the Foundation Models
  acceptable-use requirement, then a release issue that updates
  [Distribution](../architecture.md#distribution).
