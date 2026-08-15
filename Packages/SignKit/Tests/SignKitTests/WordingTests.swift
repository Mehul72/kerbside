import Testing

@testable import SignKit

struct WordingTests {
    @Test("a panel is restated in plain words")
    func panel() throws {
        let sign = Parser.parse("1P\n10AM - 3PM\nMON - FRI\nMETER")
        let panel = try #require(sign.parsedPanels.first)
        #expect(
            Wording.describe(panel)
                == "1 hour parking, Mon to Fri, 10am to 3pm, meter payment required"
        )
    }

    @Test("an unnamed direction is left out rather than widened")
    func unspecifiedDirection() {
        #expect(Wording.describe(Direction.unspecified) == nil)
        #expect(Wording.describe(Direction.left) == "to the left of the sign")
    }

    @Test("day sets collapse into ranges only when worth it")
    func daySets() {
        #expect(Wording.describe(DaySet.allDays) == "every day")
        #expect(Wording.describe(DaySet(weekdays: [.monday, .tuesday])) == "Mon, Tue")
        #expect(Wording.describe(DaySet(weekdays: [.monday, .tuesday, .wednesday])) == "Mon to Wed")
        #expect(Wording.describe(DaySet(weekdays: [.monday, .wednesday, .friday])) == "Mon, Wed, Fri")
        #expect(
            Wording.describe(DaySet(weekdays: [.saturday], includesPublicHolidays: true))
                == "Sat, public holidays"
        )
    }

    @Test("clock wording names midnight and noon")
    func clocks() {
        #expect(Wording.describe(TimeWindows.allDay) == "at all times")
        #expect(Wording.describe(TimeWindows([TimeRange(start: 1320, end: 360)!])) == "10pm to 6am")
        #expect(Wording.describe(TimeWindows([TimeRange(start: 540, end: 750)!])) == "9am to 12:30pm")
        #expect(Wording.describe(TimeWindows([TimeRange(start: 720, end: 1080)!])) == "noon to 6pm")
    }

    @Test("a peak hour panel names both of its windows")
    func peakHourWindows() throws {
        let sign = Parser.parse("NO STOPPING\n6AM - 10AM & 3PM - 6PM\nMON - FRI")
        let panel = try #require(sign.parsedPanels.first)
        #expect(
            Wording.describe(panel)
                == "No stopping, Mon to Fri, 6am to 10am and 3pm to 6pm"
        )
    }

    @Test("windows are ordered however the sign wrote them")
    func windowOrdering() {
        let evening = TimeRange(start: 900, end: 1080)!
        let morning = TimeRange(start: 360, end: 600)!
        #expect(TimeWindows([evening, morning]) == TimeWindows([morning, evening]))
        #expect(TimeWindows([morning, morning]).ranges.count == 1)
        #expect(TimeWindows([]).isAllDay)
    }

    @Test("durations read the way the sign is spoken")
    func durations() {
        #expect(Wording.describe(Restriction.timeLimited(minutes: 15)) == "15 minute parking")
        #expect(Wording.describe(Restriction.timeLimited(minutes: 60)) == "1 hour parking")
        #expect(Wording.describe(Restriction.timeLimited(minutes: 240)) == "4 hour parking")
        #expect(Wording.describe(Restriction.timeLimited(minutes: 90)) == "1 hour 30 minute parking")
    }

    @Test("a missing arrow is stated, not left silent")
    func missingDirection() {
        #expect(Wording.missingDirectionNote(.unspecified) != nil)
        #expect(Wording.missingDirectionNote(.left) == nil)
        #expect(Wording.missingDirectionNote(.both) == nil)
    }

    @Test("an unknown says what defeated it")
    func unknowns() throws {
        let sign = Parser.parse("2P\n8AM - 6PM\nWOMBAT CROSSING")
        let unknown = try #require(sign.unknowns.first)
        #expect(Wording.describe(unknown.reason) == "This line was not understood: WOMBAT CROSSING")
    }
}
