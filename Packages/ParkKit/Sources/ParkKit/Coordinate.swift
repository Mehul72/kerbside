import Foundation

/// Where the car was left, as plain numbers.
///
/// Deliberately not `CLLocationCoordinate2D`. Keeping the type clear of
/// CoreLocation is what lets every metre of arithmetic in this package be
/// tested at the command line, and it keeps ParkKit to Foundation the way
/// SignKit is.
public struct Coordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    /// The radius in metres the device claims this fix is good to. Kept
    /// because a fix taken in a basement car park is worth less than one taken
    /// in the open, and the interface should be able to say so rather than
    /// drawing a confident arrow at a guess.
    public var accuracy: Double

    public init(latitude: Double, longitude: Double, accuracy: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }

    /// Whether a fix is tight enough to point at. A reading worse than this is
    /// still recorded — it is better than nothing when the car is missing —
    /// but the interface says the arrow is approximate.
    public var isPrecise: Bool { accuracy > 0 && accuracy <= 65 }
}
