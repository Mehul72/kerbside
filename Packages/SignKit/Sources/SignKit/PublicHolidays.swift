import Foundation

/// A calendar date without a time or time zone.
///
/// Parking signs name local days, so public holidays are represented as local
/// dates rather than as instants that could move to another day when decoded.
public struct LocalDate: Hashable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Supplies holidays to the evaluator. Tests and callers can inject a table
/// without making SignKit read the clock, locale, network, or device calendar.
public protocol PublicHolidayProvider: Sendable {
    func isPublicHoliday(_ date: LocalDate) -> Bool
}

/// Statewide NSW public holidays. Local and part-day holidays are deliberately
/// excluded because the app does not yet know the photographed sign's council.
///
/// This table is sourced from the NSW Government public-holiday calendar and
/// must be extended as new years are gazetted:
/// https://www.nsw.gov.au/about-nsw/public-holidays
public struct NSWPublicHolidays: PublicHolidayProvider, Sendable {
    public static let current = NSWPublicHolidays()

    private let dates: Set<LocalDate>

    public init() {
        dates = Set(Self.statewideDates)
    }

    public init(dates: Set<LocalDate>) {
        self.dates = dates
    }

    public func isPublicHoliday(_ date: LocalDate) -> Bool {
        dates.contains(date)
    }

    private static let statewideDates: [LocalDate] = [
        // 2025
        .init(year: 2025, month: 1, day: 1),
        .init(year: 2025, month: 1, day: 27),
        .init(year: 2025, month: 4, day: 18),
        .init(year: 2025, month: 4, day: 19),
        .init(year: 2025, month: 4, day: 20),
        .init(year: 2025, month: 4, day: 21),
        .init(year: 2025, month: 4, day: 25),
        .init(year: 2025, month: 6, day: 9),
        .init(year: 2025, month: 10, day: 6),
        .init(year: 2025, month: 12, day: 25),
        .init(year: 2025, month: 12, day: 26),

        // 2026
        .init(year: 2026, month: 1, day: 1),
        .init(year: 2026, month: 1, day: 26),
        .init(year: 2026, month: 4, day: 3),
        .init(year: 2026, month: 4, day: 4),
        .init(year: 2026, month: 4, day: 5),
        .init(year: 2026, month: 4, day: 6),
        .init(year: 2026, month: 4, day: 25),
        .init(year: 2026, month: 4, day: 27),
        .init(year: 2026, month: 6, day: 8),
        .init(year: 2026, month: 10, day: 5),
        .init(year: 2026, month: 12, day: 25),
        .init(year: 2026, month: 12, day: 26),
        .init(year: 2026, month: 12, day: 28),

        // 2027
        .init(year: 2027, month: 1, day: 1),
        .init(year: 2027, month: 1, day: 26),
        .init(year: 2027, month: 3, day: 26),
        .init(year: 2027, month: 3, day: 27),
        .init(year: 2027, month: 3, day: 28),
        .init(year: 2027, month: 3, day: 29),
        .init(year: 2027, month: 4, day: 25),
        .init(year: 2027, month: 4, day: 26),
        .init(year: 2027, month: 6, day: 14),
        .init(year: 2027, month: 10, day: 4),
        .init(year: 2027, month: 12, day: 25),
        .init(year: 2027, month: 12, day: 26),
        .init(year: 2027, month: 12, day: 27),
        .init(year: 2027, month: 12, day: 28),
    ]
}
