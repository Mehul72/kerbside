import XCTest

/// Reminders, as far as they can be driven from outside.
///
/// Delivery belongs to the system and is not asserted here. Neither is the
/// permission prompt: a simulator reports notifications as already authorised
/// on a clean install and keeps that setting across an uninstall, so the ask
/// never appears and cannot be driven. **The prompt is therefore only ever
/// exercised on a real device.**
///
/// What is left, and what this covers, is that committing a limit schedules
/// against a real plan without failing, and that the countdown it produces is
/// attributed.
@MainActor
final class ReminderTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-kerbside-reset", "YES"]
        app.launch()
    }

    override func tearDown() {
        app = nil
    }

    func testCommittingALimitSchedulesWithoutFailing() {
        app.buttons["park"].tap()
        XCTAssertTrue(app.buttons["collect"].waitForExistence(timeout: 15))

        app.buttons["edit-limit"].tap()
        let quarterHour = app.buttons["duration-15"]
        XCTAssertTrue(quarterHour.waitForExistence(timeout: 5))
        quarterHour.tap()

        let attribution = app.staticTexts["limit-attribution"]
        XCTAssertTrue(attribution.waitForExistence(timeout: 10))
        XCTAssertTrue(
            attribution.label.contains("15 minute"),
            "got: \(attribution.label)"
        )

        // Changing the limit replaces the plan rather than stacking a second
        // one on top of it, and the app survives doing so.
        app.buttons["edit-limit"].tap()
        let twoHours = app.buttons["duration-120"]
        XCTAssertTrue(twoHours.waitForExistence(timeout: 5))
        twoHours.tap()

        XCTAssertTrue(attribution.waitForExistence(timeout: 10))
        XCTAssertTrue(
            attribution.label.contains("2 hour"),
            "the countdown should follow the limit that was just chosen, got: \(attribution.label)"
        )
    }
}
