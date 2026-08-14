import Foundation

/// What one line of a panel turned out to be.
enum LineToken: Hashable {
    case restriction(Restriction)
    case timeRange(TimeRange)
    case daySet(DaySet)
    case qualifier(Qualifier)
    case malformedTimeRange(String)
    case unrecognised(String)
}

/// Classifies each line on its own, without reference to its neighbours.
///
/// Independence is the point. A whole panel pattern that fails to match tells
/// you nothing; a line that fails to classify names itself.
enum LineClassifier {
    /// Arrows are pulled out first, since they can sit alongside the words
    /// rather than on a line of their own. A line that was only an arrow
    /// produces directions and no token.
    static func classify(_ line: String) -> (directions: [Direction], token: LineToken?) {
        var directions: [Direction] = []
        var remainder = ""
        for character in line {
            switch character {
            case "\u{2190}": directions.append(.left)
            case "\u{2192}": directions.append(.right)
            case "\u{2194}": directions.append(.both)
            default: remainder.append(character)
            }
        }

        let text = remainder.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return (directions, nil) }

        if let restriction = parseRestriction(text) {
            return (directions, .restriction(restriction))
        }
        switch parseTimeRange(text) {
        case .range(let range): return (directions, .timeRange(range))
        case .malformed: return (directions, .malformedTimeRange(text))
        case .notATimeRange: break
        }
        if let days = parseDaySet(text) {
            return (directions, .daySet(days))
        }
        if let qualifier = parseQualifier(text) {
            return (directions, .qualifier(qualifier))
        }
        return (directions, .unrecognised(text))
    }

    // MARK: restrictions

    static func parseRestriction(_ text: String) -> Restriction? {
        switch text {
        case "NO STOPPING": return .noStopping
        case "NO PARKING": return .noParking
        default: break
        }

        let words = text.split(separator: " ").map(String.init)

        // "2P", "1/2P"
        if words.count == 1, words[0].hasSuffix("P"), words[0].count > 1 {
            return minutesFromParkingForm(String(words[0].dropLast())).map(Restriction.timeLimited)
        }
        // "2 P"
        if words.count == 2, words[1] == "P" {
            return minutesFromParkingForm(words[0]).map(Restriction.timeLimited)
        }
        // "1 HOUR PARKING", "30 MINUTE PARKING"
        if words.count == 3, words[2] == "PARKING", let count = Int(words[0]), count > 0 {
            switch words[1] {
            case "HOUR", "HOURS", "HR", "HRS":
                return .timeLimited(minutes: count * 60)
            case "MINUTE", "MINUTES", "MIN", "MINS":
                return .timeLimited(minutes: count)
            default:
                return nil
            }
        }
        return nil
    }

    /// The part before the P: a whole number of hours, or a fraction of one.
    private static func minutesFromParkingForm(_ body: String) -> Int? {
        if let hours = Int(body) {
            guard hours > 0, hours <= 24 else { return nil }
            return hours * 60
        }
        let parts = body.split(separator: "/")
        guard parts.count == 2,
              let numerator = Int(parts[0]), let denominator = Int(parts[1]),
              numerator > 0, denominator > 0
        else { return nil }
        let total = numerator * 60
        guard total % denominator == 0 else { return nil }
        let minutes = total / denominator
        return minutes > 0 ? minutes : nil
    }

    // MARK: times

    enum TimeRangeParse {
        case range(TimeRange)
        /// Recognisably a time range, but not a usable one.
        case malformed
        case notATimeRange
    }

    static func parseTimeRange(_ text: String) -> TimeRangeParse {
        if text == "ALL TIMES" || text == "AT ALL TIMES" || text == "ALL HOURS" {
            return .range(.allDay)
        }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return .notATimeRange }

        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        let endText = parts[1].trimmingCharacters(in: .whitespaces)
        guard let start = parseClock(startText, isEnd: false),
              let end = parseClock(endText, isEnd: true)
        else { return .notATimeRange }

        guard let range = TimeRange(start: start, end: end) else { return .malformed }
        return .range(range)
    }

    /// Minutes from midnight, or nil if this is not a clock time.
    ///
    /// `isEnd` only affects MIDNIGHT, which closes a window at 24:00 but opens
    /// one at 00:00.
    static func parseClock(_ text: String, isEnd: Bool) -> Int? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        if compact == "MIDNIGHT" { return isEnd ? 1440 : 0 }
        if compact == "NOON" || compact == "MIDDAY" { return 720 }

        let isMorning: Bool
        let body: String
        if compact.hasSuffix("AM") {
            isMorning = true
            body = String(compact.dropLast(2))
        } else if compact.hasSuffix("PM") {
            isMorning = false
            body = String(compact.dropLast(2))
        } else {
            return nil
        }
        guard !body.isEmpty else { return nil }

        let digits = body.replacingOccurrences(of: ".", with: ":")
        let pieces = digits.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let hour = Int(pieces[0]), (1...12).contains(hour) else { return nil }

        var minute = 0
        if pieces.count == 2 {
            guard pieces[1].count == 2, let parsed = Int(pieces[1]), (0...59).contains(parsed) else { return nil }
            minute = parsed
        }

        let hour24 = isMorning ? (hour == 12 ? 0 : hour) : (hour == 12 ? 12 : hour + 12)
        return hour24 * 60 + minute
    }

    // MARK: days

    private static let dayNames: [String: Weekdays] = [
        "MON": .monday, "MONDAY": .monday,
        "TUE": .tuesday, "TUES": .tuesday, "TUESDAY": .tuesday,
        "WED": .wednesday, "WEDS": .wednesday, "WEDNESDAY": .wednesday,
        "THU": .thursday, "THUR": .thursday, "THURS": .thursday, "THURSDAY": .thursday,
        "FRI": .friday, "FRIDAY": .friday,
        "SAT": .saturday, "SATURDAY": .saturday,
        "SUN": .sunday, "SUNDAY": .sunday,
    ]

    private static let publicHolidayNames: Set<String> = [
        "PUBLIC HOLIDAY", "PUBLIC HOLIDAYS", "PUB HOL", "PUB HOLS", "PUBLIC HOL", "PUBLIC HOLS",
    ]

    static func parseDaySet(_ text: String) -> DaySet? {
        if text == "ALL DAYS" || text == "EVERY DAY" || text == "EVERYDAY" || text == "ANY DAY" {
            return .allDays
        }

        var weekdays = Weekdays()
        var publicHolidays = false
        var sawSomething = false

        for rawSegment in text.split(separator: ",") {
            let segment = rawSegment.trimmingCharacters(in: .whitespaces)
            guard !segment.isEmpty else { return nil }

            if publicHolidayNames.contains(segment) {
                publicHolidays = true
                sawSomething = true
                continue
            }

            let ends = segment.split(separator: "-", omittingEmptySubsequences: false)
            if ends.count == 2 {
                let fromText = ends[0].trimmingCharacters(in: .whitespaces)
                let toText = ends[1].trimmingCharacters(in: .whitespaces)
                guard let from = dayNames[fromText], let to = dayNames[toText],
                      let fromIndex = Weekdays.inWeekOrder.firstIndex(of: from),
                      let toIndex = Weekdays.inWeekOrder.firstIndex(of: to)
                else { return nil }
                // A range may wrap the week, as SAT - MON does.
                var index = fromIndex
                while true {
                    weekdays.insert(Weekdays.inWeekOrder[index])
                    if index == toIndex { break }
                    index = (index + 1) % Weekdays.inWeekOrder.count
                }
                sawSomething = true
                continue
            }

            guard ends.count == 1, let day = dayNames[segment] else { return nil }
            weekdays.insert(day)
            sawSomething = true
        }

        guard sawSomething, !weekdays.isEmpty || publicHolidays else { return nil }
        return DaySet(weekdays: weekdays, includesPublicHolidays: publicHolidays)
    }

    // MARK: qualifiers

    static func parseQualifier(_ text: String) -> Qualifier? {
        switch text {
        case "TICKET", "TICKETS": return .ticket
        case "METER", "METERS", "METERED": return .meter
        default: return nil
        }
    }
}
