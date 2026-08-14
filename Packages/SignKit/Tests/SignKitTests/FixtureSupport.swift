import Foundation

/// Fixtures live at the repository root, shared by every package, so they are
/// found by walking up from this file rather than bundled as target resources.
/// Bundling would mean a second copy that can drift from the one you edit.
enum Fixtures {
    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SignKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SignKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root

    static var parserDirectory: URL {
        repositoryRoot.appendingPathComponent("fixtures/parser", isDirectory: true)
    }

    static var evaluatorDirectory: URL {
        repositoryRoot.appendingPathComponent("fixtures/evaluator", isDirectory: true)
    }

    struct ParserCase {
        var name: String
        var input: String
        var expectedJSON: Data
    }

    /// Every `.txt` in the parser directory paired with its `.json`. Adding a
    /// case means adding two files and nothing else.
    static func parserCases() throws -> [ParserCase] {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: parserDirectory.path)
            .filter { $0.hasSuffix(".txt") }
            .map { String($0.dropLast(4)) }
            .sorted()

        return try names.map { name in
            let input = try String(
                contentsOf: parserDirectory.appendingPathComponent("\(name).txt"),
                encoding: .utf8
            )
            let expected = try Data(
                contentsOf: parserDirectory.appendingPathComponent("\(name).json")
            )
            return ParserCase(name: name, input: input, expectedJSON: expected)
        }
    }

    struct EvaluatorCase {
        var name: String
        var json: Data
    }

    /// Evaluator fixtures are self-contained: sign, instant, time zone, and
    /// expected evaluation live together so a case cannot be paired wrongly.
    static func evaluatorCases() throws -> [EvaluatorCase] {
        try FileManager.default
            .contentsOfDirectory(atPath: evaluatorDirectory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .map { filename in
                EvaluatorCase(
                    name: String(filename.dropLast(5)),
                    json: try Data(
                        contentsOf: evaluatorDirectory.appendingPathComponent(filename)
                    )
                )
            }
    }
}
