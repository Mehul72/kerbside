import Combine
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

    /// Whether a limit running out should sound an alarm rather than a single
    /// chime. Off unless asked for, and remembered between launches.
    @Published var alarmOnExpiry: Bool = ParkingController.storedAlarmPreference {
        didSet {
            guard alarmOnExpiry != oldValue else { return }
            Self.store(alarm: alarmOnExpiry)
            rescheduleReminders()
        }
    }

    let location = LocationService()

    private let reminders = ReminderService()
    private let activities = LiveActivityService()
    private let store = SharedContainer.store
    private let timeZone = SharedContainer.timeZone
    private var ruleChangeTask: Task<Void, Never>?

    /// Banner pushes, chained so that only one runs at a time.
    ///
    /// Two paths push: `commit`, whenever the record changes, and
    /// `refreshLiveDistance`, whenever a fix arrives. Saving a car fires both
    /// within milliseconds — `park` commits, and the parked screen's `task`
    /// immediately asks for a fix and pushes the distance it gets. Unordered,
    /// both found no banner running for the new spot and both started one, and
    /// the limit set a moment later only ever reached the first of them. That
    /// is the second banner people saw on the Lock Screen, stuck for ever on
    /// "No limit recorded".
    private var activityPushes: Task<Void, Never>?
    private var locationChanges: AnyCancellable?

    private static let alarmKey = "au.kerbside.alarmOnExpiry"

    private static var storedAlarmPreference: Bool {
        (UserDefaults(suiteName: SharedContainer.appGroup) ?? .standard).bool(forKey: alarmKey)
    }

    private static func store(alarm: Bool) {
        (UserDefaults(suiteName: SharedContainer.appGroup) ?? .standard)
            .set(alarm, forKey: alarmKey)
    }

    /// What the reminder plan is built from right now.
    private var reminderPreferences: ReminderPreferences {
        .standard.alarming(alarmOnExpiry)
    }

    /// Rewrites the schedule for the car currently parked, if there is one.
    private func rescheduleReminders() {
        guard let spot = record.active else { return }
        let walk = walkingMinutes
        let preferences = reminderPreferences
        Task {
            await reminders.reschedule(
                for: spot,
                now: Date(),
                in: timeZone,
                walkingMinutes: walk,
                preferences: preferences
            )
        }
    }

    var spot: ParkingSpot? { record.active }
    var isParked: Bool { record.active != nil }

    init() {
        // The interface test drives the real app against the real container,
        // so it needs a way to start from nothing. Nothing else passes this.
        if ProcessInfo.processInfo.arguments.contains("-kerbside-reset") {
            try? store.save(.empty)
            Self.store(alarm: false)
            FirstRunView.markSeen()
        }

        // Distance and bearing are read through this object but computed from
        // the location service's own published state. Without forwarding, a
        // fix arriving would update nothing on screen, because SwiftUI is
        // watching this object and not that one.
        locationChanges = location.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

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

    /// How long the walk back would take from where the phone is now, when
    /// that is knowable. This is what sets the reminder: a fixed warning is
    /// useless at both ends of the range, and only the app knows the distance.
    var walkingMinutes: Int? {
        metresAway.map { Geo.walkingMinutes(metres: $0) }
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

        var spot = ParkingSpot(
            id: id,
            parkedAt: now,
            coordinate: coordinate,
            note: note,
            sign: sign,
            limit: .openEnded,
            photoFilename: photo.flatMap { PhotoStore.save($0, id: id) }
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
    ///
    /// The photograph of the sign is deliberately not kept: the panels are
    /// redrawn as plates, which is more legible than the picture was, and the
    /// spot's own photograph belongs to the car rather than to the sign.
    func attach(sign: Sign) {
        guard var spot = record.active else { return }
        spot.sign = sign
        replaceActive(with: spot)
    }

    /// A photograph of where the car actually is.
    func setPhoto(_ image: UIImage) {
        guard var spot = record.active else { return }
        if let existing = spot.photoFilename { PhotoStore.remove(existing) }
        spot.photoFilename = PhotoStore.save(image, id: spot.id)
        replaceActive(with: spot)
    }

    func removePhoto() {
        guard var spot = record.active, let existing = spot.photoFilename else { return }
        PhotoStore.remove(existing)
        spot.photoFilename = nil
        replaceActive(with: spot)
    }

    var photo: UIImage? {
        record.active?.photoFilename.flatMap(PhotoStore.load)
    }

    /// The allowance the sign offers, when nothing has been committed yet. This
    /// is what "the sign recommends" means: a proposal, still untaken.
    var suggestion: LimitCandidate? {
        guard record.active?.limit.expiry == nil else { return nil }
        return candidates.soonestExpiring
    }

    /// Forgets a past spot, and the photograph that went with it. A row that
    /// disappeared while its picture stayed on disk would not be forgetting.
    func forget(_ id: UUID) {
        record.forget(id)
        commit(now: Date())
    }

    func forgetPast() {
        record.forgetPast()
        commit(now: Date())
    }

    private func replaceActive(with spot: ParkingSpot) {
        record.active = spot
        commit(now: Date())
        Feedback.changed()
    }

    // MARK: - Permissions

    /// What can be said about reminders right now.
    ///
    /// Refused is held apart from not-yet-asked because iOS will not show the
    /// prompt a second time. A button that silently does nothing is worse than
    /// no button, so the interface sends a refused person to Settings instead
    /// of offering an ask that cannot happen.
    enum ReminderState {
        case on
        case off
        case refused
    }

    /// Checks without asking. Permission is requested when somebody turns
    /// reminders on, not when a screen happens to appear.
    func reminderState() async -> ReminderState {
        switch await reminders.authorisationStatus() {
        case .authorized, .provisional, .ephemeral: .on
        case .denied: .refused
        default: .off
        }
    }

    func requestReminders() async -> Bool {
        if await reminders.authorisationStatus() == .authorized { return true }
        let granted = await reminders.authorise()
        if granted, let spot = record.active {
            await reminders.reschedule(
                for: spot,
                now: Date(),
                in: timeZone,
                walkingMinutes: walkingMinutes,
                preferences: reminderPreferences
            )
        }
        return granted
    }

    // MARK: - Walking back

    /// One fix, so the home screen can say how far the car is without running
    /// the receiver continuously. Called when the parked screen appears; the
    /// walk back screen starts real tracking instead.
    func refreshHere() async {
        guard let spot = record.active, spot.coordinate != nil, !location.isDenied else { return }
        _ = await location.fix()
        refreshLiveDistance()

        // A fresh distance changes when it is time to head back, so the plan is
        // rewritten rather than left as it was scheduled from somewhere else.
        let walk = walkingMinutes
        await reminders.reschedule(
            for: spot,
            now: Date(),
            in: timeZone,
            walkingMinutes: walk,
            preferences: reminderPreferences
        )
    }

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
        pushActivity(for: spot, now: Date())
    }

    /// Queues a banner push behind whatever is already in flight.
    private func pushActivity(for spot: ParkingSpot, now: Date) {
        let previous = activityPushes
        let service = activities
        let zone = timeZone
        let distance = distance
        activityPushes = Task {
            await previous?.value
            await service.sync(for: spot, distance: distance, now: now, in: zone)
        }
    }

    /// Ends the banner, in the same queue, so it cannot overtake a push that
    /// would start a new one after it.
    private func endActivity() {
        let previous = activityPushes
        let service = activities
        activityPushes = Task {
            await previous?.value
            await service.endAll()
        }
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
            let walk = walkingMinutes
            pushActivity(for: spot, now: now)
            // Not queued behind the banner. A reminder is identified by the
            // spot and the reason it exists, so adding one replaces the one it
            // supersedes and racing reschedules cannot stack up the way two
            // banners can.
            let preferences = reminderPreferences
            Task {
                await reminders.reschedule(
                    for: spot,
                    now: now,
                    in: timeZone,
                    walkingMinutes: walk,
                    preferences: preferences
                )
            }
        } else {
            endActivity()
            Task { await reminders.clear() }
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
