import ActivityKit
import Foundation
import ParkKit

/// The Lock Screen banner and the Dynamic Island.
///
/// The activity carries an expiry rather than a countdown, so the system draws
/// the falling number and the banner stays correct while the app is not
/// running. Updates are pushed only when something a person would notice has
/// changed — a limit set, a distance walked, a rule coming into force — rather
/// than on a timer.
///
/// No activity handle is kept. ActivityKit's own list survives a relaunch and
/// this one does not, so asking it every time is both simpler and the only
/// version that cannot leave a stale banner behind.
///
/// Deliberately not bound to the main actor. An `Activity` is not `Sendable`,
/// so a handle held on the main actor cannot be passed to ActivityKit's own
/// non-isolated methods. Holding no state at all sidesteps that entirely.
struct LiveActivityService: Sendable {

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Brings the banner into line with a spot, starting one if none is
    /// running for it and replacing one that belongs to a different car.
    func sync(
        for spot: ParkingSpot,
        distance: String?,
        now: Date,
        in timeZone: TimeZone
    ) async {
        guard isAvailable else { return }

        let state = ParkingActivityAttributes.ContentState.from(
            spot: spot,
            at: now,
            in: timeZone,
            distance: distance
        )
        let spotID = spot.id.uuidString

        // Updating in place rather than restarting, so the Lock Screen does
        // not flash every time a distance changes.
        if let existing = running(for: spotID) {
            await existing.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        await endAll()

        _ = try? Activity.request(
            attributes: ParkingActivityAttributes(spotID: spotID, parkedAt: spot.parkedAt),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func endAll() async {
        for activity in Activity<ParkingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func running(for spotID: String) -> Activity<ParkingActivityAttributes>? {
        Activity<ParkingActivityAttributes>.activities.first { $0.attributes.spotID == spotID }
    }
}
