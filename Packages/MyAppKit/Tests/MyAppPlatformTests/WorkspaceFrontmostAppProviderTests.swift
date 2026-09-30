import AppKit
import MyAppCore
import MyAppPlatform
import MyAppTestSupport
import Testing

/// The worked example of a local-machine adapter test, and the shape every other one
/// copies (`docs/architecture.md` › Ports and adapters).
///
/// It asks the real `NSWorkspace` the one question a Core test with a fake cannot:
/// does the adapter's translation survive contact with the OS? Everything *around*
/// that translation — what the app shows when there is no frontmost application, when
/// it refreshes — stays a Core test against `FakeFrontmostAppProvider`, where the
/// coverage floor sees it (`.claude/rules/testing.md` › Where a test goes).
///
/// Beside the translation test sits the adapter half of the port's contract suite:
/// `FrontmostAppProvidingContract`, the same function `MyAppCoreTests` runs against the
/// fake on every `just test` (`.claude/rules/testing.md` › One Contract Suite per Port).
///
/// `WorkspaceFrontmostAppProvider` needs no TCC grant; it needs a logged-in GUI
/// session, which is exactly what a CI runner does not have.
@Suite("WorkspaceFrontmostAppProvider against the real NSWorkspace", .requiresLocalMachine)
struct WorkspaceFrontmostAppProviderTests {
    @Test
    func `translates the frontmost application NSWorkspace reports`() throws {
        let provider = WorkspaceFrontmostAppProvider()

        let frontmost = try LocalMachineTests.require(
            provider.currentFrontmostApp(),
            requires: """
            a logged-in GUI session with an active application — NSWorkspace asks for no \
            permission, but a headless session has no frontmost application to report
            """,
            grant: false,
        )

        #expect(!frontmost.name.isEmpty)

        // Checked against the running applications rather than against a second read of
        // `frontmostApplication`: the frontmost application can change between two reads,
        // while the one just reported is certainly still running a moment later. This is
        // the assertion that the name and bundle identifier came off a real
        // `NSRunningApplication` instead of being invented by the translation.
        let running = NSWorkspace.shared.runningApplications
        #expect(
            running.contains { application in
                application.localizedName == frontmost.name
                    && application.bundleIdentifier == frontmost.bundleIdentifier
            },
            "\(frontmost) matches none of the \(running.count) running applications",
        )
    }

    @Test
    func `keeps the FrontmostAppProviding contract the fake is held to`() {
        FrontmostAppProvidingContract.check(WorkspaceFrontmostAppProvider())
    }
}
