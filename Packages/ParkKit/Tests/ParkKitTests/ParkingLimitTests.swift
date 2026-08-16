import Foundation
import SignKit
import Testing

@testable import ParkKit

struct ParkingLimitTests {

    static let parked = Clock.sydney(2026, 8, 19, 10, 20)

    // MARK: - The ring

    @Test("a limit just set has used none of itself")
    func aFreshLimitStartsFull() throws {
        // Set a quarter of an hour at 10:20, so it runs to 10:35.
        let limit = ParkingLimit.expires(
            at: Clock.sydney(2026, 8, 19, 10, 35),
            source: .chosen(minutes: 15)
        )
        let progress = try #require(limit.progress(at: Self.parked))
        #expect(abs(progress) < 0.0001)
    }

    /// The bug this pins: measuring from when the car arrived rather than from
    /// when the allowance started drained the ring before it had begun.
    @Test("a limit set long after parking still starts full")
    func aLateLimitStartsFull() throws {
        // Parked at 10:20; a quarter of an hour set at 11:20 runs to 11:35.
        let setAt = Clock.sydney(2026, 8, 19, 11, 20)
        let limit = ParkingLimit.expires(
            at: Clock.sydney(2026, 8, 19, 11, 35),
            source: .chosen(minutes: 15)
        )

        #expect(limit.startedAt == setAt)
        let progress = try #require(limit.progress(at: setAt))
        #expect(abs(progress) < 0.0001, "the hour before the limit was set is not part of it")

        // Halfway through the fifteen minutes is halfway round the ring,
        // regardless of how long the car had already been there.
        let half = try #require(limit.progress(at: Clock.sydney(2026, 8, 19, 11, 27, 30)))
        #expect(abs(half - 0.5) < 0.001)
    }

    @Test("the ring fills exactly as the allowance is used")
    func progressTracksTheAllowance() throws {
        let limit = ParkingLimit.expires(
            at: Clock.sydney(2026, 8, 19, 12),
            source: .sign(minutes: 120)
        )
        #expect(limit.startedAt == Clock.sydney(2026, 8, 19, 10))
        #expect(abs(try #require(limit.progress(at: Clock.sydney(2026, 8, 19, 10, 30))) - 0.25) < 0.001)
        #expect(abs(try #require(limit.progress(at: Clock.sydney(2026, 8, 19, 11))) - 0.5) < 0.001)
    }

    @Test("the ring never runs past a full turn or back before the start")
    func progressIsClamped() throws {
        let limit = ParkingLimit.expires(
            at: Clock.sydney(2026, 8, 19, 12),
            source: .sign(minutes: 120)
        )
        #expect(try #require(limit.progress(at: Clock.sydney(2026, 8, 19, 9))) == 0)
        #expect(try #require(limit.progress(at: Clock.sydney(2026, 8, 19, 15))) == 1)
    }

    @Test("an open ended spot has no ring to draw")
    func openEndedHasNoProgress() {
        #expect(ParkingLimit.openEnded.progress(at: Self.parked) == nil)
        #expect(ParkingLimit.openEnded.startedAt == nil)
    }

    @Test("time left goes negative rather than stopping at zero")
    func overrunIsStated() throws {
        let limit = ParkingLimit.expires(
            at: Clock.sydney(2026, 8, 19, 12),
            source: .sign(minutes: 120)
        )
        let left = try #require(limit.remaining(at: Clock.sydney(2026, 8, 19, 12, 20)))
        #expect(abs(left + 20 * 60) < 0.001)
    }

    // MARK: - The badge

    @Test("a badge names the restriction, never a broken first line")
    func badgeNamesTheRestriction() {
        // OCR routinely splits NO STOPPING across two lines, which used to
        // leave a badge reading just "NO".
        let split = Panel(restriction: .noStopping, rawText: "NO\nSTOPPING")
        #expect(ParkWording.plateHeadline(split) == "NO STOPPING")

        let noParking = Panel(restriction: .noParking, rawText: "NO\nPARKING\n6AM - 10AM")
        #expect(ParkWording.plateHeadline(noParking) == "NO PARKING")
    }

    @Test("an allowance is badged the way NSW paints it")
    func allowanceBadges() {
        func badge(_ minutes: Int) -> String {
            ParkWording.plateHeadline(
                Panel(restriction: .timeLimited(minutes: minutes), rawText: "")
            )
        }

        #expect(badge(15) == "1/4P")
        #expect(badge(30) == "1/2P")
        #expect(badge(45) == "3/4P")
        #expect(badge(60) == "1P")
        #expect(badge(120) == "2P")
        #expect(badge(240) == "4P")
        // Nothing NSW paints, so it is stated rather than rounded into a plate
        // that does not exist.
        #expect(badge(90) == "90 MIN")
    }
}
