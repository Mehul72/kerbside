import Foundation

public enum ChangeKind: String, Hashable, Sendable, Codable {
    case begins
    case ends
}

public struct Change: Hashable, Sendable {
    public var panel: Panel
    public var kind: ChangeKind
    public var at: Date

    public init(panel: Panel, kind: ChangeKind, at: Date) {
        self.panel = panel
        self.kind = kind
        self.at = at
    }
}

public struct Evaluation: Hashable, Sendable {
    public var instant: Date
    public var active: [Panel]
    public var inactive: [Panel]
    public var unknowns: [Unknown]
    public var nextChange: Change?

    public init(
        instant: Date,
        active: [Panel],
        inactive: [Panel],
        unknowns: [Unknown],
        nextChange: Change?
    ) {
        self.instant = instant
        self.active = active
        self.inactive = inactive
        self.unknowns = unknowns
        self.nextChange = nextChange
    }
}

/// Determines which parsed panels cover an injected instant.
///
/// Evaluation is descriptive: it returns active and inactive rules, never a
/// parking verdict. Calendar arithmetic is performed in the supplied time zone
/// so Sydney daylight-saving transitions come from tzdata.
public struct Evaluator: Sendable {
    private let publicHolidays: any PublicHolidayProvider

    public init(publicHolidays: any PublicHolidayProvider = NSWPublicHolidays.current) {
        self.publicHolidays = publicHolidays
    }

    public static func evaluate(_ sign: Sign, at instant: Date, in timeZone: TimeZone) -> Evaluation {
        Evaluator().evaluate(sign, at: instant, in: timeZone)
    }

    public func evaluate(_ sign: Sign, at instant: Date, in timeZone: TimeZone) -> Evaluation {
        let calendar = Self.calendar(in: timeZone)
        var active: [Panel] = []
        var inactive: [Panel] = []

        for panel in sign.parsedPanels {
            if isActive(panel, at: instant, calendar: calendar) {
                active.append(panel)
            } else {
                inactive.append(panel)
            }
        }

        return Evaluation(
            instant: instant,
            active: active,
            inactive: inactive,
            unknowns: sign.unknowns,
            nextChange: nextChange(in: sign.parsedPanels, after: instant, calendar: calendar)
        )
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func isActive(_ panel: Panel, at instant: Date, calendar: Calendar) -> Bool {
        let today = localDate(containing: instant, calendar: calendar)
        let yesterday = adding(days: -1, to: today, calendar: calendar)

        return [yesterday, today].contains { ruleDate in
            guard dayMatches(panel.days, on: ruleDate, calendar: calendar),
                  let interval = interval(for: panel.times, on: ruleDate, calendar: calendar)
            else { return false }
            return instant >= interval.start && instant < interval.end
        }
    }

    private func nextChange(
        in panels: [Panel],
        after instant: Date,
        calendar: Calendar
    ) -> Change? {
        var earliest: Change?

        for panel in panels {
            guard let change = nextChange(for: panel, after: instant, calendar: calendar) else {
                continue
            }
            if earliest == nil || change.at < earliest!.at {
                earliest = change
            }
        }
        return earliest
    }

    private func nextChange(for panel: Panel, after instant: Date, calendar: Calendar) -> Change? {
        let today = localDate(containing: instant, calendar: calendar)
        var candidates = Set<Date>()

        // A weekly panel normally changes within seven days. A full year also
        // covers holiday-only panels and consecutive-holiday suppression while
        // keeping a corrupt provider from causing an unbounded search.
        for offset in -1...370 {
            let ruleDate = adding(days: offset, to: today, calendar: calendar)
            guard dayMatches(panel.days, on: ruleDate, calendar: calendar),
                  let interval = interval(for: panel.times, on: ruleDate, calendar: calendar)
            else { continue }
            if interval.start > instant { candidates.insert(interval.start) }
            if interval.end > instant { candidates.insert(interval.end) }
        }

        for candidate in candidates.sorted() {
            let wasActive = isActive(
                panel,
                at: candidate.addingTimeInterval(-0.001),
                calendar: calendar
            )
            let isActiveNow = isActive(panel, at: candidate, calendar: calendar)
            guard wasActive != isActiveNow else { continue }
            return Change(
                panel: panel,
                kind: isActiveNow ? .begins : .ends,
                at: candidate
            )
        }
        return nil
    }

    private func dayMatches(_ days: DaySet, on date: LocalDate, calendar: Calendar) -> Bool {
        if publicHolidays.isPublicHoliday(date) {
            return days.includesPublicHolidays
        }
        return days.weekdays.contains(weekday(for: date, calendar: calendar))
    }

    private func weekday(for date: LocalDate, calendar: Calendar) -> Weekdays {
        guard let instant = calendar.date(from: components(for: date)),
              let weekday = calendar.dateComponents([.weekday], from: instant).weekday
        else { return [] }
        return switch weekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: []
        }
    }

    private func interval(for range: TimeRange, on date: LocalDate, calendar: Calendar) -> DateInterval? {
        guard let start = boundary(
            on: date,
            minutes: range.start,
            repeatedTimePolicy: .first,
            calendar: calendar
        ) else { return nil }

        let endDate = range.crossesMidnight
            ? adding(days: 1, to: date, calendar: calendar)
            : date
        guard let end = boundary(
            on: endDate,
            minutes: range.end,
            repeatedTimePolicy: .last,
            calendar: calendar
        ), end > start else { return nil }

        return DateInterval(start: start, end: end)
    }

    /// Resolves a wall-clock boundary. Missing spring-forward times move to the
    /// next real wall time; repeated times use the first instant for a start and
    /// the last instant for an end, so a stated window does not lose an hour.
    private func boundary(
        on date: LocalDate,
        minutes: Int,
        repeatedTimePolicy: Calendar.RepeatedTimePolicy,
        calendar: Calendar
    ) -> Date? {
        if minutes == 1440 {
            let tomorrow = adding(days: 1, to: date, calendar: calendar)
            return calendar.date(from: components(for: tomorrow))
        }

        guard let dayStart = calendar.date(from: components(for: date)) else { return nil }
        var clock = DateComponents()
        clock.hour = minutes / 60
        clock.minute = minutes % 60
        clock.second = 0
        return calendar.nextDate(
            after: dayStart.addingTimeInterval(-1),
            matching: clock,
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: repeatedTimePolicy,
            direction: .forward
        )
    }

    private func localDate(containing instant: Date, calendar: Calendar) -> LocalDate {
        let values = calendar.dateComponents([.year, .month, .day], from: instant)
        return LocalDate(year: values.year!, month: values.month!, day: values.day!)
    }

    private func adding(days: Int, to date: LocalDate, calendar: Calendar) -> LocalDate {
        var midday = components(for: date)
        midday.hour = 12
        let instant = calendar.date(from: midday)!
        let result = calendar.date(byAdding: .day, value: days, to: instant)!
        return localDate(containing: result, calendar: calendar)
    }

    private func components(for date: LocalDate) -> DateComponents {
        DateComponents(year: date.year, month: date.month, day: date.day)
    }
}
