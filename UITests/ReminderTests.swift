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

/// The opt-in alarm for a limit running out.
///
/// Whether a sound actually plays belongs to iOS and is not assertable here.
/// What is: that the choice is offered only once there is a limit to sound for,
/// that it is off until asked for, and that it survives a relaunch — a setting
/// that silently forgets itself is worse than one that was never offered.
@MainActor
final class ExpiryAlarmTests: XCTestCase {

    func testTheAlarmIsOptInAndRemembered() {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-kerbside-reset"]
        app.launch()

        app.buttons["park"].tap()
        XCTAssertTrue(app.buttons["collect"].waitForExistence(timeout: 15))

        // No limit yet, so there is nothing for an alarm to sound for.
        app.buttons["edit-limit"].tap()
        XCTAssertTrue(app.buttons["duration-15"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.switches["alarm"].exists,
            "an alarm is offered for a limit, and there is no limit yet"
        )

        app.buttons["duration-15"].tap()
        XCTAssertTrue(app.staticTexts["limit-attribution"].waitForExistence(timeout: 10))

        // Now it is on offer, and off.
        app.buttons["edit-limit"].tap()
        let alarm = app.switches["alarm"]
        XCTAssertTrue(alarm.waitForExistence(timeout: 5), "a limit should offer an alarm")
        XCTAssertEqual(alarm.value as? String, "0", "the alarm must be opt in")

        alarm.tap()
        XCTAssertEqual(alarm.value as? String, "1")
        app.buttons["Done"].firstMatch.tap()

        // Kept across a relaunch, without the reset that would wipe it.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["collect"].waitForExistence(timeout: 15))
        app.buttons["edit-limit"].tap()
        XCTAssertTrue(alarm.waitForExistence(timeout: 5))
        XCTAssertEqual(alarm.value as? String, "1", "the choice should be remembered")

        // Put it back, so a later run starts from the documented default.
        alarm.tap()
        XCTAssertEqual(alarm.value as? String, "0")
    }
}
