import Foundation
import Testing

@testable import SignKit

struct ParserFixtureTests {
    @Test("every parser fixture reads as its expected sign")
    func fixtures() throws {
        let cases = try Fixtures.parserCases()
        #expect(!cases.isEmpty, "no parser fixtures found")

        for parserCase in cases {
            let expected: Sign
            do {
                expected = try JSONDecoder().decode(Sign.self, from: parserCase.expectedJSON)
            } catch {
                Issue.record("\(parserCase.name).json did not decode: \(error)")
                continue
            }

            let actual = Parser.parse(parserCase.input)
            #expect(actual == expected, "\(parserCase.name)\n  expected \(expected)\n  actual   \(actual)")
        }
    }

    @Test("parsing is deterministic across repeated runs")
    func determinism() throws {
        for parserCase in try Fixtures.parserCases() {
            let first = Parser.parse(parserCase.input)
            for _ in 0..<8 {
                #expect(Parser.parse(parserCase.input) == first, "\(parserCase.name) varied between runs")
            }
        }
    }

    @Test("a sign round trips through its encoded form")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for parserCase in try Fixtures.parserCases() {
            let sign = Parser.parse(parserCase.input)
            let reread = try decoder.decode(Sign.self, from: try encoder.encode(sign))
            #expect(reread == sign, "\(parserCase.name) did not survive a round trip")
        }
    }
}
