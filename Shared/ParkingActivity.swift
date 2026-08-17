import ActivityKit
import Foundation
import ParkKit
import SignKit
import SwiftUI

/// Which colour the governing plate is painted, in a form that survives being
/// encoded into a Live Activity's state.
///
/// The three cases are the three a plate is allowed to be, and grey still
/// means unread rather than neutral.
enum PlateInk: String, Codable, Hashable, Sendable {
    case green
    case red
    case grey

    init(_ restriction: Restriction) {
        switch restriction {
        case .timeLimited: self = .green
        case .noParking, .noStopping: self = .red
        }
    }

    var tone: PlateTone {
        switch self {
        case .green: .permissive
        case .red: .prohibitive
        case .grey: .unread
        }
    }
}

/// The Lock Screen banner and the Dynamic Island.
///
/// The state carries an expiry rather than a countdown, so the system draws
/// the falling number itself and the activity stays right without the app
/// waking up to push it. Every string here is a description of a sign or of a
/// limit somebody set; none of them is advice.
struct ParkingActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// When the recorded limit runs out. Nil when nothing counts down,
        /// which the banner says plainly instead of showing a frozen zero.
        var expiry: Date?

        /// When the allowance began running, so the banner's ring measures the
        /// allowance rather than how long the car has been there.
        var startedAt: Date?

        /// The first line of the plate the limit came from, in the plate's own
        /// lettering: `2P`, `NO STOPPING`.
        var headline: String
        var ink: PlateInk

        /// One sentence naming where the limit came from.
        var attribution: String

        /// What the sign says is in force at the moment, if a sign was read.
        var activeRule: String?

        /// How far the car is, refreshed while the app is open. Nil when no
        /// fix was recorded or none is current.
        var distance: String?
    }

    /// Fixed for the life of the activity.
    var spotID: String
    var parkedAt: Date
}

extension ParkingActivityAttributes.ContentState {

    /// Builds the banner's state out of a spot, so the app, the widget and the
    /// activity cannot drift from one another.
    static func from(
        spot: ParkingSpot,
        at instant: Date,
        in timeZone: TimeZone,
        distance: String? = nil
    ) -> Self {
        let evaluation = spot.evaluation(at: instant, in: timeZone)
        let governing = governingPanel(spot: spot, evaluation: evaluation)

        return ParkingActivityAttributes.ContentState(
            expiry: spot.limit.expiry,
            startedAt: spot.limit.startedAt,
            headline: governing.map(ParkWording.plateHeadline) ?? "PARKED",
            ink: governing.map { PlateInk($0.restriction) } ?? .grey,
            attribution: ParkWording.attribution(spot.limit, at: instant, in: timeZone),
            activeRule: evaluation?.active.first.map { Wording.describe($0) },
            distance: distance
        )
    }

    /// The panel the banner speaks for: the rule in force now, or failing
    /// that the one the limit was read from.
    private static func governingPanel(spot: ParkingSpot, evaluation: Evaluation?) -> Panel? {
        if let active = evaluation?.active.first { return active }
        return spot.sign?.parsedPanels.first
    }


}
