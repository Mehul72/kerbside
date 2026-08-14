import Foundation
import Testing

@testable import SignKit

struct EvaluatorTests {
    private let sydney = TimeZone(identifier: "Australia/Sydney")!

    @Test("a weekday window is active and ends at its local boundary")
    func activeWeekday() throws {
        let sign = Parser.parse("1P\n9AM - 5PM\nMON - FRI")
        let instant = try #require(Self.instant("2026-08-14T02:00:00Z")) // Friday noon
        let expectedEnd = try #require(Self.instant("2026-08-14T07:00:00Z"))

        let result = Evaluator.evaluate(sign, at: instant, in: sydney)

        #expect(result.active == sign.parsedPanels)
        #expect(result.inactive.isEmpty)
        #expect(result.unknowns.isEmpty)
        #expect(result.nextChange?.kind == .ends)
        #expect(result.nextChange?.at == expectedEnd)
    }

    @Test("cross-midnight hours keep the starting day's scope")
    func crossesMidnight() throws {
        let sign = Parser.parse("NO PARKING\n10PM - 6AM\nFRI")
        let instant = try #require(Self.instant("2026-08-14T16:30:00Z")) // Saturday 2:30am

        let result = Evaluator.evaluate(sign, at: instant, in: sydney)

        #expect(result.active.count == 1)
        #expect(result.nextChange?.kind == .ends)
        #expect(result.nextChange?.at == Self.instant("2026-08-14T20:00:00Z"))
    }

    @Test("weekday-only panels are suppressed on a public holiday")
    func publicHoliday() throws {
        let weekday = Parser.parse("1P\n9AM - 10AM\nMON - FRI")
        let holiday = Parser.parse("NO PARKING\n9AM - 10AM\nPUBLIC HOLIDAYS")
        let sign = Sign(panels: weekday.panels + holiday.panels)
        let instant = try #require(Self.instant("2026-01-25T22:30:00Z")) // Australia Day

        let result = Evaluator.evaluate(sign, at: instant, in: sydney)

        #expect(result.active == holiday.parsedPanels)
        #expect(result.inactive == weekday.parsedPanels)
    }

    @Test("a caller can inject its own holiday table")
    func injectedPublicHolidayProvider() throws {
        let sign = Parser.parse("1P\n9AM - 5PM\nFRI")
        let instant = try #require(Self.instant("2026-08-14T02:00:00Z"))
        let holidays = NSWPublicHolidays(
            dates: [LocalDate(year: 2026, month: 8, day: 14)]
        )

        let result = Evaluator(publicHolidays: holidays)
            .evaluate(sign, at: instant, in: sydney)

        #expect(result.active.isEmpty)
        #expect(result.inactive == sign.parsedPanels)
    }

    @Test("the NSW table contains statewide holidays but not the bank holiday")
    func statewideHolidayTable() {
        let holidays = NSWPublicHolidays.current

        #expect(holidays.isPublicHoliday(.init(year: 2026, month: 1, day: 26)))
        #expect(holidays.isPublicHoliday(.init(year: 2026, month: 4, day: 27)))
        #expect(holidays.isPublicHoliday(.init(year: 2027, month: 12, day: 28)))
        #expect(!holidays.isPublicHoliday(.init(year: 2026, month: 8, day: 3)))
    }

    @Test("time windows are half open at both exact boundaries")
    func exactBoundaries() throws {
        let sign = Parser.parse("1P\n9AM - 5PM")
        let start = try #require(Self.instant("2026-08-13T23:00:00Z"))
        let end = try #require(Self.instant("2026-08-14T07:00:00Z"))

        #expect(Evaluator.evaluate(sign, at: start, in: sydney).active.count == 1)
        #expect(Evaluator.evaluate(sign, at: end, in: sydney).active.isEmpty)
    }

    @Test("all-day every-day panels do not invent a midnight change")
    func continuousPanel() throws {
        let sign = Parser.parse("NO STOPPING")
        let instant = try #require(Self.instant("2026-08-14T02:00:00Z"))

        let result = Evaluator.evaluate(sign, at: instant, in: sydney)

        #expect(result.active.count == 1)
        #expect(result.nextChange == nil)
    }

    @Test("unknowns survive evaluation in sign order")
    func unknowns() throws {
        let sign = Parser.parse("LOADING ZONE\n\nNO PARKING")
        let instant = try #require(Self.instant("2026-08-14T02:00:00Z"))

        let result = Evaluator.evaluate(sign, at: instant, in: sydney)

        #expect(result.unknowns == sign.unknowns)
        #expect(result.active == sign.parsedPanels)
    }

    @Test("Sydney DST changes alter elapsed time, not stated wall time")
    func daylightSaving() throws {
        let sign = Parser.parse("1P\n1AM - 4AM")

        let spring = try #require(Self.instant("2026-10-03T15:30:00Z"))
        let springResult = Evaluator.evaluate(sign, at: spring, in: sydney)
        #expect(springResult.active.count == 1)
        #expect(springResult.nextChange?.at == Self.instant("2026-10-03T17:00:00Z"))

        let autumn = try #require(Self.instant("2026-04-04T15:30:00Z"))
        let autumnResult = Evaluator.evaluate(sign, at: autumn, in: sydney)
        #expect(autumnResult.active.count == 1)
        #expect(autumnResult.nextChange?.at == Self.instant("2026-04-04T18:00:00Z"))
    }

    private static func instant(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }
}
