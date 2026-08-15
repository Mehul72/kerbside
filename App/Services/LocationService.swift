import CoreLocation
import Foundation
import ParkKit

/// The device's own idea of where it is.
///
/// Location is the first thing Kerbside has ever asked for, so it asks for as
/// little as it can: permission only when in use, a single fix when a car is
/// saved, and continuous updates only while somebody is actually walking back
/// to the car. Nothing is uploaded, because there is nowhere to upload it to.
@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    /// The most recent fix, kept so the walk back can show a live distance.
    @Published private(set) var current: Coordinate?

    /// Degrees clockwise from true north, or nil where the device has no
    /// compass. A simulator has none, which is why every surface that uses
    /// this copes with its absence rather than assuming it.
    @Published private(set) var heading: Double?

    let hasCompass = CLLocationManager.headingAvailable()

    private let manager = CLLocationManager()
    private var fixWaiters: [CheckedContinuation<Coordinate?, Never>] = []
    private var authorisationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorization = manager.authorizationStatus
    }

    var isAuthorised: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Asks once, and answers immediately ever after.
    @discardableResult
    func authorise() async -> CLAuthorizationStatus {
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorisationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One fix, or nil if permission was refused or none arrived in time.
    ///
    /// A car is saved either way: a spot with no coordinate still remembers
    /// the time, the sign and the note, and the interface says plainly that it
    /// cannot point the way back.
    func fix(timeout: TimeInterval = 8) async -> Coordinate? {
        guard await authorise() != .notDetermined, isAuthorised else { return nil }

        let expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.settleFixWaiters(with: self?.current)
        }
        defer { expiry.cancel() }

        return await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    /// Continuous position and heading, for the walk back. Started only while
    /// that screen is on, because it is the only screen that needs it.
    func startTracking() {
        guard isAuthorised else { return }
        manager.startUpdatingLocation()
        if hasCompass { manager.startUpdatingHeading() }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        if hasCompass { manager.stopUpdatingHeading() }
    }

    private func settleFixWaiters(with coordinate: Coordinate?) {
        let waiters = fixWaiters
        fixWaiters = []
        for waiter in waiters { waiter.resume(returning: coordinate) }
    }
}

// The manager was created on the main actor, so its callbacks arrive there.
extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            let coordinate = Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy
            )
            current = coordinate
            settleFixWaiters(with: coordinate)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        MainActor.assumeIsolated {
            settleFixWaiters(with: current)
        }
    }

    // The manager and its readings are not Sendable, so the plain values are
    // taken out of them here and only those cross onto the actor.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            let waiters = authorisationWaiters
            authorisationWaiters = []
            for waiter in waiters { waiter.resume(returning: authorization) }
            if !isAuthorised { settleFixWaiters(with: nil) }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        // True north where the device can work it out, magnetic otherwise. A
        // negative true heading means the device has no fix to correct by.
        let degrees = newHeading.trueHeading >= 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading
        MainActor.assumeIsolated {
            heading = degrees
        }
    }
}
