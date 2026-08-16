import Foundation
import SignKit
import Testing

@testable import ParkKit

struct SpotStoreTests {

    static func temporaryStore() -> (SpotStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parkkit-\(UUID().uuidString)")
        return (SpotStore(fileURL: SpotStore.url(inContainer: directory)), directory)
    }

    static let fullSpot = ParkingSpot(
        parkedAt: Clock.sydney(2026, 8, 19, 13),
        coordinate: Coordinate(latitude: -33.8688, longitude: 151.2093, accuracy: 8),
        note: "Level 3, bay 12",
        sign: Sign(
            panels: [
                .panel(
                    Panel(
                        restriction: .timeLimited(minutes: 120),
                        rawText: "2P"
                    )
                ),
                .unknown(Unknown(rawText: "⇦", reason: .noRestrictionFound)),
            ]
        ),
        limit: .expires(at: Clock.sydney(2026, 8, 19, 15), source: .sign(minutes: 120)),
        photoFilename: "spot.jpg"
    )

    @Test("a spot survives a round trip whole, unknown panels included")
    func roundTrip() throws {
        let (store, directory) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var record = ParkingRecord.empty
        record.park(Self.fullSpot)
        try store.save(record)

        let loaded = try store.load()
        #expect(loaded == record)
        #expect(loaded.active?.sign?.unknowns.count == 1)
        #expect(loaded.active?.coordinate?.accuracy == 8)
        #expect(loaded.active?.note == "Level 3, bay 12")
    }

    @Test("nothing written yet reads as empty rather than as an error")
    func missingFileIsEmpty() throws {
        let (store, directory) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try store.load() == .empty)
    }

    @Test("a file that cannot be read is an error, not a fresh start")
    func corruptFileThrows() throws {
        let (store, directory) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: SpotStore.url(inContainer: directory))

        #expect(throws: (any Error).self) { try store.load() }
        // A widget has nobody to show an error to, so it starts from empty.
        #expect(store.loadOrEmpty() == .empty)
    }

    @Test("parking a second car retires the first without losing it")
    func parkingRetiresThePrevious() {
        var record = ParkingRecord.empty
        record.park(Self.fullSpot)

        let later = ParkingSpot(parkedAt: Clock.sydney(2026, 8, 20, 9))
        record.park(later)

        #expect(record.active?.id == later.id)
        #expect(record.past.count == 1)
        #expect(record.past[0].id == Self.fullSpot.id)
        #expect(record.past[0].collectedAt == later.parkedAt)
    }

    @Test("collecting the car moves it into the past")
    func collecting() {
        var record = ParkingRecord.empty
        record.park(Self.fullSpot)
        record.collect(at: Clock.sydney(2026, 8, 19, 14, 30))

        #expect(record.active == nil)
        #expect(record.past.count == 1)
        #expect(record.past[0].collectedAt == Clock.sydney(2026, 8, 19, 14, 30))
    }

    @Test("collecting nothing does nothing")
    func collectingNothing() {
        var record = ParkingRecord.empty
        record.collect(at: Clock.sydney(2026, 8, 19, 14))
        #expect(record == .empty)
    }

    @Test("a past spot can be forgotten")
    func forgettingOne() {
        var record = ParkingRecord.empty
        record.park(Self.fullSpot)
        let second = ParkingSpot(parkedAt: Clock.sydney(2026, 8, 20, 9))
        record.park(second)
        record.collect(at: Clock.sydney(2026, 8, 20, 11))

        #expect(record.past.count == 2)
        record.forget(Self.fullSpot.id)
        #expect(record.past.count == 1)
        #expect(record.past[0].id == second.id)
    }

    @Test("forgetting the past keeps the car that is parked now")
    func forgettingAllKeepsTheActiveCar() {
        var record = ParkingRecord.empty
        record.park(Self.fullSpot)
        let current = ParkingSpot(parkedAt: Clock.sydney(2026, 8, 20, 9))
        record.park(current)

        record.forgetPast()

        #expect(record.past.isEmpty)
        #expect(record.active?.id == current.id, "the car parked now is not history")
    }

    @Test("forgetting a spot that is not there changes nothing")
    func forgettingAnUnknownSpot() {
        var record = ParkingRecord.empty
        record.park(Self.fullSpot)
        record.collect(at: Clock.sydney(2026, 8, 19, 14))
        record.forget(UUID())
        #expect(record.past.count == 1)
    }

    @Test("the tail of past spots stays short enough for a widget to read")
    func pastIsCapped() {
        var record = ParkingRecord.empty
        for day in 1...(ParkingRecord.pastLimit + 5) {
            record.park(ParkingSpot(parkedAt: Clock.sydney(2026, 8, 19, 13).addingTimeInterval(Double(day) * 86400)))
        }
        record.collect(at: Clock.sydney(2026, 12, 1, 9))

        #expect(record.past.count == ParkingRecord.pastLimit)
        // Most recently collected first.
        #expect(record.past[0].collectedAt == Clock.sydney(2026, 12, 1, 9))
    }
}
