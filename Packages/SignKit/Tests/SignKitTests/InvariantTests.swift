import Foundation
import Testing

struct SourceFile {
    var path: String
    var text: String
}

/// Two of the invariants are cheap to check mechanically, so a test does it
/// rather than trusting anyone to notice in review.
struct InvariantTests {
    private static let searchedDirectories = ["Packages/SignKit", "Packages/SignVision", "App"]

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

    @Test("the parser never reads an ambient clock")
    func noAmbientClock() {
        for source in Self.swiftSources()
        where source.path.hasPrefix("Packages/SignKit/Sources") && source.text.contains("Date()") {
            Issue.record("\(source.path) reads the current time")
        }
    }
}
