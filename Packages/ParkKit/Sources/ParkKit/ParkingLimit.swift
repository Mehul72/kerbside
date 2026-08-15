import Foundation

/// Where a limit came from.
///
/// A limit is never anonymous. Every countdown in the interface can name the
/// panel or the person it came from, because a number with no provenance
/// starts to look like the app's own opinion about whether the car is safe,
/// and the app does not have one.
public enum LimitSource: Hashable, Sendable, Codable {
    /// Read off a panel: the allowance the sign itself states, in minutes.
    case sign(minutes: Int)

    /// Set by the person, because the sign said nothing about duration, was
    /// not read, or was overruled by a ticket they bought.
    case chosen(minutes: Int)

    public var minutes: Int {
        switch self {
        case .sign(let minutes), .chosen(let minutes): minutes
        }
    }
}

/// How long the car has, if anything says.
public enum ParkingLimit: Hashable, Sendable, Codable {

    /// Nothing counts down. Either no panel limits how long a car may stay, or
    /// the sign was not read and nobody has said otherwise. This is a real
    /// state and is shown as one — it is never dressed up as unlimited time.
    case openEnded

    case expires(at: Date, source: LimitSource)

    public var expiry: Date? {
        switch self {
        case .openEnded: nil
        case .expires(let at, _): at
        }
    }

    public var source: LimitSource? {
        switch self {
        case .openEnded: nil
        case .expires(_, let source): source
        }
    }

    /// Seconds left at a given instant. Negative once the limit has passed,
    /// which the interface shows as overrun rather than hiding.
    public func remaining(at instant: Date) -> TimeInterval? {
        expiry.map { $0.timeIntervalSince(instant) }
    }

    /// How far through the allowance a given instant is, in `0...1`.
    /// Used to draw the ring, so it is clamped rather than allowed to run past
    /// a full turn.
    public func progress(at instant: Date, parkedAt: Date) -> Double? {
        guard let expiry else { return nil }
        let total = expiry.timeIntervalSince(parkedAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, instant.timeIntervalSince(parkedAt) / total))
    }
}
