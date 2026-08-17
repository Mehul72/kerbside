import Foundation
import SignKit
import Testing

@testable import ParkKit

struct ReminderPlanTests {

    static let parked = Clock.sydney(2026, 8, 19, 13)

    static func spot(limit: ParkingLimit, sign: Sign? = nil) -> ParkingSpot {
        ParkingSpot(parkedAt: parked, sign: sign, limit: limit)
    }

    @Test("a limit two hours out earns a warning and a notice")
    func warningAndNotice() {
        let expiry = Clock.sydney(2026, 8, 19, 15)
        let reminders = ReminderPlan.reminders(
            for: Self.spot(limit: .expires(at: expiry, source: .sign(minutes: 120))),
            now: Self.parked,
            in: Clock.sydney
        )

        #expect(reminders.count == 2)
        #expect(reminders[0].at == Clock.sydney(2026, 8, 19, 14, 45))
        #expect(reminders[0].kind == .limitEndsSoon(minutesBefore: 15))
        #expect(reminders[1].at == expiry)
        #expect(reminders[1].kind == .limitEnded)
    }

    @Test("a warning that would fire before the car was left is dropped")
    func warningInThePastIsDropped() {
        let expiry = Self.parked.addingTimeInterval(10 * 60)
        let reminders = ReminderPlan.reminders(
            for: Self.spot(limit: .expires(at: expiry, source: .chosen(minutes: 10))),
            now: Self.parked,
            in: Clock.sydney
        )

        #expect(reminders.count == 1)
        #expect(reminders[0].kind == .limitEnded)
    }

    @Test("an open ended spot with no sign has nothing to say")
    func openEndedSaysNothing() {
        let reminders = ReminderPlan.reminders(
            for: Self.spot(limit: .openEnded),
            now: Self.parked,
            in: Clock.sydney
        )
        #expect(reminders.isEmpty)
    }

    @Test("a rule that starts later is worth a reminder even with no limit")
    func restrictionBeginningIsWorthSaying() throws {
        // Parked on a Sunday evening under a weekday morning clearway.
        let clearway = Panel(
            restriction: .noParking,
            days: DaySet(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            times: TimeWindows([TimeRange(start: 6 * 60, end: 10 * 60)!]),
            rawText: "NO PARKING\n6AM - 10AM\nMON - FRI"
        )
        let sunday = Clock.sydney(2026, 8, 23, 19)
        let spot = ParkingSpot(
            parkedAt: sunday,
            sign: Sign(panels: [.panel(clearway)]),
            limit: .openEnded
        )

        let reminders = ReminderPlan.reminders(for: spot, now: sunday, in: Clock.sydney)

        #expect(reminders.count == 1)
        #expect(reminders[0].at == Clock.sydney(2026, 8, 24, 6))
        guard case .restrictionBegins(let panel) = reminders[0].kind else {
            Issue.record("expected a restriction beginning")
            return
        }
        #expect(panel.restriction == .noParking)
    }

    @Test("a collected car is not reminded about")
    func collectedSpotIsSilent() {
        var spot = Self.spot(
            limit: .expires(at: Clock.sydney(2026, 8, 19, 15), source: .sign(minutes: 120))
        )
        spot.collectedAt = Clock.sydney(2026, 8, 19, 14)

        let reminders = ReminderPlan.reminders(for: spot, now: Self.parked, in: Clock.sydney)
        #expect(reminders.isEmpty)
    }

    @Test("reminders come back in order and with distinct identities")
    func orderedAndDistinct() {
        let preferences = ReminderPreferences(
            leads: [60, 15, 5],
            atExpiry: true,
            restrictionChanges: false
        )
        let reminders = ReminderPlan.reminders(
            for: Self.spot(
                limit: .expires(at: Clock.sydney(2026, 8, 19, 17), source: .chosen(minutes: 240))
            ),
            now: Self.parked,
            in: Clock.sydney,
            preferences: preferences
        )

        #expect(reminders.count == 4)
        #expect(reminders.map(\.at) == reminders.map(\.at).sorted())
        #expect(Set(reminders.map(\.id)).count == 4)
    }

    @Test("identities are stable, so replanning replaces rather than stacks")
    func identitiesAreStable() {
        let spot = Self.spot(
            limit: .expires(at: Clock.sydney(2026, 8, 19, 15), source: .sign(minutes: 120))
        )
        let first = ReminderPlan.reminders(for: spot, now: Self.parked, in: Clock.sydney)
        let second = ReminderPlan.reminders(for: spot, now: Self.parked, in: Clock.sydney)
        #expect(first.map(\.id) == second.map(\.id))
    }
}

/// The reminder that is worth having: leave now, because the walk back plus a
/// little is all the time that is left.
struct TimeToLeaveTests {

