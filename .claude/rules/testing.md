---
paths:
  - "Packages/**/Tests/**"
  - "LaunchUITests/**"
---

## Where a Test Goes

Three kinds of test, split by what is under test:

- **A decision → a Core test with a fake.** Anything that branches, clamps, formats, or
  remembers lives in `TownsfolkCore` and is tested in `Tests/TownsfolkCoreTests` against a fake
  of the port (see "Fakes, not mocks" below). These run in CI on every push and are what
  the 80% line- and 75% function-coverage floors measure. This is the default: if an adapter looks like it
  needs a test for a decision, move the decision into Core instead.
- **Translation to or from the OS → a local-machine test.** Whether `NSWorkspace`, an
  event tap, or the accessibility API really answers what the adapter assumes can only
  be checked against the real OS. Those tests live in `Tests/TownsfolkPlatformTests`, every
  suite carries the `.requiresLocalMachine` trait, and a human runs them with
  `just test-local`. CI cannot: a runner has no logged-in GUI session and cannot be
  granted Accessibility, Input Monitoring, or Screen Recording. So they are reported as
  **skipped** on every other run rather than quietly absent, and a pull request that
  changes an adapter pastes its `just test-local` output as the evidence no gate can
  produce.
- **What only the assembled `.app` shows → `LaunchUITests`.** The one XCTest target holds
  the launch guarantee: the app starts, shows its window (a status item, for a menu-bar
  agent), and one interaction round-trips through `App/`'s real wiring
  (`LaunchTests.swift`). A new test belongs there only when what it proves is that
  wiring — scene lifecycle, the composition root handing over the real adapter — and
  nothing smaller can fail for it. A decision is a Core test, a view is covered through
  its Core view model, and an adapter's translation is a local-machine test; a UI probe
  written to *see* a change is deleted before the pull request (the `running-the-app`
  skill). It waits on a predicate with a timeout (`waitForExistence`, `XCTWaiter`),
  never a fixed sleep.

A local-machine test never becomes the only test of a decision: it is human-run, so it
proves nothing about the pull request nobody ran it for. Adapters stay translation-only,
and outside the coverage floor, precisely so that stays true. When macOS withholds an
answer for lack of a grant it reports nothing rather than an error, so unwrap through
`LocalMachineTests.require(_:requires:grant:)` — its failure names the grant instead of
reading as a broken adapter.

## Framework and Structure

- Swift Testing only (`@Test`, `#expect`, `#require`, `@Suite`); XCTest is reserved for the
  XCUITest launch target in `LaunchUITests/`
- Use `@Test(arguments:)` for input/output variations; don't copy-paste test bodies
- Group related tests in a `@Suite`; annotate `@MainActor` suites that touch view models
- TDD is required: write the failing test first, then implement to green
- Plain `import TownsfolkCore`, never `@testable import`: a Core test exercises the public API
  the rest of the app calls, so an internal can be renamed without touching a test. A
  test that seems to need an internal is either testing a detail (test the behavior it
  produces) or has found a declaration another module legitimately needs — make that
  `package`, which every target in `Packages/TownsfolkKit` sees (`swift.md` › Access Control)

## What to Test

- Test *behavior and contracts*, not implementation details
- Always test the happy path AND the error path for every public API
- Error-path tests assert the thrown error's payload with `#expect(throws:)`, not just its type

## An Independent Oracle

The expected value comes from somewhere other than the code under test: a literal worked
out by hand, a case table in `@Test(arguments:)` pairing each input with its answer, or
an invariant that must hold whatever the input (the value stays inside `range`, a
round-trip returns what went in). Never compute it by calling the implementation, and
never re-derive it with the implementation's own formula: after `increment()` from 99,
`#expect(counter.value == min(99 + 1, counter.range.upperBound))` passes with any bug
the formula shares, where `#expect(counter.value == 100)` does not.

## Fakes, not mocks

A port declared in `TownsfolkCore` (a `Sendable` protocol whose adapter lives in
`TownsfolkPlatform`) is substituted in tests by a **fake**, never a mock. A fake is a real,
working implementation of the protocol that lives in `Tests/TownsfolkTestSupport`, answers
from data the test hands it, and records what it was asked in a plain value — a call
count, or the arguments it received — which the test reads afterwards with `#expect`.
It declares no expectations up front, verifies nothing itself, and needs no framework:
`FakeFrontmostAppProvider.swift` there is the worked example to copy. It is `package`,
not `public`, and `Sendable` the honest way — a lock around what it records, never
`@unchecked Sendable`. Every test of a given port uses that one fake, so the port's test-time
behavior is defined in one place rather than re-stubbed per test. Asserting on the
recorded calls is for the cases where *asking* is the behavior (asking again on each
refresh, not asking at all during `init`); otherwise assert on the state the answer
produced, not on the interaction that produced it.

## One Contract Suite per Port

A fake stands in for the adapter only while both keep the port's promises, so those
promises are asserted once, against both. The contract suite is a function over the
protocol, not over either implementation, and every clause it checks is one the port's
`///` states (add the clause there first). `FrontmostAppProviding` is the worked example:

- The fakes and one contract function per port live in the `TownsfolkTestSupport` target
  (`Tests/TownsfolkTestSupport`), which both test targets depend on — never one test target
  depending on another. It is test code: no product exports it, and
  `ArchitectureBoundaryTests` fails if a shipped module imports it.
- `FrontmostAppProvidingContract.check(_:)` takes `some FrontmostAppProviding` and
  asserts with `#expect` that every non-`nil` answer carries a non-empty `name`, asking
  more than once. Its `violations(of:)` returns what `check(_:)` asserts on, so a Core
  test hands it a provider that breaks a clause and sees the contract report it — the
  proof the contract is not vacuous.
- `FrontmostAppProvidingContractTests` in `TownsfolkCoreTests` runs it against the fake:
  CI runs it, so the fake cannot drift from the port.
- `WorkspaceFrontmostAppProviderTests` in `TownsfolkPlatformTests`, a `.requiresLocalMachine`
  suite, runs the same function against `WorkspaceFrontmostAppProvider` beside its
  translation test (`just test-local`).

## Edge Cases (always consider these)

- **Boundary values**: values at, just inside, and just outside every bound
- **Repeated operations**: idempotence at bounds (clamp twice, reset twice)
- **State transitions**: initial state, after one operation, after error recovery
- **Both branches** of every conditional in Core (the coverage floors measure lines and functions, not branches, so they will not notice a missed one — write the test for each branch yourself)

## Hygiene

- Tests are independent: no shared mutable state, no ordering assumptions — Swift Testing
  runs them in parallel by default
- No `sleep` or timing-based assertion in a unit test; that flakiness belongs to no one.
  When time must pass, the type under test takes a clock or a `Tuning` delay (how: the
  `designing-core-logic` skill › Inject time), and the test hands it a zero `Duration`
  or a manually advanced test `Clock` kept in `Tests/TownsfolkCoreTests/`, then advances it —
  never `Task.sleep` to wait for something to happen
- A test that touches the file system gets its own directory:
  `FileManager.default.temporaryDirectory.appending(path: "TownsfolkTests-\(UUID().uuidString)")`,
  created in the test and removed in a `defer`. Never a fixed shared path, the checkout,
  or the home directory — parallel tests would collide, and a leftover file changes the
  next run
- NEVER weaken an assertion to make a test pass — fix the code
