//
//  Checkin.swift
//  Curious Places
//

import CoreLocation
import Foundation

/// A row of `checkins`: one per user and place (`UNIQUE(user_id, place_id)`).
/// `place_id` is a `curio_id`; the name and coordinates are copied at check-in time.
nonisolated struct Checkin: Decodable, Identifiable, Sendable, Equatable {
    let id: UUID
    let placeID: String
    let placeName: String
    let latitude: Double
    let longitude: Double
    let checkedInAt: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case placeID = "place_id"
        case placeName = "place_name"
        case latitude = "place_latitude"
        case longitude = "place_longitude"
        case checkedInAt = "checked_in_at"
    }
}

/// A new row of `checkins`. `user_id` is the auth user (the column references auth.users).
nonisolated struct CheckinWrite: Encodable, Sendable {
    let userID: UUID
    let placeID: String
    let placeName: String
    let latitude: Double
    let longitude: Double

    init(place: Place, userID: UUID) {
        self.userID = userID
        placeID = place.id
        placeName = place.name
        latitude = place.latitude
        longitude = place.longitude
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case placeID = "place_id"
        case placeName = "place_name"
        case latitude = "place_latitude"
        case longitude = "place_longitude"
    }
}

/// A row of `badges`: a badge definition, readable by anyone.
nonisolated struct Badge: Decodable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let description: String
    /// A Feather icon name from the Expo app, e.g. "compass".
    let iconName: String
    let requirementType: String
    let requirementValue: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case iconName = "icon_name"
        case requirementType = "requirement_type"
        case requirementValue = "requirement_value"
    }

    /// The SF Symbol for the badge's Feather icon.
    var systemImage: String {
        switch iconName {
        case "compass": "safari"
        case "map-pin": "mappin.and.ellipse"
        case "book-open": "book"
        case "star": "star.fill"
        case "flag": "flag.fill"
        case "shield": "shield.fill"
        default: "rosette"
        }
    }
}

/// A row of `user_badges`: a badge the user has earned. The database awards
/// them (supabase/proposed/06); the app only reads them.
nonisolated struct EarnedBadge: Decodable, Sendable, Equatable {
    let badgeID: UUID
    let earnedAt: Date?

    enum CodingKeys: String, CodingKey {
        case badgeID = "badge_id"
        case earnedAt = "earned_at"
    }
}

/// What a check-in achieved, for the celebration screen.
nonisolated struct CheckinOutcome: Sendable, Equatable {
    /// False when the place was already checked in (e.g. from another device).
    let isNew: Bool
    let totalCheckins: Int
    /// Badges that appeared in `user_badges` because of this check-in.
    let newBadges: [Badge]

    /// Badges in `after` but not `before`, in the order of `catalog`.
    static func newBadges(catalog: [Badge], before: Set<UUID>, after: Set<UUID>) -> [Badge] {
        let added = after.subtracting(before)
        return catalog.filter { added.contains($0.id) }
    }
}
