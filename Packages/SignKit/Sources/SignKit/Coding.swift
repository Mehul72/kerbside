import Foundation

// Fixtures are written and read by hand, so the encoded form is chosen for
// legibility rather than for whatever the synthesised conformances would emit.
// Enums with payloads become a single key object, enums without stay strings.

enum ClockFormat {
    static func string(fromMinutes minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func minutes(fromString text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        guard (0...24).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

enum InstantFormat {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

private struct SingleKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    init(_ name: String) { self.stringValue = name }
}

private func decodingError(_ decoder: Decoder, _ message: String) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
}

extension Weekdays: Codable {
    public init(from decoder: Decoder) throws {
        let names = try decoder.singleValueContainer().decode([String].self)
        var days = Weekdays()
        for name in names {
            guard let day = Weekdays.named(name) else {
                throw decodingError(decoder, "unknown weekday \"\(name)\"")
            }
            days.insert(day)
        }
        self = days
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(codingNameList)
    }
}

extension DaySet: Codable {
    private enum Keys: String, CodingKey {
        case weekdays
        case publicHolidays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        weekdays = try container.decode(Weekdays.self, forKey: .weekdays)
        includesPublicHolidays = try container.decodeIfPresent(Bool.self, forKey: .publicHolidays) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encode(includesPublicHolidays, forKey: .publicHolidays)
    }
}

extension TimeRange: Codable {
    private enum Keys: String, CodingKey {
        case start
        case end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let startText = try container.decode(String.self, forKey: .start)
        let endText = try container.decode(String.self, forKey: .end)
        guard let start = ClockFormat.minutes(fromString: startText),
              let end = ClockFormat.minutes(fromString: endText),
              let range = TimeRange(start: start, end: end)
        else {
            throw decodingError(decoder, "invalid time range \(startText) to \(endText)")
        }
        self = range
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(ClockFormat.string(fromMinutes: start), forKey: .start)
        try container.encode(ClockFormat.string(fromMinutes: end), forKey: .end)
    }
}

extension TimeWindows: Codable {
    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([TimeRange].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ranges)
    }
}

extension Restriction: Codable {
    public init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            switch name {
            case "noParking": self = .noParking
            case "noStopping": self = .noStopping
            default: throw decodingError(decoder, "unknown restriction \"\(name)\"")
            }
            return
        }
        let container = try decoder.container(keyedBy: SingleKey.self)
        guard let key = container.allKeys.first, container.allKeys.count == 1 else {
            throw decodingError(decoder, "a restriction object needs exactly one key")
        }
        switch key.stringValue {
        case "timeLimited": self = .timeLimited(minutes: try container.decode(Int.self, forKey: key))
        case "zone":
            let name = try container.decode(String.self, forKey: key)
            guard let zone = Zone(rawValue: name) else {
                throw decodingError(decoder, "unknown zone \"\(name)\"")
            }
            self = .zone(zone)
        default: throw decodingError(decoder, "unknown restriction \"\(key.stringValue)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .noParking, .noStopping:
            var container = encoder.singleValueContainer()
            try container.encode(self == .noParking ? "noParking" : "noStopping")
        case .timeLimited(let minutes):
            var container = encoder.container(keyedBy: SingleKey.self)
            try container.encode(minutes, forKey: SingleKey("timeLimited"))
        case .zone(let zone):
            var container = encoder.container(keyedBy: SingleKey.self)
            try container.encode(zone.rawValue, forKey: SingleKey("zone"))
        }
    }
}

extension UnknownReason: Codable {
    public init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            switch name {
            case "emptyPanel": self = .emptyPanel
            case "noRestrictionFound": self = .noRestrictionFound
            case "conflictingRestrictions": self = .conflictingRestrictions
            case "conflictingDaySets": self = .conflictingDaySets
            default: throw decodingError(decoder, "unknown reason \"\(name)\"")
            }
            return
        }
        let container = try decoder.container(keyedBy: SingleKey.self)
        guard let key = container.allKeys.first, container.allKeys.count == 1 else {
            throw decodingError(decoder, "a reason object needs exactly one key")
        }
        let text = try container.decode(String.self, forKey: key)
        switch key.stringValue {
        case "unrecognisedLine": self = .unrecognisedLine(text)
        case "malformedTimeRange": self = .malformedTimeRange(text)
        default: throw decodingError(decoder, "unknown reason \"\(key.stringValue)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .emptyPanel, .noRestrictionFound, .conflictingRestrictions, .conflictingDaySets:
            var container = encoder.singleValueContainer()
            try container.encode(plainName)
        case .unrecognisedLine(let line):
            var container = encoder.container(keyedBy: SingleKey.self)
            try container.encode(line, forKey: SingleKey("unrecognisedLine"))
        case .malformedTimeRange(let line):
            var container = encoder.container(keyedBy: SingleKey.self)
            try container.encode(line, forKey: SingleKey("malformedTimeRange"))
        }
    }

    private var plainName: String {
        switch self {
        case .emptyPanel: "emptyPanel"
        case .noRestrictionFound: "noRestrictionFound"
        case .conflictingRestrictions: "conflictingRestrictions"
        case .conflictingDaySets: "conflictingDaySets"
        case .unrecognisedLine: "unrecognisedLine"
        case .malformedTimeRange: "malformedTimeRange"
        }
    }
}

