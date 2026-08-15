import Foundation
import SignKit

/// One car, left in one place, under one sign.
///
/// Everything the interface, the widgets and the Live Activity need is here,
/// so the record is the single thing that gets written to the shared container
/// and the single thing that gets read back out of it.
public struct ParkingSpot: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var parkedAt: Date

    /// Nil when a fix was refused or never arrived. A spot with no coordinate
    /// is still a spot: it remembers the time, the sign and the note, and the
    /// interface says plainly that it cannot point the way back.
    public var coordinate: Coordinate?

    /// Whatever a person wants to add. Levels and bay numbers are the usual
    /// case, which is why the interface suggests one.
    public var note: String

    /// The sign that was standing over the car, if one was read. Kept whole,
    /// unknown panels included, so the record cannot become tidier than the
    /// street was.
    public var sign: Sign?

    public var limit: ParkingLimit

    /// A photograph of the spot, held in the shared container beside this
    /// record. Only the name is stored, so the record stays small enough to
    /// decode in a widget.
    public var photoFilename: String?

    /// Set when the car was collected, which is what moves a spot into the
    /// past without deleting what it recorded.
    public var collectedAt: Date?

    public init(
        id: UUID = UUID(),
        parkedAt: Date,
        coordinate: Coordinate? = nil,
        note: String = "",
        sign: Sign? = nil,
        limit: ParkingLimit = .openEnded,
        photoFilename: String? = nil,
        collectedAt: Date? = nil
    ) {
        self.id = id
        self.parkedAt = parkedAt
        self.coordinate = coordinate
        self.note = note
        self.sign = sign
        self.limit = limit
        self.photoFilename = photoFilename
        self.collectedAt = collectedAt
    }

    /// How the sign read at a given instant. Nil when no sign was recorded,
    /// which is a different thing from a sign that said nothing.
    public func evaluation(
        at instant: Date,
        in timeZone: TimeZone,
        publicHolidays: any PublicHolidayProvider = NSWPublicHolidays.current
    ) -> Evaluation? {
        guard let sign else { return nil }
        return Evaluator(publicHolidays: publicHolidays).evaluate(sign, at: instant, in: timeZone)
    }
}

/// Everything Kerbside remembers, which is one car now and a short tail of
/// where it has been.
public struct ParkingRecord: Hashable, Sendable, Codable {
    public var active: ParkingSpot?

    /// Most recently collected first.
    public var past: [ParkingSpot]

    /// Long enough to answer "where did I leave it on Tuesday", short enough
    /// that the shared file stays small enough for a widget to decode quickly.
    public static let pastLimit = 20

    public static let empty = ParkingRecord(active: nil, past: [])

    public init(active: ParkingSpot? = nil, past: [ParkingSpot] = []) {
        self.active = active
        self.past = past
    }

    /// Parks a car. Any spot already active is treated as collected at the
    /// moment the new one starts, because a person only has one car in one
    /// place and losing the old record would lose where they had been.
    public mutating func park(_ spot: ParkingSpot) {
        if let existing = active {
            retire(existing, at: spot.parkedAt)
        }
        active = spot
    }

    /// Marks the active spot collected and moves it into the past.
    public mutating func collect(at instant: Date) {
        guard let existing = active else { return }
        retire(existing, at: instant)
        active = nil
    }

    private mutating func retire(_ spot: ParkingSpot, at instant: Date) {
        var collected = spot
        collected.collectedAt = instant
        past.insert(collected, at: 0)
        if past.count > Self.pastLimit {
            past.removeLast(past.count - Self.pastLimit)
        }
    }
}
