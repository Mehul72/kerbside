import Foundation
import ParkKit
import UserNotifications

/// Notifications, scheduled from a plan ParkKit worked out.
///
/// Permission is asked for the first time somebody sets a reminder, not at
/// launch, because being asked for something before you have any use for it is
/// how a person learns to say no.
@MainActor
final class ReminderService {
    private let centre = UNUserNotificationCenter.current()

    /// Prefixed so the app can clear only its own requests, and so a spot's
    /// reminders can be replaced rather than stacked.
    private static let prefix = "au.kerbside.reminder."

    func authorisationStatus() async -> UNAuthorizationStatus {
        await centre.notificationSettings().authorizationStatus
    }

    @discardableResult
    func authorise() async -> Bool {
        (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces everything scheduled for this spot with the current plan.
    ///
    /// Rescheduling is always a replacement, never an addition: a reminder's
    /// identity comes from the spot and the reason, so changing a limit
    /// rewrites the reminders rather than leaving the old ones to fire.
    /// The alarm's own sound, bundled with the app.
    ///
    /// Longer and harsher than the default chime, because the point of it is to
    /// be heard from inside a shop. It cannot be louder than the phone is set
    /// to, and it cannot sound at all on silent: overriding either needs the
    /// critical-alert entitlement, which Apple reserves for medical and safety
    /// apps. Repetition is what is left, and repetition is what the plan does.
    static let alarmSound = UNNotificationSound(
        named: UNNotificationSoundName("kerbside-alarm.caf")
    )

    func reschedule(
        for spot: ParkingSpot,
        now: Date,
        in timeZone: TimeZone,
        walkingMinutes: Int? = nil,
        preferences: ReminderPreferences = .standard
    ) async {
        await clear()

        let reminders = ReminderPlan.reminders(
            for: spot,
            now: now,
            in: timeZone,
            walkingMinutes: walkingMinutes,
            preferences: preferences
        )
        guard !reminders.isEmpty else { return }
        guard await authorisationStatus() == .authorized else { return }

        for reminder in reminders {
            let wording = ParkWording.notification(for: reminder, spot: spot, in: timeZone)
            let content = UNMutableNotificationContent()
            content.title = wording.title
            content.body = wording.body
            content.sound = reminder.isAlarm ? Self.alarmSound : .default
            content.interruptionLevel = .timeSensitive

            let request = UNNotificationRequest(
                identifier: Self.prefix + reminder.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, reminder.at.timeIntervalSince(now)),
                    repeats: false
                )
            )
            try? await centre.add(request)
        }
    }

    /// Removes every reminder Kerbside scheduled, leaving anything else alone.
    func clear() async {
        let pending = await centre.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        centre.removePendingNotificationRequests(withIdentifiers: mine)
    }
}
