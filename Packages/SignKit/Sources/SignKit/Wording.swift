import Foundation

/// Turns parsed values back into the words a person would use.
///
/// This lives in SignKit rather than the app because what a panel says is the
/// product, and the product should be testable without a simulator. Nothing
/// here decides anything; it only restates what was read.
public enum Wording {
    public static func describe(_ panel: Panel) -> String {
        var parts = [describe(panel.restriction)]
        parts.append(describe(panel.days))
        parts.append(describe(panel.times))
        if let direction = describe(panel.direction) {
            parts.append(direction)
        }
        for qualifier in panel.qualifiers {
            parts.append(describe(qualifier))
        }
        return parts.joined(separator: ", ")
    }

    public static func describe(_ restriction: Restriction) -> String {
        switch restriction {
        case .noParking:
            return "No parking"
        case .noStopping:
            return "No stopping"
        case .timeLimited(let minutes):
            return "\(duration(minutes)) parking"
        }
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, let m):
            return "\(m) minute"
        case (let h, 0):
            return h == 1 ? "1 hour" : "\(h) hour"
        case (let h, let m):
            return "\(h) hour \(m) minute"
        }
    }

    public static func describe(_ days: DaySet) -> String {
        if days == .allDays { return "every day" }

        var phrases: [String] = []
        var index = 0
        let order = Weekdays.inWeekOrder
        while index < order.count {
            guard days.weekdays.contains(order[index]) else {
                index += 1
                continue
            }
            var last = index
            while last + 1 < order.count, days.weekdays.contains(order[last + 1]) {
                last += 1
            }
            if last - index >= 2 {
                phrases.append("\(name(order[index])) to \(name(order[last]))")
            } else {
                for position in index...last { phrases.append(name(order[position])) }
            }
            index = last + 1
        }

        if days.includesPublicHolidays { phrases.append("public holidays") }
        return phrases.isEmpty ? "no days named" : phrases.joined(separator: ", ")
    }

    static func name(_ day: Weekdays) -> String {
        guard let index = Weekdays.inWeekOrder.firstIndex(of: day) else { return "?" }
        return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][index]
    }

    public static func describe(_ times: TimeWindows) -> String {
        if times.isAllDay { return "at all times" }
        let windows = times.ranges.map { "\(clock($0.start)) to \(clock($0.end))" }
        guard let last = windows.last, windows.count > 1 else { return windows[0] }
        return windows.dropLast().joined(separator: ", ") + " and " + last
    }

    static func clock(_ minutes: Int) -> String {
        if minutes == 0 || minutes == 1440 { return "midnight" }
        if minutes == 720 { return "noon" }
        let hour24 = minutes / 60
        let minute = minutes % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "am" : "pm"
        return minute == 0 ? "\(hour12)\(suffix)" : String(format: "%d:%02d%@", hour12, minute, suffix)
    }

    /// Nil when the sign named no direction, so the caller can leave it out
    /// rather than claim the panel covers both sides.
    public static func describe(_ direction: Direction) -> String? {
        switch direction {
        case .left: "to the left of the sign"
        case .right: "to the right of the sign"
        case .both: "on both sides of the sign"
        case .unspecified: nil
        }
    }

    public static func describe(_ qualifier: Qualifier) -> String {
        switch qualifier {
        case .ticket: "ticket required"
        case .meter: "meter payment required"
        }
    }

    /// Said plainly, because an unknown is shown to the person, not logged.
    public static func describe(_ reason: UnknownReason) -> String {
        switch reason {
        case .emptyPanel:
            "This panel had no text on it."
        case .noRestrictionFound:
            "No restriction was named on this panel."
        case .unrecognisedLine(let line):
            "This line was not understood: \(line)"
        case .malformedTimeRange(let line):
            "This time range does not describe a window: \(line)"
        case .conflictingRestrictions:
            "This panel named more than one restriction."
        case .conflictingDaySets:
            "This panel named more than one set of days."
        }
    }
}