extension Direction: Codable {}
extension Qualifier: Codable {}

extension Panel: Codable {
    private enum Keys: String, CodingKey {
        case restriction
        case days
        case times
        case direction
        case qualifiers
        case rawText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        restriction = try container.decode(Restriction.self, forKey: .restriction)
        days = try container.decodeIfPresent(DaySet.self, forKey: .days) ?? .allDays
        times = try container.decodeIfPresent(TimeWindows.self, forKey: .times) ?? .allDay
        direction = try container.decodeIfPresent(Direction.self, forKey: .direction) ?? .unspecified
        qualifiers = try container.decodeIfPresent([Qualifier].self, forKey: .qualifiers) ?? []
        rawText = try container.decode(String.self, forKey: .rawText)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(restriction, forKey: .restriction)
        try container.encode(days, forKey: .days)
        try container.encode(times, forKey: .times)
        try container.encode(direction, forKey: .direction)
        try container.encode(qualifiers, forKey: .qualifiers)
        try container.encode(rawText, forKey: .rawText)
    }
}

extension Unknown: Codable {
    private enum Keys: String, CodingKey {
        case rawText
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        rawText = try container.decode(String.self, forKey: .rawText)
        reason = try container.decode(UnknownReason.self, forKey: .reason)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(rawText, forKey: .rawText)
        try container.encode(reason, forKey: .reason)
    }
}

extension PanelResult: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SingleKey.self)
        guard let key = container.allKeys.first, container.allKeys.count == 1 else {
            throw decodingError(decoder, "a panel result needs exactly one of \"panel\" or \"unknown\"")
        }
        switch key.stringValue {
        case "panel": self = .panel(try container.decode(Panel.self, forKey: key))
        case "unknown": self = .unknown(try container.decode(Unknown.self, forKey: key))
        default: throw decodingError(decoder, "unknown panel result \"\(key.stringValue)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SingleKey.self)
        switch self {
        case .panel(let panel): try container.encode(panel, forKey: SingleKey("panel"))
        case .unknown(let unknown): try container.encode(unknown, forKey: SingleKey("unknown"))
        }
    }
}

extension Sign: Codable {
    private enum Keys: String, CodingKey {
        case panels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        panels = try container.decode([PanelResult].self, forKey: .panels)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(panels, forKey: .panels)
    }
}

extension Change: Codable {
    private enum Keys: String, CodingKey {
        case panel
        case kind
        case at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        panel = try container.decode(Panel.self, forKey: .panel)
        kind = try container.decode(ChangeKind.self, forKey: .kind)
        let text = try container.decode(String.self, forKey: .at)
        guard let date = InstantFormat.date(from: text) else {
            throw decodingError(decoder, "invalid instant \"\(text)\"")
        }
        at = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(panel, forKey: .panel)
        try container.encode(kind, forKey: .kind)
        try container.encode(InstantFormat.string(from: at), forKey: .at)
    }
}

extension Evaluation: Codable {
    private enum Keys: String, CodingKey {
        case instant
        case active
        case inactive
        case unknowns
        case nextChange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let text = try container.decode(String.self, forKey: .instant)
        guard let date = InstantFormat.date(from: text) else {
            throw decodingError(decoder, "invalid instant \"\(text)\"")
        }
        instant = date
        active = try container.decode([Panel].self, forKey: .active)
        inactive = try container.decode([Panel].self, forKey: .inactive)
        unknowns = try container.decode([Unknown].self, forKey: .unknowns)
        nextChange = try container.decodeIfPresent(Change.self, forKey: .nextChange)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(InstantFormat.string(from: instant), forKey: .instant)
        try container.encode(active, forKey: .active)
        try container.encode(inactive, forKey: .inactive)
        try container.encode(unknowns, forKey: .unknowns)
        try container.encodeIfPresent(nextChange, forKey: .nextChange)
    }
}
