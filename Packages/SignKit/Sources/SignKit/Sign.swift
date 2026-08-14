import Foundation

/// One panel that was read successfully.
public struct Panel: Hashable, Sendable {
    public var restriction: Restriction
    public var days: DaySet
    public var times: TimeRange
    public var direction: Direction
    public var qualifiers: [Qualifier]
    public var rawText: String

    public init(
        restriction: Restriction,
        days: DaySet = .allDays,
        times: TimeRange = .allDay,
        direction: Direction = .unspecified,
        qualifiers: [Qualifier] = [],
        rawText: String
    ) {
        self.restriction = restriction
        self.days = days
        self.times = times
        self.direction = direction
        self.qualifiers = qualifiers
        self.rawText = rawText
    }
}

/// Why a block of sign text could not be read. The reason names the specific
/// obstacle so the interface can show it rather than shrugging.
public enum UnknownReason: Hashable, Sendable {
    case emptyPanel
    case noRestrictionFound
    case unrecognisedLine(String)
    case malformedTimeRange(String)
    case conflictingRestrictions
    case conflictingTimeRanges
    case conflictingDaySets
}

/// A panel that failed to parse. It keeps its raw text so the interface can
/// show what was on the sign even though nothing was understood.
public struct Unknown: Hashable, Sendable {
    public var rawText: String
    public var reason: UnknownReason

    public init(rawText: String, reason: UnknownReason) {
        self.rawText = rawText
        self.reason = reason
    }
}

/// Reading a panel either works or does not. Both outcomes are values in the
/// same array, so an unknown cannot be dropped on the way to the interface.
public enum PanelResult: Hashable, Sendable {
    case panel(Panel)
    case unknown(Unknown)
}

/// Everything read off one pole, in the order the panels appeared.
public struct Sign: Hashable, Sendable {
    public var panels: [PanelResult]

    public init(panels: [PanelResult]) {
        self.panels = panels
    }

    /// The panels that parsed, in sign order.
    public var parsedPanels: [Panel] {
        panels.compactMap { if case .panel(let panel) = $0 { panel } else { nil } }
    }

    /// The panels that did not parse, in sign order.
    public var unknowns: [Unknown] {
        panels.compactMap { if case .unknown(let unknown) = $0 { unknown } else { nil } }
    }
}
