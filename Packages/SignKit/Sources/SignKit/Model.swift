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

/// What a panel restricts. Zone types such as loading and bus zones are not in
/// this set yet, so a panel carrying one fails to parse rather than being
/// approximated by a neighbouring case.
public enum Restriction: Hashable, Sendable {
    case timeLimited(minutes: Int)
    case noParking
    case noStopping
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
