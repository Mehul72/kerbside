import Foundation
import Testing

@testable import SignKit

private struct EvaluatorFixture: Decodable {
    var sign: Sign
    var instant: String
    var timeZone: String
    var expected: Evaluation
}

struct EvaluatorFixtureTests {
    @Test("every evaluator fixture produces its expected timeline")
    func fixtures() throws {
        let cases = try Fixtures.evaluatorCases()
        #expect(!cases.isEmpty, "no evaluator fixtures found")

        for evaluatorCase in cases {
            let fixture: EvaluatorFixture
            do {
                fixture = try JSONDecoder().decode(EvaluatorFixture.self, from: evaluatorCase.json)
            } catch {
                Issue.record("\(evaluatorCase.name).json did not decode: \(error)")
                continue
            }
            guard let instant = ISO8601DateFormatter().date(from: fixture.instant) else {
                Issue.record("\(evaluatorCase.name) has an invalid instant: \(fixture.instant)")
                continue
            }
            guard let timeZone = TimeZone(identifier: fixture.timeZone) else {
                Issue.record("\(evaluatorCase.name) has an invalid time zone: \(fixture.timeZone)")
                continue
            }

            let actual = Evaluator.evaluate(fixture.sign, at: instant, in: timeZone)
            #expect(
                actual == fixture.expected,
                "\(evaluatorCase.name)\n  expected \(fixture.expected)\n  actual   \(actual)"
            )
        }
    }

    @Test("evaluations round trip through their fixture representation")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for evaluatorCase in try Fixtures.evaluatorCases() {
            let fixture = try decoder.decode(EvaluatorFixture.self, from: evaluatorCase.json)
            let reread = try decoder.decode(Evaluation.self, from: encoder.encode(fixture.expected))
            #expect(reread == fixture.expected, "\(evaluatorCase.name) did not survive a round trip")
        }
    }
}
