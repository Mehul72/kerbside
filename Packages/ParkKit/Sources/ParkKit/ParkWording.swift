import Foundation
import SignKit

/// Turns what ParkKit worked out into the words a person would use.
///
/// The rule every sentence here obeys: state what the sign says and what the
/// clock says, and attribute both. Nothing in this file tells anybody whether
/// they may park, and nothing here says a car is safe, fine or in trouble. A
/// countdown with no attribution reads as the app's own opinion, so every
/// phrase names the panel or the person it came from.
public enum ParkWording {

    // MARK: - Clock

    public static func clock(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    public static func dayAndClock(_ date: Date, relativeTo now: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = clock(date, in: timeZone)

        if calendar.isDate(date, inSameDayAs: now) { return time }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
        if let tomorrow, calendar.isDate(date, inSameDayAs: tomorrow) {
            return "\(time) tomorrow"
        }
        formatter.dateFormat = "EEEE"
        return "\(time) \(formatter.string(from: date))"
    }

    // MARK: - Duration

    /// A span of time, said briefly enough to fit in a Dynamic Island.
    public static func span(_ seconds: TimeInterval) -> String {
        let total = Int(abs(seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 && minutes == 0 { return "under a minute" }
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    /// What the countdown reads. Overrun is stated, not hidden, because a car
    /// that is past its limit is exactly when a person most needs to be told
    /// the truth.
    public static func remaining(_ seconds: TimeInterval) -> String {
        seconds >= 0 ? "\(span(seconds)) left" : "\(span(seconds)) over"
    }

    // MARK: - Limits

    /// What a candidate means, in one sentence that names its panel.
    public static func describe(_ candidate: LimitCandidate, in timeZone: TimeZone) -> String {
        let allowance = Wording.describe(candidate.panel.restriction)

        if let lifts = candidate.restrictionLifts {
            return "\(allowance) stops applying at \(dayAndClock(lifts, relativeTo: candidate.parkedAt, in: timeZone))"
                + ", before the allowance is used up."
        }

        if candidate.startsLater {
            return "\(allowance) starts at \(dayAndClock(candidate.clockStarts, relativeTo: candidate.parkedAt, in: timeZone))"
                + " and runs out at \(dayAndClock(candidate.allowanceEnds, relativeTo: candidate.parkedAt, in: timeZone))."
        }

        return "\(allowance) runs out at "
            + "\(dayAndClock(candidate.allowanceEnds, relativeTo: candidate.parkedAt, in: timeZone))."
    }

    /// Names a limit by where it came from. The sign's own wording is reused
    /// for a sign's allowance so the app describes a plate in the same words
    /// everywhere it describes one.
    public static func describe(_ source: LimitSource) -> String {
        switch source {
        case .sign(let minutes):
            "The \(Wording.duration(minutes)) parking on this sign"
        case .chosen(let minutes):
            "The \(Wording.duration(minutes)) limit you set"
        }
    }

    /// The line under the countdown, which always says where the number came
    /// from.
    ///
    /// - Parameter now: when supplied, a limit already passed is put in the past
    ///   tense. A sentence that says a limit "runs out" at a time that has been
    ///   and gone reads as though nothing has happened.
    public static func attribution(
        _ limit: ParkingLimit,
        at now: Date? = nil,
        in timeZone: TimeZone
    ) -> String {
        switch limit {
        case .openEnded:
            return "No limit recorded."
        case .expires(let at, let source):
            let time = clock(at, in: timeZone)
            let passed = now.map { at <= $0 } ?? false
            return "\(describe(source)) \(passed ? "ran" : "runs") out at \(time)."
        }
    }

    // MARK: - Badges

    /// A panel reduced to the few characters a plate paints largest, for the
    /// places a whole plate will not fit: a widget, the Dynamic Island, a row
    /// in a list.
    ///
    /// Derived from the restriction rather than taken from the first line of
    /// what was photographed. A sign whose text broke across lines gives a
    /// first line of `NO`, which says nothing and looks like a mistake; the
    /// restriction always knows what the panel was.
    public static func plateHeadline(_ panel: Panel) -> String {
        switch panel.restriction {
        case .noParking:
            "NO PARKING"
        case .noStopping:
            "NO STOPPING"
        case .timeLimited(let minutes):
            allowanceBadge(minutes)
        }
    }

    /// The way NSW paints an allowance: whole hours as `1P`, `2P`, `4P`, and
    /// the two common fractions as `1/4P` and `1/2P`. Anything else is stated
    /// in minutes rather than rounded into a plate that does not exist.
    static func allowanceBadge(_ minutes: Int) -> String {
        switch minutes {
        case 15: "1/4P"
        case 30: "1/2P"
        case 45: "3/4P"
        case let value where value % 60 == 0: "\(value / 60)P"
        default: "\(minutes) MIN"
        }
    }

    /// The walk, with the number agreeing with its noun. "About 1 minutes on
    /// foot" is the kind of thing that makes an interface look unfinished.
    public static func walk(minutes: Int) -> String {
        minutes == 1 ? "About a minute on foot." : "About \(minutes) minutes on foot."
    }

    // MARK: - Place

    /// How far the car is, and which way. Says when a fix was too loose to
    /// point with rather than drawing a confident arrow at a guess.
    public static func place(from here: Coordinate, to car: Coordinate) -> String {
        let metres = Geo.distance(from: here, to: car)
        let distance = Geo.describe(metres: metres)
        guard car.isPrecise else { return "about \(distance) away" }
        return "\(distance) \(Geo.compassPoint(Geo.bearing(from: here, to: car)))"
    }

    // MARK: - Reminders

    /// What a notification says. Two lines: what is happening, and which panel
    /// says so.
    public static func notification(
        for reminder: Reminder,
        spot: ParkingSpot,
        in timeZone: TimeZone
    ) -> (title: String, body: String) {
        switch reminder.kind {
        case .timeToLeave(let walkMinutes):
            let walk = walkMinutes <= 1
                ? "The car is a minute away"
                : "The car is about \(walkMinutes) minutes' walk"
            return ("Time to head back", "\(walk). \(attribution(spot.limit, in: timeZone))")

        case .limitEndsSoon(let minutesBefore):
            return (
                "\(minutesBefore) minutes left",
                attribution(spot.limit, in: timeZone)
            )
        case .limitEnded:
            let time = spot.limit.expiry.map { clock($0, in: timeZone) } ?? "now"
            let source = spot.limit.source.map(describe) ?? "The limit"
            return ("The limit has passed", "\(source) ran out at \(time).")
        case .restrictionBegins(let panel):
            return (
                "A rule starts now",
                "Where you left the car: \(Wording.describe(panel))."
            )
        }
    }

    // MARK: - Spot

    /// The heading over a saved spot.
    public static func parked(_ spot: ParkingSpot, relativeTo now: Date, in timeZone: TimeZone) -> String {
        "Parked \(dayAndClock(spot.parkedAt, relativeTo: now, in: timeZone))"
    }
}
