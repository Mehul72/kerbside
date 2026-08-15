import Foundation
import Testing

@testable import ParkKit

struct GeoTests {

    // Two Sydney landmarks with a distance that can be checked independently.
    static let operaHouse = Coordinate(latitude: -33.8568, longitude: 151.2153, accuracy: 5)
    static let harbourBridge = Coordinate(latitude: -33.8523, longitude: 151.2108, accuracy: 5)

    @Test("distance between two known points is right to within a few metres")
    func knownDistance() {
        let metres = Geo.distance(from: Self.operaHouse, to: Self.harbourBridge)
        // 0.0045° of latitude is 500 m and 0.0045° of longitude at this
        // latitude is 416 m, so the two lie 650 m apart.
        #expect(abs(metres - 650.4) < 2)
    }

    @Test("a point is no distance from itself")
    func zeroDistance() {
        #expect(Geo.distance(from: Self.operaHouse, to: Self.operaHouse) < 0.001)
    }

    @Test("one degree of latitude is about 111 km")
    func degreeOfLatitude() {
        let south = Coordinate(latitude: -34, longitude: 151, accuracy: 5)
        let north = Coordinate(latitude: -33, longitude: 151, accuracy: 5)
        let metres = Geo.distance(from: south, to: north)
        #expect(abs(metres - 111_195) < 200)
    }

    @Test("bearing due north is zero and due east is ninety")
    func cardinalBearings() {
        let origin = Coordinate(latitude: -33.87, longitude: 151.21, accuracy: 5)
        let north = Coordinate(latitude: -33.86, longitude: 151.21, accuracy: 5)
        let east = Coordinate(latitude: -33.87, longitude: 151.22, accuracy: 5)
        let south = Coordinate(latitude: -33.88, longitude: 151.21, accuracy: 5)
        let west = Coordinate(latitude: -33.87, longitude: 151.20, accuracy: 5)

        #expect(abs(Geo.bearing(from: origin, to: north) - 0) < 0.5)
        #expect(abs(Geo.bearing(from: origin, to: east) - 90) < 0.5)
        #expect(abs(Geo.bearing(from: origin, to: south) - 180) < 0.5)
        #expect(abs(Geo.bearing(from: origin, to: west) - 270) < 0.5)
    }

    @Test("bearing never leaves zero up to three hundred and sixty")
    func bearingRange() {
        let origin = Coordinate(latitude: -33.87, longitude: 151.21, accuracy: 5)
        for degrees in stride(from: 0.0, to: 360.0, by: 7.0) {
            let radians = degrees * .pi / 180
            let target = Coordinate(
                latitude: origin.latitude + 0.01 * cos(radians),
                longitude: origin.longitude + 0.01 * sin(radians),
                accuracy: 5
            )
            let bearing = Geo.bearing(from: origin, to: target)
            #expect(bearing >= 0)
            #expect(bearing < 360)
        }
    }

    @Test("compass points name the eight directions and wrap at north")
    func compassPoints() {
        #expect(Geo.compassPoint(0) == "north")
        #expect(Geo.compassPoint(45) == "north-east")
        #expect(Geo.compassPoint(90) == "east")
        #expect(Geo.compassPoint(180) == "south")
        #expect(Geo.compassPoint(270) == "west")
        #expect(Geo.compassPoint(350) == "north")
        #expect(Geo.compassPoint(359.9) == "north")
        #expect(Geo.compassPoint(-10) == "north")
        #expect(Geo.compassPoint(370) == "north")
    }

    @Test("distance is said with precision that falls away with range")
    func spokenDistance() {
        #expect(Geo.describe(metres: 4) == "under 10 m")
        #expect(Geo.describe(metres: 42) == "40 m")
        #expect(Geo.describe(metres: 43) == "45 m")
        #expect(Geo.describe(metres: 247) == "250 m")
        #expect(Geo.describe(metres: 1247) == "1.2 km")
    }

    @Test("a walk is never reported as less than a minute")
    func walkingTime() {
        #expect(Geo.walkingMinutes(metres: 5) == 1)
        #expect(Geo.walkingMinutes(metres: 240) == 3)
        #expect(Geo.walkingMinutes(metres: 800) == 10)
    }

    @Test("a loose fix is not treated as precise")
    func precision() {
        #expect(Coordinate(latitude: 0, longitude: 0, accuracy: 12).isPrecise)
        #expect(!Coordinate(latitude: 0, longitude: 0, accuracy: 180).isPrecise)
        #expect(!Coordinate(latitude: 0, longitude: 0, accuracy: -1).isPrecise)
    }
}
