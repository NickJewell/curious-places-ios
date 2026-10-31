//
//  HuntModel.swift
//  Curious Places
//

import CoreLocation
import Observation

/// Sensors and progress for one hunt: precise location, a smoothed compass heading,
/// the distance and bearing to the target, and arrival.
///
/// Headings only come through a `CLLocationManager` delegate, and `trueHeading` is
/// only valid while that same manager delivers locations. So the hunt runs its own
/// manager at navigation accuracy, alongside the app-wide `LocationProvider`.
@Observable
final class HuntModel: NSObject, CLLocationManagerDelegate {
    enum Page: String, CaseIterable, Identifiable {
        case map = "Map"
        case compass = "Compass"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .map: "map"
            case .compass: "safari"
            }
        }
    }

    let target: Place
    /// The page showing, kept here so it survives putting the compass away.
    var page = Page.map
    let isHeadingAvailable = CLLocationManager.headingAvailable()

    private(set) var location: CLLocation?
    private(set) var progress = HuntProgress()
    /// Smoothed heading, degrees from north. Nil until the first reading.
    private(set) var heading: Double?
    /// Negative when the compass is uncalibrated (Core Location's convention).
    private(set) var headingAccuracy: CLLocationDirection?
    /// Unbounded angles for the dial and the needle, so they turn the short way across north.
    private(set) var dialRotation: Double = 0
    private(set) var arrowRotation: Double = 0
    private(set) var isAuthorizationDenied = false

    private let manager = CLLocationManager()

    init(target: Place) {
        self.target = target
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 1
        manager.activityType = .fitness
        manager.headingFilter = 1
    }

    var bearing: Double? {
        location.map { HuntMath.bearing(from: $0.coordinate, to: target.coordinate) }
    }

    var needsCalibration: Bool {
        guard let headingAccuracy else { return false }
        return headingAccuracy < 0 || headingAccuracy > HuntMath.calibrationAccuracy
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        if isHeadingAvailable { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - Updates

    private func apply(_ location: CLLocation) {
        self.location = location
        let distance = location.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
        progress.update(distance: distance, accuracy: location.horizontalAccuracy)
        updateRotations()
    }

    private func apply(_ reading: CLHeading) {
        headingAccuracy = reading.headingAccuracy
        // trueHeading is negative until a location fix arrives; magnetic is close enough meanwhile.
        var raw = reading.trueHeading >= 0 ? reading.trueHeading : reading.magneticHeading
        guard raw >= 0 else { return }
        // When walking, the GPS course is steadier than the magnetometer.
        if let location, location.speed > HuntMath.walkingSpeed, location.course >= 0 {
            raw = HuntMath.circularMean(raw, location.course, factor: HuntMath.courseBlend)
        }
        heading = heading.map { HuntMath.circularMean($0, raw, factor: HuntMath.headingSmoothing) } ?? raw
        updateRotations()
    }

    private func updateRotations() {
        let heading = heading ?? 0
        dialRotation = HuntMath.unwrapped(-heading, from: dialRotation)
        if let bearing {
            arrowRotation = HuntMath.unwrapped(bearing - heading, from: arrowRotation)
        }
    }

    // MARK: - CLLocationManagerDelegate (delivered on the main thread, where the manager was made)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated { apply(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        MainActor.assumeIsolated { apply(newHeading) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            isAuthorizationDenied = status == .denied || status == .restricted
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Transient (e.g. no fix yet); updates continue when the fix returns.
    }

    /// The calibration hint in the compass page replaces the system's full-screen prompt.
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}
