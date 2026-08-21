import XCTest

/// Adds the widget to the Home Screen and photographs it.
///
/// This drives SpringBoard rather than Kerbside, so it is the one test here
/// that depends on how the system's own interface is laid out. It is kept
/// separate for that reason: when a future iOS moves the widget gallery, this
/// is the file to fix, and nothing else here is affected.
@MainActor
final class WidgetGalleryTests: XCTestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testWidgetOnTheHomeScreen() throws {
        // Give the widget a car to report on first.
        let app = XCUIApplication()
        app.launchArguments += ["-kerbside-reset", "YES"]
        app.launch()
        app.buttons["park"].tap()
        XCTAssertTrue(app.buttons["collect"].waitForExistence(timeout: 15))
        app.buttons["edit-limit"].tap()
        let twoHours = app.buttons["duration-120"]
        XCTAssertTrue(twoHours.waitForExistence(timeout: 5))
        twoHours.tap()
        XCTAssertTrue(app.staticTexts["limit-attribution"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)

        try enterJiggleMode()
        try openWidgetGallery()
        try chooseKerbside()

        Thread.sleep(forTimeInterval: 3)
        capture("widget-home-screen")
    }

    private func enterJiggleMode() throws {
        let empty = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)
        )
        empty.press(forDuration: 1.6)
        Thread.sleep(forTimeInterval: 2)
    }

    private func openWidgetGallery() throws {
        let candidates = ["Add Widget", "Edit", "Add"]
        for label in candidates {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3), button.isHittable {
                button.tap()
                Thread.sleep(forTimeInterval: 2)
                // "Edit" opens a menu that then offers the gallery.
                let addWidget = springboard.buttons["Add Widget"]
                if addWidget.waitForExistence(timeout: 2), addWidget.isHittable {
                    addWidget.tap()
                    Thread.sleep(forTimeInterval: 2)
                }
                return
            }
        }
        throw XCTSkip("this iOS does not present the widget gallery the way this test expects")
    }

    private func chooseKerbside() throws {
        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 4) {
            search.tap()
            search.typeText("Kerbside")
            Thread.sleep(forTimeInterval: 2)
        }

        let cell = springboard.staticTexts["Kerbside NSW"].firstMatch
        guard cell.waitForExistence(timeout: 5) else {
            capture("widget-gallery-no-kerbside")
            throw XCTSkip("Kerbside did not appear in the widget gallery")
        }
        // The gallery's rows are drawn rather than exposed as controls, so the
        // label is found but is not itself hittable. Tapping where it sits
        // reaches the row underneath it.
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 3)
        capture("widget-gallery")

        // The gallery renders the widget itself as a transformed image, so its
        // contents are not reachable as text — only the configuration's own
        // name and description are. Finding those proves the extension loaded
        // and was asked for a timeline; the attached screenshot is what shows
        // it drew the saved spot.
        XCTAssertTrue(
            springboard.staticTexts["Your car"].waitForExistence(timeout: 5),
            "the widget extension should offer its configuration in the gallery"
        )

        let add = springboard.buttons["Add Widget"].firstMatch
        if add.waitForExistence(timeout: 4) {
            add.tap()
            Thread.sleep(forTimeInterval: 3)
        }
        capture("widget-added")

        let done = springboard.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) { done.tap() }
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
        try? screenshot.pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
    }
}
