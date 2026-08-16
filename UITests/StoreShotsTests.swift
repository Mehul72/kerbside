import XCTest

/// Produces the App Store screenshots by walking the real app.
///
/// Not a test of behaviour — it asserts only enough to fail loudly if a screen
/// it is meant to photograph is not there. It expects a record to have been
/// seeded into the shared container first, so the shots show a real sign
/// rather than an empty app.
@MainActor
final class StoreShotsTests: XCTestCase {

    func testCaptureStoreShots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kerbside-intro", "YES"]
        app.launch()

        let start = app.buttons["intro-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        capture("1-introduction")
        start.tap()

        // Store shots need a car and a sign in the shared container. Without
        // one there is nothing to photograph, so this is skipped rather than
        // failed — it is a generator, not a test of behaviour.
        guard app.buttons["collect"].waitForExistence(timeout: 10) else {
            throw XCTSkip("no spot seeded; run the seeding script before capturing")
        }
        Thread.sleep(forTimeInterval: 2)
        capture("2-parked")

        // A spot saved without a location has no walk back to photograph.
        let walkBack = app.buttons["walk-back"]
        guard walkBack.waitForExistence(timeout: 5) else {
            throw XCTSkip("the seeded spot has no coordinate, so there is no walk back")
        }
        walkBack.tap()
        Thread.sleep(forTimeInterval: 4)
        capture("3-walk-back")

        app.buttons["done"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)

        app.buttons["edit-limit"].tap()
        Thread.sleep(forTimeInterval: 2)
        capture("4-limit")
    }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kerbside-store", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
