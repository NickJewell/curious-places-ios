//
//  PlaceService.swift
//  Curious Places
//

import Foundation
import MapKit
import Supabase

/// A latitude/longitude rectangle.
nonisolated struct BoundingBox: Equatable, Sendable {
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    /// The region's rectangle, grown by `buffer` of its span on every side.
    init(region: MKCoordinateRegion, buffer: Double = 0) {
        let halfLat = region.span.latitudeDelta * (0.5 + buffer)
        let halfLon = region.span.longitudeDelta * (0.5 + buffer)
        self.init(
            minLatitude: region.center.latitude - halfLat,
            maxLatitude: region.center.latitude + halfLat,
            minLongitude: region.center.longitude - halfLon,
            maxLongitude: region.center.longitude + halfLon
        )
    }

    func contains(_ other: BoundingBox) -> Bool {
        other.minLatitude >= minLatitude && other.maxLatitude <= maxLatitude
            && other.minLongitude >= minLongitude && other.maxLongitude <= maxLongitude
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        (minLatitude...maxLatitude).contains(latitude) && (minLongitude...maxLongitude).contains(longitude)
    }
}

/// Reads places straight from Supabase with the anon key (decision D2 in docs/migration).
struct PlaceService {
    /// Most rows returned for one map query (matches the Expo server's limit).
    static let viewportLimit = 200

    let client: SupabaseClient

    func places(in box: BoundingBox, language: AppLanguage) async throws -> [Place] {
        let rows: [PlaceRow] = try await client
            .from("places")
            .select(Self.columns(for: language))
            .eq("visible_flag", value: true)
            .gte("lat", value: box.minLatitude)
            .lte("lat", value: box.maxLatitude)
            .gte("lon", value: box.minLongitude)
            .lte("lon", value: box.maxLongitude)
            .order("curio_id")
            .limit(Self.viewportLimit)
            .execute()
            .value
        return rows.compactMap { $0.place(in: language) }
    }

    func place(id: String, language: AppLanguage) async throws -> Place? {
        let rows: [PlaceRow] = try await client
            .from("places")
            .select(Self.columns(for: language))
            .eq("curio_id", value: id)
            .eq("visible_flag", value: true)
            .limit(1)
            .execute()
            .value
        return rows.first?.place(in: language)
    }

    /// Only columns the live Expo server already selects, so the query can't fail
    /// on a column that exists only in the inventory's INFERRED list.
    static func columns(for language: AppLanguage) -> String {
        var columns = ["curio_id", "name", "lat", "lon", "detail_overview", "attributes"]
        if let column = language.overviewColumn { columns.append(column) }
        return columns.joined(separator: ",")
    }
}
