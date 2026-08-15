import Foundation

/// The two numbers the walk back needs: how far, and which way.
///
/// Both are computed here rather than taken from CoreLocation so they can be
/// checked against known distances in a test. Nothing in this enum reads the
/// device, the clock or the network.
public enum Geo {

    /// IUGG mean earth radius, in metres. Good to a fraction of a percent over
    /// the few hundred metres a walk back to a car ever covers.
    static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres.
    public static func distance(from origin: Coordinate, to destination: Coordinate) -> Double {
        let phi1 = origin.latitude * .pi / 180
        let phi2 = destination.latitude * .pi / 180
        let deltaPhi = (destination.latitude - origin.latitude) * .pi / 180
        let deltaLambda = (destination.longitude - origin.longitude) * .pi / 180

        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Initial great-circle bearing in degrees clockwise from true north, in
    /// `0..<360`.
    public static func bearing(from origin: Coordinate, to destination: Coordinate) -> Double {
        let phi1 = origin.latitude * .pi / 180
        let phi2 = destination.latitude * .pi / 180
        let deltaLambda = (destination.longitude - origin.longitude) * .pi / 180

        let y = sin(deltaLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The eight points of the compass, named the way a person would say them.
    public static func compassPoint(_ bearing: Double) -> String {
        let names = [
            "north", "north-east", "east", "south-east",
            "south", "south-west", "west", "north-west",
        ]
        let normalised = (bearing.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalised / 45).rounded()) % 8
        return names[index]
    }

    /// Distance said the way it would be said out loud. Precision falls away
    /// with range because "1,247 m" pretends to a certainty a phone in a
    /// pocket does not have.
    public static func describe(metres: Double) -> String {
        switch metres {
        case ..<10: "under 10 m"
        case ..<100: "\(Int((metres / 5).rounded()) * 5) m"
        case ..<1000: "\(Int((metres / 10).rounded()) * 10) m"
        default: String(format: "%.1f km", metres / 1000)
        }
    }

    /// Roughly how long the walk takes, at a shade under 5 km/h. Rounded up to
    /// whole minutes, because nobody arrives in ninety seconds.
    public static func walkingMinutes(metres: Double) -> Int {
        max(1, Int((metres / 80).rounded(.up)))
    }
}
