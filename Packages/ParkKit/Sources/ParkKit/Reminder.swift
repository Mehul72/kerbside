import Foundation
import SignKit

/// Why a reminder is worth interrupting somebody for.
public enum ReminderKind: Hashable, Sendable, Codable {

    /// There is just enough time left to walk back to the car, plus a little.
    ///
    /// This is the reminder that is actually useful: a fixed warning is either
    /// too early when the car is at the kerb outside or far too late when it is
    /// a kilometre away, and only the app knows which.
    case timeToLeave(walkMinutes: Int)

    /// The allowance is nearly used up.
    case limitEndsSoon(minutesBefore: Int)

    /// The allowance is used up now.
    case limitEnded

    /// A rule on the sign is about to start applying. This is the one nobody
    /// can work out for themselves: a car left on a Sunday evening under
    /// `No Parking 6-10AM MON-FRI` is fine all night and towable at six.
    case restrictionBegins(Panel)
}

/// One scheduled interruption.
public struct Reminder: Hashable, Sendable, Identifiable {

    /// Stable across rescheduling, so re-planning a spot replaces its
    /// reminders rather than stacking a second set on top of them.
    public var id: String
    public var at: Date
    public var kind: ReminderKind

    /// Whether this one should sound like an alarm rather than a notification.
    ///
    /// iOS will not let an ordinary app override the silent switch — that needs
    /// the critical-alert entitlement, which Apple grants to medical and safety
    /// apps and would not grant to this one. So an alarm here is a longer,
    /// harsher sound repeated a few times, which is what can actually be done
    /// and is enough to be noticed from inside a shop.
    public var isAlarm: Bool

    public init(id: String, at: Date, kind: ReminderKind, isAlarm: Bool = false) {
        self.id = id
        self.at = at
        self.kind = kind
        self.isAlarm = isAlarm
    }
}

/// What a person wants to be told about, and how far ahead.
public struct ReminderPreferences: Hashable, Sendable, Codable {

    /// Minutes before the limit runs out. Empty means no warning shots.
    public var leads: [Int]

    /// Whether to say anything at the moment the limit runs out.
    public var atExpiry: Bool

    /// Whether to say anything when a rule on the sign starts applying.
    public var restrictionChanges: Bool

    /// Minutes of slack on top of the walk back, so a reminder does not arrive
    /// at the exact moment somebody would have to start running.
    public var walkingBuffer: Int

    /// Sound an alarm when the limit runs out, rather than one chime.
    ///
    /// Off unless somebody asks for it. A single notification is the right
    /// weight for most people most of the time, and an app that decides on its
    /// own to make an alarm noise in a quiet shop is an app people delete.
    public var alarmAtExpiry: Bool

    /// How many times the alarm sounds, and how far apart.
    ///
    /// A notification plays its sound once, so being hard to miss has to come
    /// from repetition rather than from length. Four over a minute is enough to
    /// catch somebody at a till without becoming a nuisance if they are already
    /// walking back.
    public var alarmRepeats: Int
    public var alarmInterval: TimeInterval

    public init(
        leads: [Int],
        atExpiry: Bool,
        restrictionChanges: Bool,
        walkingBuffer: Int = 5,
        alarmAtExpiry: Bool = false,
        alarmRepeats: Int = 4,
        alarmInterval: TimeInterval = 20
    ) {
        self.leads = leads
        self.atExpiry = atExpiry
        self.restrictionChanges = restrictionChanges
        self.walkingBuffer = walkingBuffer
        self.alarmAtExpiry = alarmAtExpiry
        self.alarmRepeats = alarmRepeats
        self.alarmInterval = alarmInterval
    }

    public static let standard = ReminderPreferences(
        leads: [15],
        atExpiry: true,
        restrictionChanges: true
    )

    /// The same preferences with the alarm turned on or off.
    public func alarming(_ on: Bool) -> ReminderPreferences {
        var copy = self
        copy.alarmAtExpiry = on
        return copy
    }
}

/// Works out which reminders are worth scheduling for a spot.
///
/// Every reminder here is derived from something the sign said or something a
/// person set. None is invented, and none of them offers advice: a reminder
/// states what is about to change, which is the same thing every other surface
/// in the app does.
public enum ReminderPlan {

    /// - Parameter walkingMinutes: how long it would take to walk back from
    ///   where the person is now, when that is known. When it is, it replaces
    ///   the fixed warning entirely: being told "leave now" is strictly better
    ///   than being told "fifteen minutes left" from an unknown distance.
    public static func reminders(
        for spot: ParkingSpot,
        now: Date,
        in timeZone: TimeZone,
        walkingMinutes: Int? = nil,
        preferences: ReminderPreferences = .standard,
        publicHolidays: any PublicHolidayProvider = NSWPublicHolidays.current
    ) -> [Reminder] {
        guard spot.collectedAt == nil else { return [] }
        var reminders: [Reminder] = []

        if let expiry = spot.limit.expiry, let walk = walkingMinutes, walk >= 0 {
            let lead = walk + preferences.walkingBuffer
            let at = expiry.addingTimeInterval(-Double(lead) * 60)
            if at > now, at > spot.parkedAt {
                reminders.append(
                    Reminder(
                        id: "\(spot.id.uuidString).leave",
                        at: at,
                        kind: .timeToLeave(walkMinutes: walk)
                    )
                )
            }
        }

        // The fixed warning is a fallback for when there is no distance to work
        // from — no fix, or location refused.
        if let expiry = spot.limit.expiry, walkingMinutes == nil {
            for lead in preferences.leads where lead > 0 {
                let at = expiry.addingTimeInterval(-Double(lead) * 60)
                // A warning that would fire before the car was even left is
                // not a warning, so it is dropped rather than fired at once.
                guard at > now, at > spot.parkedAt else { continue }
                reminders.append(
                    Reminder(
                        id: "\(spot.id.uuidString).soon.\(lead)",
                        at: at,
                        kind: .limitEndsSoon(minutesBefore: lead)
                    )
                )
            }
        }

        // The moment it runs out is worth saying however the warning was
        // worked out, so this sits outside both branches above.
        if let expiry = spot.limit.expiry, preferences.atExpiry, expiry > now {
            // One notice normally; a short series when an alarm was asked for,
            // because a notification sounds once and somebody inside a shop
            // will miss one.
            let times = preferences.alarmAtExpiry ? max(1, preferences.alarmRepeats) : 1

            for attempt in 0..<times {
                let at = expiry.addingTimeInterval(Double(attempt) * preferences.alarmInterval)
                reminders.append(
                    Reminder(
                        id: attempt == 0
                            ? "\(spot.id.uuidString).ended"
                            : "\(spot.id.uuidString).ended.\(attempt)",
                        at: at,
                        kind: .limitEnded,
                        isAlarm: preferences.alarmAtExpiry
                    )
                )
            }
        }

        if preferences.restrictionChanges,
           let evaluation = spot.evaluation(at: now, in: timeZone, publicHolidays: publicHolidays),
           let change = evaluation.nextChange,
           change.kind == .begins,
           change.at > now {
            reminders.append(
                Reminder(
                    id: "\(spot.id.uuidString).begins",
                    at: change.at,
                    kind: .restrictionBegins(change.panel)
                )
            )
        }

        return reminders.sorted { $0.at < $1.at }
    }
}
