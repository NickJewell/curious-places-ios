//
//  HuntMath.swift
//  Curious Places
//

import CoreLocation
import Foundation

/// Thresholds and geometry for the hunt, ported from CompassScreen.tsx and HuntMapView.tsx.
nonisolated enum HuntMath {
    /// Under this distance the hunt counts as arrived (`ARRIVAL_THRESHOLD`).
    static let arrivalDistance: CLLocationDistance = 10
    /// Check-in is allowed under this distance (`CHECKIN_THRESHOLD`).
    static let checkInDistance: CLLocationDistance = 40
    /// "Get within 40 m" is shown under this distance.
    static let nearbyDistance: CLLocationDistance = 60
    /// Fixes less accurate than this don't count for arrival or check-in.
    static let requiredAccuracy: CLLocationAccuracy = 20
    /// Weight of each new compass reading in the low-pass filter.
    static let headingSmoothing = 0.2
    /// Above walking pace, the GPS course is blended into the compass this much.
    static let walkingSpeed: CLLocationSpeed = 1
    static let courseBlend = 0.6
    /// Above this heading error (degrees), suggest calibrating.
    static let calibrationAccuracy: CLLocationDirection = 30
    /// The target pulses on the hunt map within this distance.
    static let pulseDistance: CLLocationDistance = 1000

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Moves `current` towards `target` by `factor`, the short way round the circle.
    static func circularMean(_ current: Double, _ target: Double, factor: Double) -> Double {
        let c = current * .pi / 180
        let t = target * .pi / 180
        let x = cos(c) * (1 - factor) + cos(t) * factor
        let y = sin(c) * (1 - factor) + sin(t) * factor
        return normalized(atan2(y, x) * 180 / .pi)
    }

    /// The angle to animate to so that `angle` is reached the short way from `previous`.
    /// `previous` is unbounded (it accumulates turns), so the needle never spins
    /// all the way round when crossing north.
    static func unwrapped(_ angle: Double, from previous: Double) -> Double {
        var diff = normalized(angle) - normalized(previous)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return previous + diff
    }

    /// Initial great-circle bearing from `start` to `end`, in degrees from true north.
    static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalized(atan2(y, x) * 180 / .pi)
    }

    static func cardinal(_ bearing: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return directions[Int((normalized(bearing) / 45).rounded()) % 8]
    }

    /// Degrees and decimal minutes, e.g. "N 51° 30.450'".
    static func formatted(_ value: Double, isLatitude: Bool) -> String {
        let direction = isLatitude ? (value >= 0 ? "N" : "S") : (value >= 0 ? "E" : "W")
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutes = (absolute - Double(degrees)) * 60
        return "\(direction) \(degrees)° \(minutes.formatted(.number.precision(.fractionLength(3))))'"
    }

    /// Always metric, as in the Expo app, to match the 10 m and 40 m thresholds.
    static func formattedDistance(_ distance: CLLocationDistance) -> String {
        if distance >= 1000 {
            return "\((distance / 1000).formatted(.number.precision(.fractionLength(1)))) km"
        }
        return "\(Int(distance.rounded())) m"
    }

    /// One pulse cycle, from 2 s at 1 km down to 0.4 s at 50 m.
    static func pulseDuration(distance: CLLocationDistance) -> TimeInterval {
        if distance <= 50 { return 0.4 }
        if distance >= 1000 { return 2 }
        return 0.4 + (distance - 50) / 950 * 1.6
    }

    /// 0 (no pulse) to 4 (closest). Restarting the animation per tier, not per metre,
    /// keeps it from stuttering as the distance changes.
    static func pulseTier(distance: CLLocationDistance) -> Int {
        switch distance {
        case 1000...: 0
        case 500...: 1
        case 150...: 2
        case 50...: 3
        default: 4
        }
    }
}

/// Arrival and check-in eligibility, fed one location fix at a time.
nonisolated struct HuntProgress: Equatable, Sendable {
    private(set) var distance: CLLocationDistance?
    /// Within check-in range on the latest accurate fix.
    private(set) var canCheckIn = false
    /// Once arrived, the hunt stays arrived, even if the user wanders off.
    private(set) var hasArrived = false

    /// Inaccurate fixes still update the distance shown, but not eligibility.
    mutating func update(distance: CLLocationDistance, accuracy: CLLocationAccuracy) {
        self.distance = distance
        let isAccurate = accuracy >= 0 && accuracy <= HuntMath.requiredAccuracy
        guard isAccurate else { return }
        canCheckIn = distance < HuntMath.checkInDistance
        if distance < HuntMath.arrivalDistance { hasArrived = true }
    }
}