    static let parked = Clock.sydney(2026, 8, 19, 13)

    static func spot(expiring at: Date) -> ParkingSpot {
        ParkingSpot(
            parkedAt: parked,
            limit: .expires(at: at, source: .chosen(minutes: 120))
        )
    }

    @Test("a distant car is called back earlier than a near one")
    func leadFollowsTheWalk() throws {
        let expiry = Clock.sydney(2026, 8, 19, 15)

        func leaveTime(walk: Int) throws -> Date {
            let reminders = ReminderPlan.reminders(
                for: Self.spot(expiring: expiry),
                now: Self.parked,
                in: Clock.sydney,
                walkingMinutes: walk
            )
            let leave = try #require(reminders.first { $0.kind == .timeToLeave(walkMinutes: walk) })
            return leave.at
        }

        // Walk plus the five minute buffer, every time.
        #expect(try leaveTime(walk: 2) == Clock.sydney(2026, 8, 19, 14, 53))
        #expect(try leaveTime(walk: 10) == Clock.sydney(2026, 8, 19, 14, 45))
        #expect(try leaveTime(walk: 25) == Clock.sydney(2026, 8, 19, 14, 30))
    }

    @Test("a known walk replaces the fixed warning rather than adding to it")
    func walkReplacesTheFixedLead() {
        let reminders = ReminderPlan.reminders(
            for: Self.spot(expiring: Clock.sydney(2026, 8, 19, 15)),
            now: Self.parked,
            in: Clock.sydney,
            walkingMinutes: 4
        )
        #expect(reminders.contains { $0.kind == .timeToLeave(walkMinutes: 4) })
        #expect(!reminders.contains { $0.kind == .limitEndsSoon(minutesBefore: 15) })
    }

    @Test("with no distance to work from, the fixed warning still stands")
    func fallsBackWithoutADistance() {
        let reminders = ReminderPlan.reminders(
            for: Self.spot(expiring: Clock.sydney(2026, 8, 19, 15)),
            now: Self.parked,
            in: Clock.sydney,
            walkingMinutes: nil
        )
        #expect(reminders.contains { $0.kind == .limitEndsSoon(minutesBefore: 15) })
        #expect(!reminders.contains { if case .timeToLeave = $0.kind { true } else { false } })
    }

    @Test("the moment it runs out is said either way")
    func expiryIsAlwaysSaid() {
        for walk in [nil, 3] as [Int?] {
            let reminders = ReminderPlan.reminders(
                for: Self.spot(expiring: Clock.sydney(2026, 8, 19, 15)),
                now: Self.parked,
                in: Clock.sydney,
                walkingMinutes: walk
            )
            #expect(
                reminders.contains { $0.kind == .limitEnded },
                "expected an expiry notice with walkingMinutes \(String(describing: walk))"
            )
        }
    }

    @Test("a walk longer than the time left cannot fire in the past")
    func tooLateToLeave() {
        // Ten minutes left, but the car is half an hour away.
        let reminders = ReminderPlan.reminders(
            for: Self.spot(expiring: Self.parked.addingTimeInterval(10 * 60)),
            now: Self.parked,
            in: Clock.sydney,
            walkingMinutes: 30
        )
        #expect(!reminders.contains { if case .timeToLeave = $0.kind { true } else { false } })
        #expect(reminders.contains { $0.kind == .limitEnded })
    }

    @Test("the notification says how far the walk is and what runs out")
    func wording() throws {
        let spot = Self.spot(expiring: Clock.sydney(2026, 8, 19, 15))
        let reminders = ReminderPlan.reminders(
            for: spot,
            now: Self.parked,
            in: Clock.sydney,
            walkingMinutes: 8
        )
        let leave = try #require(reminders.first { $0.kind == .timeToLeave(walkMinutes: 8) })
        let words = ParkWording.notification(for: leave, spot: spot, in: Clock.sydney)
        #expect(words.title == "Time to head back")
        #expect(words.body.contains("8 minutes"))
        #expect(words.body.contains("3:00 pm"))
    }
}
