import Foundation
import SignKit
import Testing

@testable import ParkKit

/// Panels are built directly rather than parsed, so these tests are about what
/// a sign leaves a car and cannot fail because the parser changed.
struct LimitSuggesterTests {

    static let weekdays = DaySet(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])

    /// `2P  8.30AM - 6PM  MON - FRI`, the commonest plate in Sydney.
    static let twoHourWeekday = Panel(
        restriction: .timeLimited(minutes: 120),
        days: weekdays,
        times: TimeWindows([TimeRange(start: 8 * 60 + 30, end: 18 * 60)!]),
        rawText: "2P\n8.30AM - 6PM\nMON - FRI"
    )

    static func sign(_ panels: Panel...) -> Sign {
        Sign(panels: panels.map { .panel($0) })
    }

    // Wednesday.
    static let wednesday = (year: 2026, month: 8, day: 19)

    @Test("parked mid-window, the allowance runs out two hours later")
    func runsOutWithinTheWindow() throws {
        let parked = Clock.sydney(2026, 8, 19, 13)
        let candidates = LimitSuggester().candidates(
            for: Self.sign(Self.twoHourWeekday),
            parkedAt: parked,
            in: Clock.sydney
        )

        let candidate = try #require(candidates.first)
        #expect(candidate.clockStarts == parked)
        #expect(candidate.allowanceEnds == Clock.sydney(2026, 8, 19, 15))
        #expect(candidate.restrictionLifts == nil)
        #expect(candidate.expiry == Clock.sydney(2026, 8, 19, 15))
        #expect(!candidate.startsLater)
    }

    @Test("parked late in the window, the restriction lifts before the allowance bites")
    func restrictionLiftsFirst() throws {
        let parked = Clock.sydney(2026, 8, 19, 17)
        let candidates = LimitSuggester().candidates(
            for: Self.sign(Self.twoHourWeekday),
            parkedAt: parked,
            in: Clock.sydney
        )

        let candidate = try #require(candidates.first)
        #expect(candidate.clockStarts == parked)
        #expect(candidate.allowanceEnds == Clock.sydney(2026, 8, 19, 19))
        #expect(candidate.restrictionLifts == Clock.sydney(2026, 8, 19, 18))
        // Nothing to count down to: the two hours never come due.
        #expect(candidate.expiry == nil)
        #expect(candidate.limit == .openEnded)
    }

    @Test("parked before the window opens, the allowance starts when it does")
    func allowanceStartsWithTheWindow() throws {
        let parked = Clock.sydney(2026, 8, 19, 7)
        let candidates = LimitSuggester().candidates(
            for: Self.sign(Self.twoHourWeekday),
            parkedAt: parked,
            in: Clock.sydney
        )

        let candidate = try #require(candidates.first)
        #expect(candidate.clockStarts == Clock.sydney(2026, 8, 19, 8, 30))
        #expect(candidate.allowanceEnds == Clock.sydney(2026, 8, 19, 10, 30))
        #expect(candidate.restrictionLifts == nil)
        #expect(candidate.startsLater)
    }

    @Test("parked on a Saturday, a weekday allowance waits until Monday")
    func waitsForTheNextWorkingDay() throws {
        let parked = Clock.sydney(2026, 8, 22, 13)
        let candidates = LimitSuggester().candidates(
            for: Self.sign(Self.twoHourWeekday),
            parkedAt: parked,
            in: Clock.sydney
        )

        let candidate = try #require(candidates.first)
        #expect(candidate.clockStarts == Clock.sydney(2026, 8, 24, 8, 30))
        #expect(candidate.expiry == Clock.sydney(2026, 8, 24, 10, 30))
    }

    @Test("a panel that forbids stopping is not an allowance")
    func noStoppingHasNoAllowance() {
        let panel = Panel(restriction: .noStopping, rawText: "NO STOPPING")
        let candidates = LimitSuggester().candidates(
            for: Self.sign(panel),
            parkedAt: Clock.sydney(2026, 8, 19, 13),
            in: Clock.sydney
        )
        #expect(candidates.isEmpty)
    }

    @Test("a panel that was not read never becomes an allowance")
    func unknownPanelsContributeNothing() {
        let sign = Sign(
            panels: [.unknown(Unknown(rawText: "2P ???", reason: .noRestrictionFound))]
        )
        let candidates = LimitSuggester().candidates(
            for: sign,
            parkedAt: Clock.sydney(2026, 8, 19, 13),
            in: Clock.sydney
        )
        #expect(candidates.isEmpty)
    }

    @Test("two allowances are offered soonest first")
    func twoPanelsAreOrdered() throws {
        let morning = Panel(
            restriction: .timeLimited(minutes: 60),
            days: Self.weekdays,
            times: TimeWindows([TimeRange(start: 8 * 60, end: 10 * 60)!]),
            rawText: "1P 8AM - 10AM MON - FRI"
        )
        let daytime = Panel(
            restriction: .timeLimited(minutes: 240),
            days: Self.weekdays,
            times: TimeWindows([TimeRange(start: 10 * 60, end: 18 * 60)!]),
            rawText: "4P 10AM - 6PM MON - FRI"
        )

        let candidates = LimitSuggester().candidates(
            for: Self.sign(daytime, morning),
            parkedAt: Clock.sydney(2026, 8, 19, 9),
            in: Clock.sydney
        )

        #expect(candidates.count == 2)
        #expect(candidates[0].expiry == Clock.sydney(2026, 8, 19, 10))
        #expect(candidates[1].expiry == Clock.sydney(2026, 8, 19, 14))
        #expect(candidates.soonestExpiring?.minutes == 60)
    }

    @Test("an allowance that never bites is not the one offered first")
    func soonestExpiringSkipsALiftedRestriction() throws {
        // Parked at five: the two-hour plate lifts at six, but a four-hour
        // plate that runs until ten still comes due at nine.
        let evening = Panel(
            restriction: .timeLimited(minutes: 240),
            days: .allDays,
            times: TimeWindows([TimeRange(start: 16 * 60, end: 22 * 60)!]),
            rawText: "4P 4PM - 10PM"
        )

        let candidates = LimitSuggester().candidates(
            for: Self.sign(Self.twoHourWeekday, evening),
            parkedAt: Clock.sydney(2026, 8, 19, 17),
            in: Clock.sydney
        )

        let offered = try #require(candidates.soonestExpiring)
        #expect(offered.minutes == 240)
        #expect(offered.expiry == Clock.sydney(2026, 8, 19, 21))
    }

    @Test("an allowance is four hours of elapsed time, not four turns of the clock")
    func daylightSavingIsElapsedTime() throws {
        // Sydney puts its clocks forward at 2am on 4 October 2026, so 2am to
        // 3am never happens. Four hours from 1am is six in the morning.
        let panel = Panel(
            restriction: .timeLimited(minutes: 240),
            days: .allDays,
            times: .allDay,
            rawText: "4P"
        )
        let parked = Clock.sydney(2026, 10, 4, 1)
        let candidates = LimitSuggester().candidates(
            for: Self.sign(panel),
            parkedAt: parked,
            in: Clock.sydney
        )

        let candidate = try #require(candidates.first)
        #expect(candidate.allowanceEnds == parked.addingTimeInterval(4 * 3600))
        #expect(candidate.allowanceEnds == Clock.sydney(2026, 10, 4, 6))
    }

    @Test("committing a candidate carries the allowance it came from")
    func limitNamesItsSource() throws {
        let candidates = LimitSuggester().candidates(
            for: Self.sign(Self.twoHourWeekday),
            parkedAt: Clock.sydney(2026, 8, 19, 13),
            in: Clock.sydney
        )
        let candidate = try #require(candidates.first)
        #expect(candidate.limit == .expires(
            at: Clock.sydney(2026, 8, 19, 15),
            source: .sign(minutes: 120)
        ))
    }
}
