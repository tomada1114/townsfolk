# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Residents can talk about their stored relationships as ordinary scene seeds, with
  both residents speaking when they still live in town. Past residents remain named
  in relationship seeds without returning as speakers.

### Added

- Initial project scaffold from [macos-app-template](https://github.com/tomada1114/macos-app-template)
- Settings (⌘,) holds your name, the town's speed, and whether the town keeps moving
  while you use other apps; every change applies at once with no Save button, and a
  name outside 1–20 characters is kept in the field with "Use 1–20 characters." under it
- When Apple Intelligence is off, its model is still downloading, or this Mac cannot run
  it, a full-window message and a banner say what is missing — with an Open System
  Settings button when Apple Intelligence is off — and check again whenever the window
  becomes active
- The town's timeline, ready for the town window to show: posts newest first, one
  conversation per group joined by a thread line, a one-line quote above a reply to an
  older post, your posts marked "(you)", event rows with their symbol, relative times
  refreshed every minute, a scene's posts appearing one at a time on a fading Lamplight
  wash, a "↑ n new posts" pill while you read older posts, older posts loading as you
  scroll, ↑ and ↓ to move between posts, and a Town menu with Scroll to Latest (⌘↑)
- The first-run screens, ready for the town window to show: "A small town is waiting
  for you." asks only for your name — Continue stays disabled until it is 1–20
  characters, with "{n} over" past the limit — then "Finding you a town…" checks off
  Drawing the streets, Meeting the neighbors, and Saying hello as the town is really
  founded, adds "This is taking longer than usual." after a minute, offers Try Again
  after "Couldn't find you a town this time.", and announces "You moved to {town}." to
  VoiceOver; a name already chosen before the app quit mid-founding goes straight to
  founding
- The composer, ready for the town window to show: post one line as yourself, new or in
  reply to any post through its ↩ Reply button or Town › Reply (⌘R), with Town › New
  Post (⌘N) to start typing, Return to post, and Esc to cancel a reply and then leave
  the field. Pasted line breaks become spaces, a counter appears once 20 characters
  remain ("12 left", "3 over"), and your post shows at once at the top of the timeline,
  scrolling back up to it if you were reading older posts
- Resident profiles, ready for the town window to show: click a resident's name in a
  post, or select their post and choose Town › Show Profile (⌘I), to see who they are —
  occupation and age, personality, hobby, worry, whom they know, the names they took up
  from you, and when they moved in or out — in a read-only popover that Esc or a click
  outside closes; your own name opens nothing
- Things happen in town: about every three hours of running time an event starts — a
  turn in the weather, a festival, a lost pet — and lasts one to twelve hours, at most
  two at once, with residents talking about it while it goes on; and about once every
  one to two days of running time someone moves in or away, keeping the town between 3
  and 10 residents, each move a "Ren moved in." or "Jun moved away." row that the next
  scene talks about. Nothing is drawn while the Mac runs hot or the model is unavailable
- The status line, ready for the town window to show above the composer: one line
  saying what is going on — an ongoing event with its symbol, then the latest topic
  ("Rain since noon · the bakery's new bread"), "Everyone's talking about …", or "A quiet
  day in …" — cut at the tail when the window is narrow, crossfading when it changes,
  and read in full by VoiceOver as "Town status"

### Changed

- Scene prompts keep an existing period, exclamation mark, or question mark at the end
  of a resident's worry without adding another period
- Requires macOS 27.0 or later; building from source requires Xcode 27
- The town window and the Settings window replace the example counter: one window
  titled "Townsfolk" that opens at 380 × 680 pt, stops shrinking at 320 × 440 pt, and
  quits the app when it closes, and an empty Settings pane that ⌘, opens

[Unreleased]: https://github.com/tomada1114/townsfolk/commits/main
