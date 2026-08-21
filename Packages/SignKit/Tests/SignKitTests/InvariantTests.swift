import Foundation
import Testing

struct SourceFile {
    var path: String
    var text: String
}

/// Two of the invariants are cheap to check mechanically, so a test does it
/// rather than trusting anyone to notice in review.
struct InvariantTests {
    private static let searchedDirectories = [
        "Packages/SignKit",
        "Packages/SignVision",
        "Packages/ParkKit",
        "App",
        "Shared",
        "Widgets",
        "UITests",
    ]

    /// The two packages that hold the reasoning. Both are pure, both are
    /// tested without a simulator, and neither may read the clock.
    private static let pureSources = ["Packages/SignKit/Sources", "Packages/ParkKit/Sources/ParkKit"]

    /// This file names the very things it forbids, so it excludes itself.
    private static let selfPath = "Packages/SignKit/Tests/SignKitTests/InvariantTests.swift"

    private static func swiftSources() -> [SourceFile] {
        var sources: [SourceFile] = []
        for directory in searchedDirectories {
            let root = Fixtures.repositoryRoot.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(atPath: root.path) else { continue }
            for case let relative as String in walker {
                guard relative.hasSuffix(".swift") else { continue }
                guard !relative.hasPrefix(".build/"), !relative.contains("/.build/") else { continue }
                let url = root.appendingPathComponent(relative)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let path = directory + "/" + relative
                guard path != selfPath else { continue }
                sources.append(SourceFile(path: path, text: text))
            }
        }
        return sources
    }

    @Test("no verdict: the codebase contains no canPark")
    func noVerdict() {
        let sources = Self.swiftSources()
        #expect(!sources.isEmpty, "no sources were scanned, so this proves nothing")
        for source in sources where source.text.contains("canPark") {
            Issue.record("\(source.path) mentions a parking verdict")
        }
    }

    @Test("on device only: no networking anywhere in the packages")
    func noNetwork() {
        let forbidden = ["import Network", "URLSession", "URLRequest", "NWConnection"]
        for source in Self.swiftSources() {
            for needle in forbidden where source.text.contains(needle) {
                Issue.record("\(source.path) uses \(needle)")
            }
        }
    }

    @Test("UserDefaults access has the App Store privacy reasons it needs")
    func userDefaultsReasonsAreDeclared() throws {
        let manifest = Fixtures.repositoryRoot
            .appendingPathComponent("App/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifest)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        let root = try #require(propertyList as? [String: Any])
        let APIs = try #require(root["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = try #require(APIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        let reasons = Set(try #require(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String]))

        #expect(reasons.contains("1C8F.1"), "the App Group preference needs its approved reason")
        #expect(reasons.contains("CA92.1"), "the local fallback needs its approved reason")
        #expect(root["NSPrivacyTracking"] as? Bool == false)
        #expect((root["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    @Test("the reasoning never reads an ambient clock")
    func noAmbientClock() {
        for source in Self.swiftSources()
        where Self.pureSources.contains(where: source.path.hasPrefix) && source.text.contains("Date()") {
            Issue.record("\(source.path) reads the current time")
        }
    }

    /// ParkKit reasons about places and durations, and it does so in plain
    /// numbers. Letting CoreLocation in would put the walk home behind a
    /// simulator, which is exactly what SignKit refuses for signs.
    @Test("ParkKit depends on nothing but Foundation and SignKit")
    func parkKitStaysPure() {
        let allowed: Set<String> = ["Foundation", "SignKit"]
        for source in Self.swiftSources()
        where source.path.hasPrefix("Packages/ParkKit/Sources/ParkKit") {
            for line in source.text.split(separator: "\n") where line.hasPrefix("import ") {
                let module = line.dropFirst("import ".count).trimmingCharacters(in: .whitespaces)
                if !allowed.contains(module) {
                    Issue.record("\(source.path) imports \(module)")
                }
            }
        }
    }

    /// The walk back is a bearing and a distance, never a map.
    ///
    /// Map tiles are fetched, and this app works in airplane mode because
    /// everything it knows it worked out on the device. Handing off to Apple
    /// Maps is allowed — that launches another app rather than making a
    /// request — so `MKMapItem` is fine and a map view is not.
    @Test("no map is ever drawn inside the app")
    func noEmbeddedMap() {
        let forbidden = ["MKMapView", "MapKit.Map", "Map(coordinateRegion", "Map(position"]
        for source in Self.swiftSources() {
            for needle in forbidden where source.text.contains(needle) {
                Issue.record("\(source.path) draws a map with \(needle)")
            }
        }
    }
}
