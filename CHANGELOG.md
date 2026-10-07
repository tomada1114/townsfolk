# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial project scaffold from [macos-app-template](https://github.com/tomada1114/macos-app-template)
- Settings (⌘,) holds your name, the town's speed, and whether the town keeps moving
  while you use other apps; every change applies at once with no Save button, and a
  name outside 1–20 characters is kept in the field with "Use 1–20 characters." under it
- The town's timeline, ready for the town window to show: posts newest first, one
  conversation per group joined by a thread line, a one-line quote above a reply to an
  older post, your posts marked "(you)", event rows with their symbol, relative times
  refreshed every minute, a scene's posts appearing one at a time on a fading Lamplight
  wash, a "↑ n new posts" pill while you read older posts, older posts loading as you
  scroll, ↑ and ↓ to move between posts, and a Town menu with Scroll to Latest (⌘↑)

### Changed

- Requires macOS 27.0 or later; building from source requires Xcode 27
- The town window and the Settings window replace the example counter: one window
  titled "Townsfolk" that opens at 380 × 680 pt, stops shrinking at 320 × 440 pt, and
  quits the app when it closes, and an empty Settings pane that ⌘, opens

[Unreleased]: https://github.com/tomada1114/townsfolk/commits/main
