import Foundation

/// Building instants by wall time in Sydney, so a test reads like the sign it
/// is about.
enum Clock {
    static let sydney = TimeZone(identifier: "Australia/Sydney")!

    static func sydney(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sydney
        return calendar.date(
            from: DateComponents(
                year: year, month: month, day: day,
                hour: hour, minute: minute, second: second
            )
        )!
    }
}
