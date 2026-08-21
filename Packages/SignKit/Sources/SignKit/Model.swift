import Foundation

/// The seven days, as an option set so that any day set has exactly one
/// representation regardless of how the sign spelled it.
public struct Weekdays: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let monday = Weekdays(rawValue: 1 << 0)
    public static let tuesday = Weekdays(rawValue: 1 << 1)
    public static let wednesday = Weekdays(rawValue: 1 << 2)
    public static let thursday = Weekdays(rawValue: 1 << 3)
    public static let friday = Weekdays(rawValue: 1 << 4)
    public static let saturday = Weekdays(rawValue: 1 << 5)
    public static let sunday = Weekdays(rawValue: 1 << 6)

    public static let all: Weekdays = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
    ]

    /// Monday first, the order NSW signs are written in.
    public static let inWeekOrder: [Weekdays] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
    ]

    static let codingNames = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// Always Monday first, so encoding a day set is deterministic.
    var codingNameList: [String] {
        Weekdays.inWeekOrder.indices.compactMap { index in
            contains(Weekdays.inWeekOrder[index]) ? Weekdays.codingNames[index] : nil
        }
    }

    static func named(_ name: String) -> Weekdays? {
        guard let index = codingNames.firstIndex(of: name) else { return nil }
        return inWeekOrder[index]
    }
}

/// Which days a panel applies on. A panel that names no days applies on all of
/// them, which is resolved here at parse time rather than left to the evaluator.
public struct DaySet: Hashable, Sendable {
    public var weekdays: Weekdays
    public var includesPublicHolidays: Bool

    public init(weekdays: Weekdays, includesPublicHolidays: Bool = false) {
        self.weekdays = weekdays
        self.includesPublicHolidays = includesPublicHolidays
    }

    public static let allDays = DaySet(weekdays: .all, includesPublicHolidays: true)
}

/// A window within a day, in minutes from midnight.
///
/// `end` may be 1440 to mean the end of the day. `end < start` crosses midnight.
/// `end == start` is not a window and is rejected.
public struct TimeRange: Hashable, Sendable {
    public let start: Int
    public let end: Int

    public init?(start: Int, end: Int) {
        guard (0..<1440).contains(start), (0...1440).contains(end), start != end else { return nil }
        self.start = start
        self.end = end
    }

    public static let allDay = TimeRange(start: 0, end: 1440)!

    public var crossesMidnight: Bool { end < start }

    /// Half open: a window ending at 6pm does not include 6pm.
    public func contains(minutesFromMidnight minute: Int) -> Bool {
        crossesMidnight ? (minute >= start || minute < end) : (minute >= start && minute < end)
    }
}

/// The hours a panel applies, as one or more windows within a day.
///
/// Peak hour signs routinely name two, written either on one line as
/// `6AM - 10AM & 3PM - 6PM` or stacked on two. They are one panel with one
/// restriction, so they are held together rather than split into panels that
/// the sign does not have.
public struct TimeWindows: Hashable, Sendable {
    public let ranges: [TimeRange]

    /// Canonical form: deduplicated and ordered, so two spellings of the same
    /// hours cannot produce two different values. A panel that names no hours
    /// applies at all times.
    public init(_ ranges: [TimeRange]) {
        var seen = Set<TimeRange>()
        var kept: [TimeRange] = []
        for range in ranges where seen.insert(range).inserted {
            kept.append(range)
        }
        kept.sort { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
        self.ranges = kept.isEmpty ? [.allDay] : kept
    }

    public static let allDay = TimeWindows([.allDay])

    public var isAllDay: Bool { ranges == [.allDay] }

    public func contains(minutesFromMidnight minute: Int) -> Bool {
        ranges.contains { $0.contains(minutesFromMidnight: minute) }
    }
}

/// A stretch of kerb set aside for one kind of vehicle or one purpose.
///
/// A closed set, like `Restriction` itself. A zone Kerbside does not know is
/// left unread rather than folded into a neighbouring one: a mail zone is not
/// a loading zone, and a reader who was told it was would be misled about who
/// may stop there.
public enum Zone: String, Hashable, Sendable, CaseIterable {
    case loading
    case bus
    case taxi
    case works
    case mail
    case coach
    case truck

    /// What NSW paints on the plate.
    public var painted: String {
        "\(rawValue.uppercased()) ZONE"
    }
}

/// What a panel restricts.
///
/// A closed set on purpose. A panel carrying something not in it fails to parse
/// rather than being approximated by a neighbouring case.
public enum Restriction: Hashable, Sendable {
    case timeLimited(minutes: Int)
    case noParking
    case noStopping

    /// Kerb given over to buses, taxis, loading and the like. Prohibitive for
    /// an ordinary car, but not the same prohibition as no stopping, so it
    /// keeps its own case and its own words.
    case zone(Zone)
}

/// Which stretch of kerb a panel governs, relative to the pole.
///
/// Absence stays `.unspecified` and is never widened to `.both`, because
/// widening invents coverage the sign did not state.
public enum Direction: String, Hashable, Sendable, CaseIterable {
    case left
    case right
    case both
    case unspecified
}

/// A closed set on purpose. A free text case would let an unreadable line pass
/// as a qualifier, which is the silent guess the invariants forbid.
public enum Qualifier: String, Hashable, Sendable, CaseIterable {
    case ticket
    case meter
}
