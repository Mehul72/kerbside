import Foundation
import SignKit

/// A limit one panel supports, with everything needed to explain it.
///
/// This is a proposal, never a decision. The interface shows candidates and a
/// person commits one; nothing here writes a limit onto a spot by itself.
public struct LimitCandidate: Hashable, Sendable {

    /// The panel the allowance was read from.
    public var panel: Panel

    /// When the car was left.
    public var parkedAt: Date

    /// When the allowance starts running. Later than `parkedAt` only when the
    /// car was left before the restriction came into force.
    public var clockStarts: Date

    /// When the allowance would be used up, if nothing interrupts it.
    public var allowanceEnds: Date

    /// When the restriction stops applying, set only when that happens before
    /// the allowance is used up. In that case the allowance never bites and
    /// there is nothing to count down to.
    public var restrictionLifts: Date?

    public init(
        panel: Panel,
        parkedAt: Date,
        clockStarts: Date,
        allowanceEnds: Date,
        restrictionLifts: Date?
    ) {
        self.panel = panel
        self.parkedAt = parkedAt
        self.clockStarts = clockStarts
        self.allowanceEnds = allowanceEnds
        self.restrictionLifts = restrictionLifts
    }

    /// The panel's stated allowance in minutes.
    public var minutes: Int {
        if case .timeLimited(let minutes) = panel.restriction { return minutes }
        return 0
    }

    /// The instant worth counting down to, or nil when the restriction lifts
    /// before the allowance is used up.
    public var expiry: Date? { restrictionLifts == nil ? allowanceEnds : nil }

    /// Whether the allowance had not started when the car was left.
    public var startsLater: Bool { clockStarts > parkedAt }

    /// The limit this candidate becomes once someone commits it.
    public var limit: ParkingLimit {
        guard let expiry else { return .openEnded }
        return .expires(at: expiry, source: .sign(minutes: minutes))
    }
}

/// Works out what a sign leaves a car that was parked under it.
///
/// The arithmetic is delegated to SignKit's `Evaluator` rather than repeated,
/// so daylight saving, midnight-crossing windows and public holidays behave
/// here exactly as they do everywhere else in the app.
public struct LimitSuggester: Sendable {
    private let publicHolidays: any PublicHolidayProvider

    public init(publicHolidays: any PublicHolidayProvider = NSWPublicHolidays.current) {
        self.publicHolidays = publicHolidays
    }

    /// Every time-limited panel's answer to "how long does this leave me",
    /// soonest first. Panels that forbid stopping or parking produce nothing:
    /// they are not allowances, and the evaluator already reports them as
    /// rules in force so they are stated rather than judged.
    ///
    /// Panels that did not parse contribute nothing here and are shown by the
    /// interface in their own right, so an unread panel can never quietly
    /// become an allowance.
    public func candidates(
        for sign: Sign,
        parkedAt: Date,
        in timeZone: TimeZone
    ) -> [LimitCandidate] {
        let evaluator = Evaluator(publicHolidays: publicHolidays)
        var candidates: [LimitCandidate] = []

        for panel in sign.parsedPanels {
            guard case .timeLimited(let minutes) = panel.restriction, minutes > 0 else { continue }
            guard let candidate = self.candidate(
                for: panel,
                minutes: minutes,
                parkedAt: parkedAt,
                in: timeZone,
                using: evaluator
            ) else { continue }
            candidates.append(candidate)
        }

        // Soonest first, and a candidate that actually expires outranks one
        // whose restriction lifts first, because the former is the one a
        // person needs to act on.
        return candidates.sorted { lhs, rhs in
            switch (lhs.expiry, rhs.expiry) {
            case (let left?, let right?): left < right
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.allowanceEnds < rhs.allowanceEnds
            }
        }
    }

    private func candidate(
        for panel: Panel,
        minutes: Int,
        parkedAt: Date,
        in timeZone: TimeZone,
        using evaluator: Evaluator
    ) -> LimitCandidate? {
        let alone = Sign(panels: [.panel(panel)])
        let atParking = evaluator.evaluate(alone, at: parkedAt, in: timeZone)

        let clockStarts: Date
        if atParking.active.isEmpty {
            // The restriction is not in force yet, so the allowance has not
            // started. It starts when the window opens.
            guard let change = atParking.nextChange, change.kind == .begins else { return nil }
            clockStarts = change.at
        } else {
            clockStarts = parkedAt
        }

        let allowanceEnds = clockStarts.addingTimeInterval(Double(minutes) * 60)

        // Does the restriction lift before the allowance is used up? If it
        // does, the allowance never bites and there is nothing to count down.
        let atStart = evaluator.evaluate(alone, at: clockStarts, in: timeZone)
        var restrictionLifts: Date?
        if let change = atStart.nextChange, change.kind == .ends, change.at < allowanceEnds {
            restrictionLifts = change.at
        }

        return LimitCandidate(
            panel: panel,
            parkedAt: parkedAt,
            clockStarts: clockStarts,
            allowanceEnds: allowanceEnds,
            restrictionLifts: restrictionLifts
        )
    }
}

extension Array where Element == LimitCandidate {

    /// The candidate an interface should offer first: the soonest one that
    /// actually runs out. Nil when the sign named no allowance that bites,
    /// which leaves the spot open ended until someone says otherwise.
    public var soonestExpiring: LimitCandidate? {
        first { $0.expiry != nil }
    }
}
