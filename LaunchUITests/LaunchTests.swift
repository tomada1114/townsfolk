import XCTest

/// The template's launch guarantee: the app starts, shows its window, and responds.
///
/// XCTest by necessity — Apple has not ported UI automation to Swift Testing.
/// All other tests use Swift Testing in Packages/MyAppKit.
final class LaunchTests: XCTestCase {
    private enum Timeout {
        static let windowAppears: TimeInterval = 10
        static let elementAppears: TimeInterval = 5
    }

    @MainActor
    func testAppLaunchesAndShowsCounter() {
        // A failed launch assertion should end the test immediately instead of
        // cascading through the remaining waits against a dead app.
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Timeout.windowAppears))

        let counter = app.staticTexts["counterValue"]
        XCTAssertTrue(counter.waitForExistence(timeout: Timeout.elementAppears))

        app.buttons["incrementButton"].click()
        // macOS exposes a SwiftUI Text's string as `value` (sometimes `label`),
        // and the update is asynchronous — wait on a predicate covering both.
        let showsOne = NSPredicate(format: "label == '1' OR value == '1'")
        let updated = XCTNSPredicateExpectation(predicate: showsOne, object: counter)
        XCTAssertEqual(
            XCTWaiter.wait(for: [updated], timeout: Timeout.elementAppears),
            .completed,
            "counterValue should read 1 after clicking increment",
        )
    }
}
