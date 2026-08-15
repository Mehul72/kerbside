import Foundation
import ParkKit
import SignKit

// A development tool for seeing what a sign leaves a car, and what would be
// scheduled, without a simulator. It is not part of the app.
//
//   parkplan --at "2026-08-19T13:00:00+10:00" "2P" "8.30AM - 6PM" "MON - FRI"

let arguments = Array(CommandLine.arguments.dropFirst())
let sydney = TimeZone(identifier: "Australia/Sydney")!

var parkedAt = Date()
var text: [String] = []
var index = 0
while index < arguments.count {
    if arguments[index] == "--at", index + 1 < arguments.count {
        guard let parsed = ISO8601DateFormatter().date(from: arguments[index + 1]) else {
            FileHandle.standardError.write(Data("could not read \(arguments[index + 1])\n".utf8))
            exit(1)
        }
        parkedAt = parsed
        index += 2
    } else {
        text.append(arguments[index])
        index += 1
    }
}

let input: String
if text.isEmpty {
    var stdinText = ""
    while let line = readLine(strippingNewline: false) { stdinText += line }
    input = stdinText
} else {
    input = text.joined(separator: "\n")
}

let sign = Parser.parse(input)
print("Parked \(ParkWording.dayAndClock(parkedAt, relativeTo: parkedAt, in: sydney))")
print("")

for (position, result) in sign.panels.enumerated() {
    switch result {
    case .panel(let panel):
        print("Panel \(position + 1): \(Wording.describe(panel))")
    case .unknown(let unknown):
        print("Panel \(position + 1): not read. \(Wording.describe(unknown.reason))")
    }
}
print("")

let candidates = LimitSuggester().candidates(for: sign, parkedAt: parkedAt, in: sydney)
if candidates.isEmpty {
    print("No allowance on this sign limits how long the car may stay.")
} else {
    print("Allowances")
    for candidate in candidates {
        print("  \(ParkWording.describe(candidate, in: sydney))")
    }
}
print("")

var spot = ParkingSpot(parkedAt: parkedAt, sign: sign)
spot.limit = candidates.soonestExpiring?.limit ?? .openEnded
print("Limit: \(ParkWording.attribution(spot.limit, in: sydney))")
print("")

let reminders = ReminderPlan.reminders(for: spot, now: parkedAt, in: sydney)
if reminders.isEmpty {
    print("Nothing to schedule.")
} else {
    print("Reminders")
    for reminder in reminders {
        let wording = ParkWording.notification(for: reminder, spot: spot, in: sydney)
        print("  \(ParkWording.dayAndClock(reminder.at, relativeTo: parkedAt, in: sydney))"
            + " — \(wording.title): \(wording.body)")
    }
}
