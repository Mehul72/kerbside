import CoreGraphics
import Foundation
import ImageIO
import SignKit
import Testing

@testable import SignVision

/// What a photograph should yield, described only in terms that survive OCR.
///
/// Raw text is deliberately absent. Vision returns whatever it read, and
/// asserting on that would make this a test of Apple's recogniser rather than
/// of our segmentation. What must hold is that the rules recovered from the
/// photograph are the rules on the sign.
struct ExpectedPanel: Codable, Hashable {
    var restriction: Restriction
    var days: DaySet
    var times: TimeWindows
    var direction: Direction
    var qualifiers: [Qualifier]

    init(_ panel: Panel) {
        restriction = panel.restriction
        days = panel.days
        times = panel.times
        direction = panel.direction
        qualifiers = panel.qualifiers
    }
}

struct VisionExpectation: Codable {
    var note: String?
    /// Set only while a fixture is known to fail, saying why. The suite fails
    /// if a fixture carrying this starts passing, so a fixed case cannot stay
    /// quietly marked broken.
    var knownIssue: String?
    var panels: [ExpectedPanel]
    /// Unknowns are counted, not described. The reason carries OCR text, which
    /// varies, but a panel that cannot be read must still never disappear.
    var unknownCount: Int
}

/// Photographs of real poles, run through the same pipeline the app uses.
///
/// The SignVision suite otherwise draws every image it tests against, so it
/// cannot fail on a photograph. These cases exist so that it can.
struct VisionFixtureTests {
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SignVisionTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SignVision
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("fixtures/vision", isDirectory: true)

    static func names() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".jpg") }
            .map { String($0.dropLast(4)) }
            .sorted()
    }

    static func read(_ name: String) async throws -> (Sign, VisionExpectation) {
        let expectation = try JSONDecoder().decode(
            VisionExpectation.self,
            from: try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
        )
        let url = directory.appendingPathComponent("\(name).jpg")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw VisionFixtureError.unreadablePhotograph(name)
        }
        let reading = try await SignRecognizer().read(image)
        return (reading.sign, expectation)
    }

    enum VisionFixtureError: Error {
        case unreadablePhotograph(String)
    }

    @Test("photographs of real poles are segmented into the panels on them")
    func realPoles() async throws {
        let names = try Self.names()
        #expect(!names.isEmpty, "no photographs to test against")

        for name in names {
            let (sign, expected) = try await Self.read(name)
            let actual = sign.parsedPanels.map(ExpectedPanel.init)

            func check() {
                #expect(actual == expected.panels, "\(name) panels")
                #expect(sign.unknowns.count == expected.unknownCount, "\(name) unknown count")
            }

            if let issue = expected.knownIssue {
                await withKnownIssue("\(name): \(issue)") { check() }
            } else {
                check()
            }
        }
    }

    @Test("a photographed pole never silently loses a panel")
    func nothingDisappears() async throws {
        for name in try Self.names() {
            let (sign, expected) = try await Self.read(name)
            let total = expected.panels.count + expected.unknownCount
            #expect(
                sign.panels.count <= total || sign.unknowns.isEmpty == false,
                "\(name) produced \(sign.panels.count) results for a pole of \(total) panels"
            )
            #expect(!sign.panels.isEmpty, "\(name) produced nothing at all")
        }
    }
}
