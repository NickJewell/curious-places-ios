//
//  LocationProvider.swift
//  Curious Places
//

import CoreLocation
import Observation

/// Foreground location for the map and distance labels.
@Observable
final class LocationProvider {
    private(set) var location: CLLocation?
    private(set) var isAuthorizationDenied = false

    private var session: CLServiceSession?

    /// Asks for when-in-use permission and streams updates until the calling task is cancelled.
    func run() async {
        session = CLServiceSession(authorization: .whenInUse)
        defer { session = nil }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                isAuthorizationDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                if let location = update.location {
                    self.location = location
                }
            }
        } catch {
            // The stream only ends early when the task is cancelled.
        }
    }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        location?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
