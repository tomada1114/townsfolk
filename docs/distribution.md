# Distribution & Signing

## Release flow

Pushing a tag `v*` that matches `MARKETING_VERSION` in `project.yml` triggers
`.github/workflows/release.yml`:

1. Re-run tests, the coverage gate, and a build (never ship unverified code)
2. Build Release and sign — **Developer ID if secrets are configured, ad-hoc
   otherwise** (with a loud notice)
3. Package a DMG (`scripts/package_dmg.sh`, plain `hdiutil` — no dependencies)
4. Notarize + staple — again secret-gated, skipped with a notice otherwise
5. Attest build provenance (`actions/attest-build-provenance`)
6. Create the GitHub Release with generated notes and the DMG attached

Bump `MARKETING_VERSION` first; the workflow fails loudly if the tag and the
project version disagree.

### Preparing the version bump

`just release-prep <version>` (`scripts/release-prep.sh`) makes the edits a
release needs before its tag exists, and checks them while that is still cheap —
the tag/version disagreement above is only reported once the tag is pushed:

- `project.yml`: `MARKETING_VERSION` becomes `<version>` and
  `CURRENT_PROJECT_VERSION` is incremented.
- `CHANGELOG.md`: the `[Unreleased]` entries move under
  `## [<version>] - <date>`, leaving a fresh empty `[Unreleased]`, plus a
  `[<version>]:` release-tag link reference beside the `[Unreleased]:` one — and
  when that one is a `…/compare/<range>` URL, its range moves on to
  `v<version>...HEAD`. An `[Unreleased]:` line of any other shape is left alone.

