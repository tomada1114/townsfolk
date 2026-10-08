import XCTest

/// The launch guarantee: the app starts and shows the town window.
///
/// XCTest by necessity — Apple has not ported UI automation to Swift Testing.
/// All other tests use Swift Testing in Packages/TownsfolkKit.
final class LaunchTests: XCTestCase {
    private enum Timeout {
        static let windowAppears: TimeInterval = 10
        static let elementAppears: TimeInterval = 10
    }

    @MainActor
    func testAppLaunchesAndShowsTownWindow() {
        // A failed launch assertion should end the test immediately instead of
        // cascading through the remaining waits against a dead app.
        continueAfterFailure = false

        let app = XCUIApplication()
        // Each launch owns a separate settings suite and sandbox temporary town.
        app.launchEnvironment["TOWNSFOLK_LAUNCH_TEST_ID"] = UUID().uuidString
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: Timeout.windowAppears))
        XCTAssertEqual(app.windows.count, 1, "the app should open exactly one window")

        // Every later state of the window keeps this identifier on its root.
        let root = window.descendants(matching: .any)["townWindow"]
        XCTAssertTrue(root.waitForExistence(timeout: Timeout.elementAppears))
        let firstScreen = NSPredicate { _, _ in
            window.descendants(matching: .any)["modelUnavailableMessage"].exists
                || window.descendants(matching: .any)["firstRunNameEntry"].exists
        }
        let screenAppeared = expectation(for: firstScreen, evaluatedWith: window)
        wait(for: [screenAppeared], timeout: Timeout.elementAppears)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "Launch screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
