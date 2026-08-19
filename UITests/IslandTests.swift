import XCTest

/// Photographs the Dynamic Island in both of its presentations.
///
/// Like `WidgetGalleryTests` this drives SpringBoard rather than Kerbside, so
/// it depends on where the system puts its own furniture. It is kept apart for
/// that reason: the expanded island is a surface the app cannot see, and two
/// layout faults lived in it unnoticed because nothing here ever looked.
@MainActor
final class IslandTests: XCTestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testIslandPresentations() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kerbside-reset", "YES"]
        app.launch()
        app.buttons["park"].tap()
        XCTAssertTrue(app.buttons["collect"].waitForExistence(timeout: 15))

        // A quarter hour, so the count is mm:ss — the shape the island was
        // reported wrong in.
        app.buttons["edit-limit"].tap()
        let quarterHour = app.buttons["duration-15"]
        XCTAssertTrue(quarterHour.waitForExistence(timeout: 5))
        quarterHour.tap()
        XCTAssertTrue(app.staticTexts["limit-attribution"].waitForExistence(timeout: 10))

        // The first activity a device ever runs asks permission, and the
        // prompt sits over the very surfaces this photographs.
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        capture("island-compact")

        // The island sits across the top centre. A long press opens it.
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.021))
        island.press(forDuration: 1.2)
        // The expansion animates. Photographed too early this catches a
        // half-drawn frame — which is how the clipped plate and the cut-off
        // count read at first glance, rather than as the layout faults they
        // were.
        Thread.sleep(forTimeInterval: 2)
        capture("island-expanded")
    }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kerbside-island", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
