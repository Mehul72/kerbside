import XCTest

/// The surfaces outside the app: the Dynamic Island and the Lock Screen.
///
/// These cannot be asserted on the way a screen can — they belong to the
/// system, not to Kerbside — so what this checks is that starting an activity
/// does not fail and that the app survives being sent away and brought back
/// with one running.
@MainActor
final class LiveSurfaceTests: XCTestCase {

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

    func testActivitySurvivesBackgrounding() {
        app.buttons["park"].tap()
        XCTAssertTrue(app.buttons["collect"].waitForExistence(timeout: 15))

        // A limit gives the banner something to count down.
        app.buttons["edit-limit"].tap()
        let twoHours = app.buttons["duration-120"]
        XCTAssertTrue(twoHours.waitForExistence(timeout: 5))
        twoHours.tap()
        XCTAssertTrue(app.staticTexts["limit-attribution"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        capture("dynamic-island")

        app.activate()
        XCTAssertTrue(
            app.buttons["collect"].waitForExistence(timeout: 15),
            "coming back to the app should find the same car still parked"
        )
        capture("returned")
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let shots = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kerbside-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(
            to: shots.appendingPathComponent("\(name).png")
        )
    }
}
