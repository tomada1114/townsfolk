---
name: running-the-app
description: >
  Covers running this app to see a change working: just run to launch the fresh Debug
  build, confirming the running process really is that build, reading its unified-log
  output with just logs and log show, taking a screenshot of the app window or the whole
  screen with screencapture, driving a flow with a throwaway XCUITest under just uitest,
  putting the app in a known state with launch arguments or environment variables, and
  just test-local and just reset-permissions. Use when asked to run the app, to launch
  or start it, or to screenshot it, when a change has to be verified in the real app
  rather than in tests, when the app must be observed with no human at the keyboard,
  when a TCC permission prompt or a System Settings step needs a human hand-off, or
  when deciding what evidence a pull request carries for behavior no CI job can assert.
---

# Running the App

**Owns:** launching this app to observe a change, reading what it emits, and the
hand-off to a human when macOS demands one. **Does not own:** whether a behavior
belongs in a test at all (`.claude/rules/testing.md`, `tdd`); how an OS integration is
structured behind a port (`integrating-system-apis`); what a pull request looks like
(`create-pr`); which document a change owes (`updating-docs`).

Running the app proves wiring, not logic. Every decision this app makes is owned by
`TownsfolkCore` and gated by `just test`; `just build`, `just uitest`, and `just smoke`
prove it compiles, launches, and stays alive. What none of them shows is the thing a
person actually sees — the view that renders nothing, the adapter that returns an empty
answer because macOS withheld a grant, the log line that never fires. That is what
launching is for, and its result is evidence in the pull request, never a substitute for
a test.

## Ask before taking over the Mac

Launching the app, a throwaway XCUITest, `just uitest`, `just smoke`, and
`just test-local` all take over the owner's screen and keyboard. Batch them at the end of
the work, and ask the owner in chat before running them ("May I launch the app now?").
When one is needed partway through, stop there and ask rather than running it. Every
check that leaves the screen alone — `just test`, `just build`, `just lint`, `just check`
— needs no such ask.

## Launch the build you just made

```bash
just run      # just build, then scripts/run-app.sh
```

`scripts/run-app.sh` quits every running process whose bundle declares this app's
identifier — read from `project.yml` by `scripts/bundle-id.sh`, never hard-coded — waits
up to 10 seconds for them to go, then `open`s
`build/dev-derived-data/Build/Products/Debug/Townsfolk.app` and prints the new pid. The quit
step is the point: a bare `open` on an already-running app only activates the old
process, so you would be watching the previous build with no signal that anything went
wrong. A survivor of the SIGTERM is reported, never force-killed — the failure names the
pid and leaves the decision to you.

Confirm the process really is the build you just made, before trusting anything you see:

```bash
pid=$(pgrep -f 'Debug/Townsfolk.app/Contents/MacOS/Townsfolk' | head -1)
ps -o pid=,lstart=,comm= -p "$pid"
stat -f '%Sm %N' build/dev-derived-data/Build/Products/Debug/Townsfolk.app/Contents/MacOS/Townsfolk
```

Two things have to hold: the executable path is *this* checkout's (another worktree or
clone of the same app carries the same bundle identifier, and its process looks
identical in every other respect), and the process start time is later than the
binary's mtime. `lsappinfo info -only bundlepath "$pid"` answers the same first question
from Launch Services if you prefer it.

Quit it when you are done — leaving a build running behind you is how the next run ends
up watching a stale window:

```bash
kill -TERM "$pid"    # the pid you verified above — never pkill -f on the path
```

A `pkill -f` on the executable path would also hit the same app launched from another
worktree or clone, and an instance an in-flight `xcodebuild test` is driving under
XCUITest; the pid you just checked is the only one this run owns.

Prefer that to `osascript -e 'quit app id "…"'`: driving another app through AppleScript
is itself TCC-gated (Automation) and prompts a human the first time.

## Read what it says

Shipped code logs through `os.Logger`, never `print`
(`Packages/TownsfolkKit/Sources/TownsfolkCore/AppLog.swift`; `.swiftlint.yml`'s
`no_print_in_sources`), because a `.app` launched the way users launch it has nowhere to
send stdout. `AppLog` declares one subsystem — the bundle identifier — and one logger
per concern, named for the concern (`presence`), which is what makes a stream
narrowable to one story:

