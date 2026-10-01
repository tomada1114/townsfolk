import XCTest

/// The launch guarantee: the app starts and shows the town window.
///
/// XCTest by necessity — Apple has not ported UI automation to Swift Testing.
/// All other tests use Swift Testing in Packages/TownsfolkKit.
final class LaunchTests: XCTestCase {
    private enum Timeout {
        static let windowAppears: TimeInterval = 10
        static let elementAppears: TimeInterval = 5
    }

    @MainActor
    func testAppLaunchesAndShowsTownWindow() {
        // A failed launch assertion should end the test immediately instead of
        // cascading through the remaining waits against a dead app.
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launch()

        let window = app.windows["Townsfolk"]
        XCTAssertTrue(window.waitForExistence(timeout: Timeout.windowAppears))
        XCTAssertEqual(app.windows.count, 1, "the app should open exactly one window")

        // Every later state of the window keeps this identifier on its root.
        let root = window.descendants(matching: .any)["townWindow"]
        XCTAssertTrue(root.waitForExistence(timeout: Timeout.elementAppears))
    }
}
