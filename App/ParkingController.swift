import Foundation
import ParkKit
import SignKit
import SwiftUI
import UIKit
import WidgetKit

/// What Kerbside remembers, and everything that has to happen when it changes.
///
/// One place writes the record, so the file, the reminders, the Live Activity
/// and the widgets can never disagree about where the car is. Nothing here
/// decides anything about a sign: limits are proposed by ParkKit and committed
/// by a person, and this only carries out what was committed.
@MainActor
final class ParkingController: ObservableObject {

    @Published private(set) var record: ParkingRecord = .empty

    /// The limits the current spot's sign supports. Offered, never applied by
    /// themselves.
    @Published private(set) var candidates: [LimitCandidate] = []

    @Published private(set) var isSaving = false
    @Published var failure: String?

    /// Republished when a rule on the sign comes into or goes out of force, so
    /// the interface restates what is active without polling.
    @Published private(set) var instant = Date()

    let location = LocationService()

    private let reminders = ReminderService()
    private let activities = LiveActivityService()
    private let store = SharedContainer.store
    private let timeZone = SharedContainer.timeZone
    private var ruleChangeTask: Task<Void, Never>?

    var spot: ParkingSpot? { record.active }
    var isParked: Bool { record.active != nil }

    init() {
        reload()
    }

    // MARK: - Reading

    func reload() {
        do {
            record = try store.load()
        } catch {
            // A record that cannot be read is not quietly replaced with an
            // empty one, because that would lose a car without saying so.
            failure = "The saved spot could not be read. Saving a new one will replace it."
            record = .empty
        }
        refreshCandidates()
        scheduleRuleChange()
    }

    /// The sign as it reads now: which rules are in force, which are not, and
    /// which panels were never understood.
    var evaluation: Evaluation? {
        spot?.evaluation(at: instant, in: timeZone)
    }

    /// How far the car is and which way, or nil when either end is unknown.
    var distance: String? {
        guard let car = spot?.coordinate, let here = location.current else { return nil }
        return ParkWording.place(from: here, to: car)
    }

    var metresAway: Double? {
        guard let car = spot?.coordinate, let here = location.current else { return nil }
        return Geo.distance(from: here, to: car)
    }

    var bearing: Double? {
        guard let car = spot?.coordinate, let here = location.current else { return nil }
        return Geo.bearing(from: here, to: car)
    }

    // MARK: - Parking

    /// Saves where the car is. The fix is asked for here rather than at launch,
    /// so permission is requested at the moment its purpose is obvious.
    func park(sign: Sign? = nil, photo: UIImage? = nil, note: String = "") async {
        isSaving = true
        defer { isSaving = false }

        let now = Date()
        let coordinate = await location.fix()
        let id = UUID()
        let filename = photo.flatMap { PhotoStore.save($0, id: id) }

        var spot = ParkingSpot(
            id: id,
            parkedAt: now,
            coordinate: coordinate,
            note: note,
            sign: sign,
            limit: .openEnded,
            photoFilename: filename
        )

        // The sign's own allowance is offered as the starting point when it is
        // unambiguous. It stays named and editable on screen, so it is a
        // proposal a person can see and change rather than a number the app
        // decided on quietly.
        let suggested = LimitSuggester().candidates(for: sign ?? Sign(panels: []), parkedAt: now, in: timeZone)
        if suggested.count == 1, let only = suggested.soonestExpiring {
            spot.limit = only.limit
        }

        record.park(spot)
        commit(now: now)
        Feedback.recorded()
    }

    func collect() {
        let now = Date()
        record.collect(at: now)
        commit(now: now)
        Feedback.changed()
    }

    // MARK: - Limits

    func choose(_ candidate: LimitCandidate) {
        guard var spot = record.active else { return }
        spot.limit = candidate.limit
        replaceActive(with: spot)
    }

    /// A limit somebody set themselves, because the sign said nothing about
    /// duration, was not read, or was overruled by a ticket they bought.
    func setLimit(minutes: Int) {
        guard var spot = record.active else { return }
        spot.limit = .expires(
            at: Date().addingTimeInterval(Double(minutes) * 60),
            source: .chosen(minutes: minutes)
        )
        replaceActive(with: spot)
    }

    func clearLimit() {
        guard var spot = record.active else { return }
        spot.limit = .openEnded
        replaceActive(with: spot)
    }

    func setNote(_ text: String) {
        guard var spot = record.active, spot.note != text else { return }
        spot.note = text
        replaceActive(with: spot)
    }

    /// Attaches a sign read after the car was already saved.
    func attach(sign: Sign, photo: UIImage?) {
        guard var spot = record.active else { return }
        spot.sign = sign
        if let photo, let filename = PhotoStore.save(photo, id: spot.id) {
            spot.photoFilename = filename
        }
        replaceActive(with: spot)
    }

    private func replaceActive(with spot: ParkingSpot) {
        record.active = spot
        commit(now: Date())
        Feedback.changed()
    }

    // MARK: - Permissions

    /// Checks without asking. Permission is requested when somebody turns
    /// reminders on, not when a screen happens to appear.
    func remindersAuthorised() async -> Bool {
        await reminders.authorisationStatus() == .authorized
    }

    func requestReminders() async -> Bool {
        if await reminders.authorisationStatus() == .authorized { return true }
        let granted = await reminders.authorise()
        if granted, let spot = record.active {
            await reminders.reschedule(for: spot, now: Date(), in: timeZone)
        }
        return granted
    }

    // MARK: - Walking back

    func startTracking() {
        location.startTracking()
    }

    func stopTracking() {
        location.stopTracking()
    }

    /// Pushes a fresh distance to the Lock Screen while the app is open. The
    /// countdown does not need this — the system draws that from the expiry —
    /// so this only fires when the distance has really changed.
    func refreshLiveDistance() {
        guard let spot = record.active else { return }
        Task { await activities.sync(for: spot, distance: distance, now: Date(), in: timeZone) }
    }

    // MARK: - Writing

    /// One write, then everything that has to follow it.
    private func commit(now: Date) {
        do {
            try store.save(record)
        } catch {
            failure = "That spot could not be saved to this device."
            Feedback.failed()
            return
        }

        instant = now
        refreshCandidates()
        prunePhotos()
        scheduleRuleChange()
        WidgetCenter.shared.reloadAllTimelines()

        if let spot = record.active {
            let distance = distance
            Task {
                await activities.sync(for: spot, distance: distance, now: now, in: timeZone)
                await reminders.reschedule(for: spot, now: now, in: timeZone)
            }
        } else {
            Task {
                await activities.endAll()
                await reminders.clear()
            }
        }
    }

    private func refreshCandidates() {
        guard let spot = record.active, let sign = spot.sign else {
            candidates = []
            return
        }
        candidates = LimitSuggester().candidates(
            for: sign,
            parkedAt: spot.parkedAt,
            in: timeZone
        )
    }

    private func prunePhotos() {
        var kept = Set(record.past.compactMap(\.photoFilename))
        if let filename = record.active?.photoFilename { kept.insert(filename) }
        PhotoStore.prune(keeping: kept)
    }

    /// Wakes exactly once, when the sign next changes what it says, so the
    /// interface restates the active rule without polling a clock.
    private func scheduleRuleChange() {
        ruleChangeTask?.cancel()
        guard let change = evaluation?.nextChange else { return }
        let seconds = change.at.timeIntervalSinceNow + 0.05
        guard seconds > 0 else { return }

        ruleChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            instant = Date()
            Feedback.changed()
            refreshLiveDistance()
            WidgetCenter.shared.reloadAllTimelines()
            scheduleRuleChange()
        }
    }
}