It refuses a version that is not above the current one (compared component by
component, so 1.10.0 follows 1.9.0), a work tree with uncommitted changes, and an
empty `[Unreleased]`. `--dry-run` runs every one of those checks and writes
nothing. It creates no commit, tag, or push — those stay human actions
(`AGENTS.md`'s "Security and human approval") — and prints them in order:

```bash
just release-prep 0.2.0            # writes project.yml and CHANGELOG.md only
git switch -c release/0.2.0
git add project.yml CHANGELOG.md
git commit -m 'chore(release): 0.2.0'
gh pr create --fill
# then, once that pull request is merged into main:
git switch main && git pull
git tag v0.2.0
git push origin v0.2.0             # pushing the tag is what starts the release
```

## Required secrets for trusted distribution

All optional — without them you still get an ad-hoc-signed DMG.

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Base64-encoded "Developer ID Application" certificate + private key (.p12) |
| `DEVELOPER_ID_CERT_PASSWORD` | Password protecting that .p12 |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | 10-character team identifier |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for `notarytool` (create at appleid.apple.com) |

Signing and notarization require a paid
[Apple Developer Program](https://developer.apple.com/programs/) membership
($99/year).

The three `APPLE_*` secrets only take effect when the `DEVELOPER_ID_*` pair
is also configured — Apple's notary service always rejects ad-hoc-signed
submissions, so the workflow skips notarization (with a warning) rather than
submit one.

## The unsigned-build caveat (be honest with your users)

On Apple Silicon everything is at least ad-hoc signed, but a **downloaded**
app that is not Developer-ID-signed *and* notarized is blocked by Gatekeeper —
and since macOS 15 the Control-click → Open bypass is gone. Users of unsigned
builds must clear quarantine manually:

```bash
xattr -dr com.apple.quarantine /Applications/Townsfolk.app
```

Document this in your release notes, or better, configure the secrets above.

## Sandboxed or not

`App/Townsfolk.entitlements` ships with `com.apple.security.app-sandbox` set to
`true`, and that is the right default: it is what the Mac App Store requires,
and it keeps a bug in the app from reaching the rest of the user's machine.
Some apps cannot keep it. Decide this before the first feature — the decision
shapes which distribution channels stay open — and because turning it off
widens what the app may do to the user's machine, it needs a human's sign-off
(`AGENTS.md`'s "Security and human approval" covers the entitlements file).

### What forces the sandbox off

There is no entitlement that buys these back. Inside a container they fail at
runtime, so an app that needs one is unsandboxed or it does not ship:

- **Controlling other apps through the Accessibility API** — `AXUIElement*`
  calls that read or move another application's windows. `AXIsProcessTrusted()`
  is never granted to a sandboxed process.
- **Posting synthesized input** — `CGEvent.post`, whether to drive another app
  or to fake a keystroke system-wide.
- **Global event taps** — `CGEvent.tapCreate` on `.cghidEventTap`, the usual
  way a utility watches for a hotkey while another app is frontmost.
- **Arbitrary file access** — reading `~/.ssh/config`, a dotfile, or any path
  the user did not hand over through an open panel. A sandboxed app can still
  reach a user-picked file, and keep reaching it across launches through a
  security-scoped bookmark; it cannot go looking on its own.

Plenty of privileged-looking work does *not* require dropping it: automating
another app through Apple Events (the
`com.apple.security.automation.apple-events` entitlement), outbound network
access, and screen capture all work sandboxed with the right entitlement and
the user's consent.

### What stays on regardless

- **Hardened Runtime** — `ENABLE_HARDENED_RUNTIME: YES` in `project.yml` is a
  separate mechanism from the sandbox, and notarization requires it either way.
- **Developer ID signing and notarization** — neither cares whether the app is
  sandboxed. Both signing paths in the release workflow carry whatever the
  entitlements file says: with the Developer ID secrets it re-signs with
  `codesign --options runtime --entitlements App/Townsfolk.entitlements`; without
  them it keeps the ad-hoc signature `xcodebuild` already applied, which
  `project.yml` builds from the same file (`CODE_SIGN_IDENTITY: "-"` and
  `CODE_SIGN_ENTITLEMENTS` on the Release configuration). Either way the
  workflow then runs `codesign -d --entitlements -` on the app and fails unless
  it shows `com.apple.security.app-sandbox` — so turning the sandbox off also
  means changing that release step.
- **Every local and CI gate** — nothing in `just check`, `just smoke`, or CI
  reads the entitlements file, so flipping the key changes no check there; only
  the release workflow's entitlements step (above) notices.

### What it costs

- **The Mac App Store is out.** The sandbox is a hard store requirement, so an
  unsandboxed app ships only through direct distribution — which is what this
  template builds anyway (see "Future steps" below).
- **Every permission becomes the user's problem.** Accessibility, Input
  Monitoring, and Screen Recording are granted only in System Settings ›
  Privacy & Security, one toggle at a time, and macOS re-prompts after the app
  is re-signed with a different identity. Budget the onboarding screen that
  explains it.

### The usage-description keys

`project.yml` sets `GENERATE_INFOPLIST_FILE: YES`, so there is no `Info.plist`
to hand-edit: a privacy string is an `INFOPLIST_KEY_NS…UsageDescription` build
setting on the `Townsfolk` target (`project.yml` declares none yet).

```yaml
targets:
  Townsfolk:
    settings:
      base:
        INFOPLIST_KEY_NSAppleEventsUsageDescription: "Townsfolk asks Finder to reveal the file you picked."
```

A TCC-gated API whose key is missing does not fall back to an error — the
system terminates the process at the moment of the call, so the failure shows
up at launch, never at build time. The keys these apps reach for most often:

| What the app does | Key |
|---|---|
| Automates another app (Apple Events) | `NSAppleEventsUsageDescription` |
| Reads the Desktop, Documents, or Downloads folder | `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription` |
| Reads removable or network volumes | `NSRemovableVolumeUsageDescription`, `NSNetworkVolumesUsageDescription` |
| Camera or microphone | `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` |
| Calendars, Contacts, Reminders, Photos | `NSCalendarsFullAccessUsageDescription`, `NSContactsUsageDescription`, `NSRemindersFullAccessUsageDescription`, `NSPhotoLibraryUsageDescription` |
| Accessibility, Input Monitoring, Screen Recording | none — no key exists; prompt with the API's own trust check and send the user to System Settings |

## Future steps (deliberately out of template scope)

- **Homebrew cask**: as of Homebrew 5.0 (2026), unsigned/un-notarized casks
  are removed from homebrew/cask — notarization is a hard prerequisite.
- **Sparkle**: in-app updates for direct distribution; add it only when users
  ask, and sign your appcast (see
  [Sparkle's documentation](https://sparkle-project.org/documentation/)).
- **Mac App Store**: a different signing/provisioning pipeline entirely; this
  template targets direct distribution via GitHub Releases. It also requires
  the App Sandbox, which "Sandboxed or not" above says some apps cannot keep.
