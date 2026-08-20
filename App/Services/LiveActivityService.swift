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
/// Nothing here serialises itself. `sync` reads the running activities and
/// then starts one, and two calls overlapping across that gap will both find
/// nothing and both start a banner — an activity has no stable identifier to
/// deduplicate on the way a notification request does. Callers push through
/// one queue for that reason.
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

        // The expiry is the one moment the banner must redraw itself: the
        // figure has to turn around and start counting up. Marking the content
        // stale then is what wakes it, because the app will not be running.
        //
        // Only while it is still ahead of us. A limit that has already passed
        // — a car left overnight, the app reopened the morning after — has
        // nothing left to wake for, and handing ActivityKit a stale date in
        // the past means it never shows the banner at all.
        let staleDate = state.expiry.flatMap { $0 > now ? $0 : nil }
        let content = ActivityContent(state: state, staleDate: staleDate)

        // Updating in place rather than restarting, so the Lock Screen does
        // not flash every time a distance changes.
        //
        // More than one activity can be running for the same car if two syncs
        // ever raced, and a device that has already been left in that state
        // will not fix itself: the extra banner is never found again, so it
        // sits on the Lock Screen for ever saying whatever it said when it was
        // started. The extras are ended here rather than only prevented.
        let mine = running(for: spotID)
        if let keep = mine.first {
            for extra in mine.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            await keep.update(content)
            return
        }

        await endAll()

        _ = try? Activity.request(
            attributes: ParkingActivityAttributes(spotID: spotID, parkedAt: spot.parkedAt),
            content: content,
            pushType: nil
        )
    }

    func endAll() async {
        for activity in Activity<ParkingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Every activity running for this car. Normally none or one; more than
    /// one means something started a second banner behind this one's back.
    private func running(for spotID: String) -> [Activity<ParkingActivityAttributes>] {
        Activity<ParkingActivityAttributes>.activities.filter { $0.attributes.spotID == spotID }
    }
}
