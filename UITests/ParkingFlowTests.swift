import XCTest

/// The parts of Kerbside that only exist on a device.
///
/// SignKit and ParkKit are tested without a simulator, so nothing here checks
/// arithmetic. What it checks is that the record is really written and read
/// back, that a limit chosen off a sign reaches the countdown, and that a
/// collected car leaves the screen — the seams between the packages and the
/// interface.
final class ParkingFlowTests: XCTestCase {

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

    /// Saving a spot, then collecting it, returns the app to where it started.
    func testParkingAndCollecting() {
        XCTAssertTrue(
            app.buttons["park"].waitForExistence(timeout: 10),
            "the empty home should offer to save a spot"
        )

        app.buttons["park"].tap()

        let collect = app.buttons["collect"]
        XCTAssertTrue(
            collect.waitForExistence(timeout: 15),
            "saving a spot should show the parked screen"
        )
        capture("parked-no-sign")

        // No sign was read, so nothing may invent a limit.
        let attribution = app.staticTexts["limit-attribution"]
        XCTAssertTrue(attribution.exists)
        XCTAssertEqual(
            attribution.label,
            "No limit recorded.",
            "a spot with no sign must say it has no limit rather than showing one"
        )
        XCTAssertTrue(
            app.otherElements["no-sign"].exists || app.images["no-sign"].exists
                || app.staticTexts["no-sign"].exists,
            "a spot with no sign should show an unread plate"
        )

        collect.tap()

        XCTAssertTrue(
            app.buttons["park"].waitForExistence(timeout: 10),
            "collecting the car should return to the empty home"
        )
    }

    /// A limit set by hand reaches the countdown and names itself as chosen.
    func testSettingALimitByHand() {
        app.buttons["park"].tap()
        XCTAssertTrue(app.buttons["collect"].waitForExistence(timeout: 15))

        app.buttons["edit-limit"].tap()

        let twoHours = app.buttons["duration-120"]
        XCTAssertTrue(twoHours.waitForExistence(timeout: 5), "the sheet should offer plain durations")
        capture("limit-sheet")
        twoHours.tap()

        // The countdown must attribute the number to the person who set it.
        let attribution = app.staticTexts["limit-attribution"]
        XCTAssertTrue(attribution.waitForExistence(timeout: 10))
        XCTAssertTrue(
            attribution.label.contains("you set"),
            "a limit set by hand should say so, got: \(attribution.label)"
        )
        capture("parked-with-limit")
    }

    /// The record survives the app being killed and relaunched, which is the
    /// whole point of writing it to a file.
    func testSpotSurvivesRelaunch() {
        app.buttons["park"].tap()
        XCTAssertTrue(app.buttons["collect"].waitForExistence(timeout: 15))

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(
            app.buttons["collect"].waitForExistence(timeout: 15),
            "a saved spot should still be there after a relaunch"
        )
    }

    /// Screenshots land in the shared container so they can be looked at from
    /// outside the simulator, and are attached to the result bundle as well.
    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.au.kerbside"
        ) else { return }
        let shots = directory.appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(
            to: shots.appendingPathComponent("\(name).png")
        )
    }
}