```bash
just logs   # log stream --predicate 'subsystem == "<bundle id>"' --level debug
/usr/bin/log stream --level debug --style compact \
  --predicate 'subsystem == "io.github.tomada1114.Townsfolk" AND category == "presence"'
```

Four things cost time if you guess them:

- **`just logs` streams until Ctrl-C**, which an agent cannot send. Redirect a
  background stream to a file, do the thing, then kill the stream — and do not pipe it
  into `head`, whose block-buffered pipe shows nothing at all for the first few
  kilobytes.
- **`log show --last 2m` is not the bounded equivalent.** `.debug` and `.info` messages
  live in memory, not in the persisted store, so `log show --last 5m --predicate
  'subsystem == "…"' --debug --info` prints an empty table even for lines a stream was
  catching a second earlier. It reaches `.notice` and above only.
- **Anything user-derived is redacted.** `<private>` in the output is the design
  (`.claude/rules/swift.md` › Logging asks for it), not a bug. Assert on the public half
  of the line — that the event happened, a state such as `presence`'s `visible=true` —
  instead of turning private data on.
- **`log` is a zsh builtin**, so an interactive shell answers `log: too many arguments`.
  Spell it `/usr/bin/log` outside a `just` recipe.

## See it without a human at the keyboard

[references/observing-behavior.md](references/observing-behavior.md) has the verified
recipes: `screencapture` of the app window or the whole screen, a throwaway XCUITest
that drives a flow and attaches a screenshot, and putting the app into a known state
with launch arguments or environment variables.

## Where a human is unavoidable — ask once, up front

macOS deliberately makes some steps unautomatable, and every one of them blocks an
otherwise unattended run:

- **The first TCC prompt** for Accessibility, Input Monitoring, Screen Recording, or
  Automation. The prompt is a system-owned modal, and synthesizing a click on it is
  itself gated by the grant it is asking for.
- **Anything in System Settings › Privacy & Security**, including granting the *test
  runner's* launcher — your terminal, or Xcode — what `just test-local` needs (see the
  `test-local` recipe's comment in the `justfile`: a test process inherits its
  launcher's grants and never gets its own).
- **The keychain "wants to sign using key …" dialog** on the first Debug build that
  signs with a real identity, which otherwise hangs an unattended build forever
  (`docs/getting-started.md` › Keeping Permission Grants Across Rebuilds).

Ask for all of them **once, in a single message, before the loop starts** — every grant,
every settings pane, in the order to do them, plus the one command that shows the grant
took. Asking per iteration is what turns a five-minute verification into an afternoon.
Then make the grant last: a Debug build signed ad hoc is a new app to TCC on every
rebuild, so the grant you were just given dies at the next `just run` unless
`Config/Local.xcconfig` gives the build a stable identity. When a grant looks stale, or
you switched signing, `just reset-permissions` drops every recorded decision for this
app — and only this app — so the next launch prompts from scratch.

## The evidence a pull request carries

No gate runs any of this, so the pull request is where it lands. State the exact command
you ran, not a paraphrase, and paste:

- **`just test-local` output** for any change under `Sources/TownsfolkPlatform/` — required
  by `AGENTS.md`'s Review Checklist, and the one thing CI reports as skipped rather than
  absent.
- **A log excerpt** (a few lines of the stream, with the predicate you used above them)
  for behavior whose only observable is a log line.
- **For anything a person looks at, a sentence, not a screenshot.** The owner does not
  want screenshots in pull requests (2026-10-06). Say what was checked and how — for
  example, a throwaway XCUITest that found each label by its text — and what it showed.
  A screenshot taken to look at the app yourself stays out of the pull request.

Never paste a Team ID, a signing identity, a certificate common name, or a personal
name: a pull request here, or in a repository cut from this template, may be public,
and `codesign`, `security`, and System Settings output all carry them. Redact before pasting, and say that you did.

Leave nothing behind: quit the app, remove any throwaway test file and re-run
`just generate`, and check `git status --porcelain` is empty. Build products under
`build/` are gitignored and can stay.
