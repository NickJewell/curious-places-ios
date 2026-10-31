//
//  RouteMath.swift
//  Curious Places
//

import CoreLocation
import Foundation
import MapKit

/// Where the user is relative to a walking route, worked out locally between directions requests.
nonisolated struct RouteProgress: Equatable, Sendable {
    /// Metres from the user to the nearest point on the route.
    let offRouteDistance: CLLocationDistance
    /// Metres left along the route from that nearest point to its end.
    let remainingDistance: CLLocationDistance
}

/// Geometry on a route's polyline. Map points are planar, so projecting onto a segment
/// is plain vector maths; `MKMapPoint.distance(to:)` turns the results into metres.
nonisolated enum RouteGeometry {
    /// Nil for an empty path.
    static func progress(of point: MKMapPoint, along path: [MKMapPoint]) -> RouteProgress? {
        guard let first = path.first else { return nil }
        guard path.count > 1 else {
            return RouteProgress(offRouteDistance: point.distance(to: first), remainingDistance: 0)
        }

        var nearest = (distance: CLLocationDistance.infinity, segment: 0, point: first)
        for segment in 0..<(path.count - 1) {
            let projected = project(point, from: path[segment], to: path[segment + 1])
            let distance = point.distance(to: projected)
            if distance < nearest.distance {
                nearest = (distance, segment, projected)
            }
        }

        var remaining = nearest.point.distance(to: path[nearest.segment + 1])
        for segment in (nearest.segment + 1)..<(path.count - 1) {
            remaining += path[segment].distance(to: path[segment + 1])
        }
        return RouteProgress(offRouteDistance: nearest.distance, remainingDistance: remaining)
    }

    /// The closest point to `point` on the segment from `start` to `end`.
    static func project(_ point: MKMapPoint, from start: MKMapPoint, to end: MKMapPoint) -> MKMapPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return start }
        let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clamped = min(max(t, 0), 1)
        return MKMapPoint(x: start.x + clamped * dx, y: start.y + clamped * dy)
    }

    /// The time left at the route's own pace (Apple's estimate for the whole route).
    static func remainingTime(_ remaining: CLLocationDistance, routeDistance: CLLocationDistance,
                              routeTime: TimeInterval) -> TimeInterval? {
        guard routeDistance > 0, routeTime > 0 else { return nil }
        return remaining / routeDistance * routeTime
    }

    /// Whole minutes, rounded up, never less than one. Shown and spoken alike.
    static func walkingMinutes(_ seconds: TimeInterval) -> Int {
        max(1, Int((seconds / 60).rounded(.up)))
    }

    /// "12 min", or "1 h 5 min".
    static func formattedWalkingTime(_ seconds: TimeInterval) -> String {
        let minutes = walkingMinutes(seconds)
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

/// When to ask Apple for walking directions. Requests are throttled per device
/// (`MKError.loadingThrottled`), so they're driven by events, never by every fix:
/// the first usable fix, then only when the user strays from the route.
nonisolated struct RoutePolicy: Equatable, Sendable {
    /// The first route only needs a rough fix; check-in needs far better.
    static let firstFixAccuracy: CLLocationAccuracy = 100
    /// Closer than this, the compass does the job and routes stop helping.
    static let minimumDistance: CLLocationDistance = 75
    /// Further than this from the route, on an accurate fix, asks for a new one.
    static let offRouteDistance: CLLocationDistance = 30
    static let minimumInterval: TimeInterval = 20
    /// After a failure (throttling, no network, no route), wait this long before trying again.
    static let failureBackoff: TimeInterval = 60
    /// Per hunt stop; after this the last route stays.
    static let maximumRequests = 15

    private(set) var requestCount = 0
    private(set) var lastRequest: Date?
    private(set) var retryAfter: Date?

    /// - Parameter offRoute: metres from the current route, or nil if there's no route yet.
    func shouldRequest(distanceToTarget: CLLocationDistance, accuracy: CLLocationAccuracy,
                       offRoute: CLLocationDistance?, now: Date) -> Bool {
        guard requestCount < Self.maximumRequests,
              accuracy >= 0,
              distanceToTarget >= Self.minimumDistance else { return false }
        if let retryAfter, now < retryAfter { return false }
        if let lastRequest, now.timeIntervalSince(lastRequest) < Self.minimumInterval { return false }
        guard let offRoute else { return accuracy <= Self.firstFixAccuracy }
        return accuracy <= HuntMath.requiredAccuracy && offRoute > Self.offRouteDistance
    }

    mutating func didRequest(at now: Date) {
        requestCount += 1
        lastRequest = now
    }

    mutating func didFail(at now: Date) {
        retryAfter = now.addingTimeInterval(Self.failureBackoff)
    }
}
