import Foundation

/// What one line of a panel turned out to be.
enum LineToken: Hashable {
    case restriction(Restriction, qualifiers: [Qualifier])
    /// One line may name several windows, as `6AM - 10AM & 3PM - 6PM` does.
    case timeRanges([TimeRange])
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

        // "2P TICKET" and "1P METER" put the allowance and how it is paid for
        // on one line, so a trailing qualifier is peeled off before the rest is
        // read as a restriction.
        let (core, peeled) = peelQualifiers(from: text)
        if !core.isEmpty, let restriction = parseRestriction(core) {
            return (directions, .restriction(restriction, qualifiers: peeled))
        }
        switch parseTimeRange(text) {
        case .ranges(let ranges): return (directions, .timeRanges(ranges))
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

    /// Splits trailing qualifier words off a line, leaving what comes before.
    ///
    /// Only from the end, and only words that are qualifiers on their own. A
    /// qualifier in the middle of a line would mean the line is something this
    /// parser does not know, and guessing at it is what the invariants forbid.
    static func peelQualifiers(from text: String) -> (core: String, qualifiers: [Qualifier]) {
        var words = text.split(separator: " ").map(String.init)
        var found: [Qualifier] = []

        while let last = words.last, let qualifier = parseQualifier(last) {
            found.insert(qualifier, at: 0)
            words.removeLast()
        }
        return (words.joined(separator: " "), found)
    }

    // MARK: restrictions

    static func parseRestriction(_ text: String) -> Restriction? {
        switch text {
        case "NO STOPPING": return .noStopping
        case "NO PARKING": return .noParking
        default: break
        }

        // "LOADING ZONE", "BUS ZONE". A zone this parser does not know stays
        // unread rather than being folded into one it does.
        if text.hasSuffix(" ZONE") {
            let name = String(text.dropLast(" ZONE".count)).lowercased()
            return Zone(rawValue: name).map(Restriction.zone)
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
        case ranges([TimeRange])
        /// Recognisably a time range, but not a usable one.
        case malformed
        case notATimeRange
    }

    static func parseTimeRange(_ text: String) -> TimeRangeParse {
        if text == "ALL TIMES" || text == "AT ALL TIMES" || text == "ALL HOURS" {
            return .ranges([.allDay])
        }

        var ranges: [TimeRange] = []
        var sawMalformed = false
        for window in splitWindows(text) {
            switch parseSingleRange(window) {
            case .ranges(let parsed): ranges.append(contentsOf: parsed)
            case .malformed: sawMalformed = true
            // One unreadable window makes the whole line unreadable. Keeping
            // the half that parsed would silently shrink the restriction.
            case .notATimeRange: return .notATimeRange
            }
        }
        if sawMalformed { return .malformed }
        return ranges.isEmpty ? .notATimeRange : .ranges(ranges)
    }

    /// A peak hour panel writes its second window after an ampersand or "AND".
    private static func splitWindows(_ text: String) -> [String] {
        text.replacingOccurrences(of: " AND ", with: "&")
            .split(separator: "&")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func parseSingleRange(_ text: String) -> TimeRangeParse {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return .notATimeRange }

        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        let endText = parts[1].trimmingCharacters(in: .whitespaces)
        guard let start = parseClock(startText, isEnd: false),
              let end = parseClock(endText, isEnd: true)
        else { return .notATimeRange }

        guard let resolved = resolveMeridiems(start: start, end: end) else {
            return .notATimeRange
        }
        guard let range = TimeRange(start: resolved.start, end: resolved.end) else {
            return .malformed
        }
        return .ranges([range])
    }

    /// A clock reading, which may not yet know whether it is morning.
    ///
    /// NSW signs print the minutes and the meridiem in superscript, and text
    /// recognition frequently drops them, turning `9:30AM - 3:30PM` into
    /// `930-330`. The digits survive; which half of the day they belong to has
    /// to be recovered from the pair.
    struct Clock {
        var minutesIntoHalfDay: Int
        var meridiem: Meridiem?
        /// Already absolute, as MIDNIGHT and NOON are.
        var fixed: Int?
    }

    enum Meridiem {
        case morning
        case afternoon
    }

    /// Works out which half of the day each end of a window belongs to.
    ///
    /// Where a sign states the meridiem it is obeyed. Where it does not, only
    /// two situations are unambiguous, and anything else stays unread:
    ///
    /// * The stated hours run backwards, as `9:30 - 3:30` does. A window can
    ///   only do that by crossing noon, so it is morning to afternoon.
    /// * One end is stated. The other is then whichever half lets the window
    ///   run forward through the day, provided only one half does.
    ///
    /// `6:30 - 9:30` is refused: a morning peak and an evening one are equally
    /// consistent with those digits, and picking either would be a guess.
    static func resolveMeridiems(start: Clock, end: Clock) -> (start: Int, end: Int)? {
        if let startFixed = start.fixed, let endFixed = end.fixed {
            return (startFixed, endFixed)
        }

        func absolute(_ clock: Clock, _ meridiem: Meridiem) -> Int {
            if let fixed = clock.fixed { return fixed }
            let hour = clock.minutesIntoHalfDay / 60
            let minute = clock.minutesIntoHalfDay % 60
            let hour24 = meridiem == .morning
                ? (hour == 12 ? 0 : hour)
                : (hour == 12 ? 12 : hour + 12)
            return hour24 * 60 + minute
        }

        let startOptions = start.fixed != nil
            ? [Meridiem.morning]
            : start.meridiem.map { [$0] } ?? [.morning, .afternoon]
        let endOptions = end.fixed != nil
            ? [Meridiem.morning]
            : end.meridiem.map { [$0] } ?? [.morning, .afternoon]

        // Both stated: obey the sign, including a window that crosses midnight.
        if start.meridiem != nil || start.fixed != nil,
           end.meridiem != nil || end.fixed != nil {
            return (absolute(start, startOptions[0]), absolute(end, endOptions[0]))
        }

        var solutions: [(start: Int, end: Int)] = []
        for startMeridiem in startOptions {
            for endMeridiem in endOptions {
                let from = absolute(start, startMeridiem)
                let to = absolute(end, endMeridiem)
                // Forward through one day. A sign that means to cross midnight
                // prints the meridiem, so an inferred window never does.
                if to > from { solutions.append((from, to)) }
            }
        }
        return solutions.count == 1 ? solutions[0] : nil
    }

    /// Minutes from midnight, or nil if this is not a clock time.
    ///
    /// `isEnd` only affects MIDNIGHT, which closes a window at 24:00 but opens
    /// one at 00:00.
    static func parseClock(_ text: String, isEnd: Bool) -> Clock? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        if compact == "MIDNIGHT" {
            return Clock(minutesIntoHalfDay: 0, meridiem: nil, fixed: isEnd ? 1440 : 0)
        }
        if compact == "NOON" || compact == "MIDDAY" {
            return Clock(minutesIntoHalfDay: 0, meridiem: nil, fixed: 720)
        }
        // NSW writes the end of a morning window as "12 NOON", which names the
        // hour and the marker together.
        if compact == "12NOON" || compact == "12MIDDAY" {
            return Clock(minutesIntoHalfDay: 0, meridiem: nil, fixed: 720)
        }
        if compact == "12MIDNIGHT" {
            return Clock(minutesIntoHalfDay: 0, meridiem: nil, fixed: isEnd ? 1440 : 0)
        }

        var meridiem: Meridiem?
        var body = compact
        if compact.hasSuffix("AM") {
            meridiem = .morning
            body = String(compact.dropLast(2))
        } else if compact.hasSuffix("PM") {
            meridiem = .afternoon
            body = String(compact.dropLast(2))
        }
        guard !body.isEmpty else { return nil }

        let digits = body.replacingOccurrences(of: ".", with: ":")
        let hour: Int
        let minute: Int

        if digits.contains(":") {
            let pieces = digits.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2, let parsedHour = Int(pieces[0]),
                  pieces[1].count == 2, let parsedMinute = Int(pieces[1])
            else { return nil }
            hour = parsedHour
            minute = parsedMinute
        } else {
            // Superscript minutes come back joined to the hour: 930, 1230.
            guard digits.allSatisfy(\.isNumber) else { return nil }
            switch digits.count {
            case 1, 2:
                guard let parsed = Int(digits) else { return nil }
                hour = parsed
                minute = 0
            case 3, 4:
                guard let parsedHour = Int(digits.dropLast(2)),
                      let parsedMinute = Int(digits.suffix(2))
                else { return nil }
                hour = parsedHour
                minute = parsedMinute
            default:
                return nil
            }
        }

        guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
        return Clock(minutesIntoHalfDay: hour * 60 + minute, meridiem: meridiem, fixed: nil)
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
        if text == "ALL DAYS" || text == "EVERY DAY" || text == "EVERYDAY" || text == "ANY DAY"
            || text == "7 DAYS" || text == "7DAYS" || text == "SEVEN DAYS" {
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
