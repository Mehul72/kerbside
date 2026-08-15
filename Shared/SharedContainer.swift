import Foundation
import ParkKit

/// Where the app and its widgets meet.
///
/// One App Group holds one record and one photograph per spot. The lookup
/// fails soft on purpose: a build signed without the group entitlement still
/// runs, still remembers a car and still shows a Live Activity — it only loses
/// the ability to feed a widget, which is a degraded app rather than a broken
/// one.
enum SharedContainer {
    static let appGroup = "group.au.kerbside"

    /// True when the record really is shared. The interface uses this to
    /// explain why a widget is empty rather than leaving somebody guessing.
    static var isShared: Bool { groupDirectory != nil }

    private static var groupDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var directory: URL {
        if let groupDirectory { return groupDirectory }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kerbside", isDirectory: true)
    }

    static var store: SpotStore {
        SpotStore(fileURL: SpotStore.url(inContainer: directory))
    }

    static var photosDirectory: URL {
        directory.appendingPathComponent("spots", isDirectory: true)
    }

    static func photoURL(_ filename: String) -> URL {
        photosDirectory.appendingPathComponent(filename)
    }

    /// Sydney, from tzdata, never a fixed offset. Every surface reads the same
    /// clock so a widget and the app can never disagree about what time it is
    /// where the car is.
    static let timeZone = TimeZone(identifier: "Australia/Sydney")!
}
