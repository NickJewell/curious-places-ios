//
//  HuntModel.swift
//  Curious Places
//

import CoreLocation
import MapKit
import Observation

/// Sensors and progress for one hunt: precise location, a smoothed compass heading,
/// the distance and bearing to the target, arrival, and a walking route.
///
/// Headings only come through a `CLLocationManager` delegate, and `trueHeading` is
/// only valid while that same manager delivers locations. So the hunt runs its own
/// manager at navigation accuracy, alongside the app-wide `LocationProvider`.
///
/// The walking route is only for the map page. Arrival and check-in always use the
/// straight-line distance.
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

    /// Apple's walking route from where the user was when it was asked for. Nil until the
    /// first one arrives, and kept when a later request fails.
    private(set) var walkingRoute: MKRoute?
    /// Where the user is along `walkingRoute`, updated on every fix without new requests.
    private(set) var routeProgress: RouteProgress?

    private let manager = CLLocationManager()
    private let directions: DirectionsService
    private var routePath: [MKMapPoint] = []
    private var routePolicy = RoutePolicy()
    private var routeTask: Task<Void, Never>?

    init(target: Place, directions: DirectionsService = DirectionsService()) {
        self.target = target
        self.directions = directions
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

    /// Where the route ends. Walking routes stop at the nearest path, which can be some
    /// way from a plaque in a churchyard, so the map draws the rest as a dashed line.
    var routeEnd: CLLocationCoordinate2D? {
        routePath.last?.coordinate
    }

    /// Metres left along the route, plus the dashed last leg to the place. Nil without a route.
    var remainingWalkingDistance: CLLocationDistance? {
        guard let routeProgress, let end = routePath.last else { return nil }
        return routeProgress.remainingDistance + end.distance(to: MKMapPoint(target.coordinate))
    }

    /// Seconds left at the route's own pace, or nil without a route.
    var remainingWalkingTime: TimeInterval? {
        guard let walkingRoute, let remainingWalkingDistance else { return nil }
        return RouteGeometry.remainingTime(remainingWalkingDistance, routeDistance: walkingRoute.distance,
                                           routeTime: walkingRoute.expectedTravelTime)
    }

    func openInMaps() {
        directions.openWalkingDirectionsInMaps(to: target)
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
        updateRoute(at: location, distance: distance)
    }

    /// Tracks progress along the current route, and asks for a new one when `RoutePolicy`
    /// says so: on the first usable fix, then only when the user strays from the route.
    private func updateRoute(at location: CLLocation, distance: CLLocationDistance) {
        routeProgress = RouteGeometry.progress(of: MKMapPoint(location.coordinate), along: routePath)
        let now = Date.now
        guard routeTask == nil,
              routePolicy.shouldRequest(distanceToTarget: distance, accuracy: location.horizontalAccuracy,
                                        offRoute: routeProgress?.offRouteDistance, now: now) else { return }
        routePolicy.didRequest(at: now)
        let start = location.coordinate
        // Not cancelled when the compass is put away: the route is still wanted on return.
        routeTask = Task {
            defer { routeTask = nil }
            do {
                let route = try await directions.walkingRoute(from: start, to: target)
                walkingRoute = route
                routePath = Array(UnsafeBufferPointer(start: route.polyline.points(), count: route.polyline.pointCount))
                routeProgress = self.location.flatMap {
                    RouteGeometry.progress(of: MKMapPoint($0.coordinate), along: routePath)
                }
            } catch {
                // Throttled, offline or no route: keep any route we have and try again later.
                routePolicy.didFail(at: .now)
            }
        }
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
