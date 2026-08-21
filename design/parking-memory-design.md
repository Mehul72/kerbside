# Kerbside as a kerbside memory

Kerbside stops being an app that reads a sign and becomes an app that remembers
a car. It records where the car was left, what the sign above it said, and how
long that leaves, then surfaces the answer on the Lock Screen, in the Dynamic
Island, on the Home Screen and by notification.

Sign reading is not removed and is not demoted. It is what makes the timer
honest: the limit is not a number somebody typed, it is the panel they
photographed.

## What holds

Every product invariant survives this change. Two of them are close
enough to the new features to state precisely how.

**No verdict.** A countdown is the nearest this app has come to an opinion, so
the limit is always attributed. Screens say "the 2P on this sign runs out at
3:40 PM", never "you are fine until 3:40 PM" and never "you may not park".
`LimitSuggester` proposes candidates; a person commits one. No `canPark`, no
green tick, no red alert.

**On device only.** CoreLocation is local. There are no map tiles, no
geocoding and no reverse geocoding. The Apple Maps handoff launches another
app; it is not a network call from Kerbside. `InvariantTests` extends to cover
`Packages/ParkKit`, `Shared/` and `Widgets/`.

**Unreadable is a result.** A sign that did not parse produces a session with
no limit, shown as prominently as one that did. The app never invents a
duration to fill a ring.

**Time is `Australia/Sydney` from tzdata, injected.** ParkKit adopts SignKit's
discipline: no ambient `Date()` in its sources, enforced by the same test.

## Packages/ParkKit

Pure Swift, Foundation only, tested with `swift test`, no Apple framework
beyond Foundation. A coordinate is two `Double`s, not a `CLLocationCoordinate2D`,
so the arithmetic is testable at the command line.

| Type | Responsibility |
| --- | --- |
| `Coordinate` | Latitude, longitude, horizontal accuracy in metres |
| `ParkingSpot` | Coordinate, parked-at instant, note, level or bay text, optional `Sign` |
| `ParkingLimit` | `.expires(at:reason:)` or `.openEnded`, carrying what it came from |
| `LimitCandidate` | A limit the sign supports, with the panel it was read from |
| `LimitSuggester` | `Sign` + parked instant + time zone to candidates |
| `Reminder` | An instant and a kind |
| `ReminderPlan` | Session, limit and evaluation to the reminders worth scheduling |
| `Geo` | Haversine distance and initial bearing |
| `SpotStore` | Codable JSON persistence behind a protocol |

### LimitSuggester

The interesting logic, and the reason the existing `Evaluator` earns its keep.
For each parsed `.timeLimited` panel, given when the car was left:

- Parked inside the panel's window, and the allowance ends before the window
  does: the allowance runs out at `parked + minutes`.
- Parked inside the window, but the window closes first: the allowance never
  bites. The candidate reports the restriction lifting, not an expiry.
- Parked outside the window: the allowance starts when the window opens, so it
  runs out at `windowStart + minutes`.

Each candidate names its reason, so the interface can say which of the three
happened rather than presenting a bare time.

A `noStopping` or `noParking` panel active at the parked instant produces no
candidate. It is surfaced by the existing evaluator as an active rule, stated
and not judged.

### ReminderPlan

Three kinds, all derived, none invented:

- `limitEndsSoon` at a configurable lead, fifteen minutes by default
- `limitEnded` at the expiry itself
- `restrictionBegins` from `Evaluation.nextChange`, which already computes it

The third is free and is the one a person cannot work out for themselves:
parking on a Sunday evening under `No Parking 6-10AM MON-FRI` earns a
notification before six on Monday.

## Targets

`project.yml` gains a widget extension and an App Group. The deployment target
moves from iOS 16.0 to iOS 18.0, which is what Live Activities, interactive
widgets and the modern ActivityKit timer APIs need.

- `Kerbside` — sources `App/` and `Shared/`
- `KerbsideWidgets` — app extension, sources `Widgets/` and `Shared/`, holding
  the Home Screen widgets, the Lock Screen accessories and the Live Activity
- `group.au.kerbside` — one JSON file both targets read

`Shared/` exists because `ActivityAttributes` conforms to an ActivityKit
protocol and therefore cannot live in a Foundation-only package, while both the
app and the extension must see the same type.

The project is regenerated with `xcodegen generate`. The `.pbxproj` is never
hand edited.

## Screens

**Home, parked.** The photographed plate at the top, drawn as it is drawn
today. Below it the countdown ring in amber, the bearing and distance back to
the car, then `Remind me` and `I'm back`. A sign that did not parse shows its
unknown plate in full and reads "no limit recorded".

**Home, not parked.** One plate-styled `Park here`, with `Read a sign first`
beneath it.

**Return to car.** A bearing needle easing to the device heading, distance
counting down while walking, and `Walk me there` handing off to Apple Maps.
No tiles. Works in airplane mode.

**Past spots.** Where, when, and what the sign said.

## Live surfaces

The Dynamic Island compact view carries the countdown; expanded adds the plate
and the distance. The Lock Screen banner mirrors it. Home Screen widgets come
in small and medium, with Lock Screen accessories alongside.

## Aesthetic

The night asphalt ground and the enamel plates stay. They encode meaning:
green and red are the sign's own colours and are never borrowed for approval or
alarm. What the new work adds is motion — springs on state change, a countdown
ring that breathes and shimmers as it runs low, staggered plate entrances, a
needle that eases rather than snaps, and haptics when a rule changes. All of it
is disabled under `accessibilityReduceMotion`.

## Permissions

Location is the first thing Kerbside has ever asked for, from an app whose
pitch is no server, no account and no network. The usage description says so
plainly instead of reaching for a generic sentence. Notification permission is
requested when a reminder is first set, not at launch.
