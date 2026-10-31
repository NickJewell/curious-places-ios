//
//  DirectionsService.swift
//  Curious Places
//

import CoreLocation
import MapKit

/// Walking routes from Apple's directions service: free, with no key, but throttled per
/// device, so callers decide when to ask (`RoutePolicy`).
struct DirectionsService {
    /// The best walking route, or throws (`MKError.directionsNotFound`, `.loadingThrottled`, no network).
    func walkingRoute(from start: CLLocationCoordinate2D, to place: Place) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude),
                                   address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude),
                                        address: nil)
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        guard let route = try await MKDirections(request: request).calculate().routes.first else {
            throw MKError(.directionsNotFound)
        }
        return route
    }

    /// Hands the place to Apple Maps for spoken walking directions from the user's location.
    func openWalkingDirectionsInMaps(to place: Place) {
        let item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
