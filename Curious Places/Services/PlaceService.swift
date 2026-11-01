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

    /// Visible places with these ids, in no particular order. Hidden or missing ids are left out.
    func places(ids: [String], language: AppLanguage) async throws -> [Place] {
        guard !ids.isEmpty else { return [] }
        let rows: [PlaceRow] = try await client
            .from("places")
            .select(Self.columns(for: language))
            .in("curio_id", values: ids)
            .eq("visible_flag", value: true)
            .execute()
            .value
        return rows.compactMap { $0.place(in: language) }
    }

    /// Visible places in the r9 H3 cell at this point and the six cells around it, nearest
    /// first (`places_near` in supabase/proposed/08). Empty more than two rings from any place.
    func placesNear(latitude: Double, longitude: Double, language: AppLanguage) async throws -> [Place] {
        let rows: [PlaceRow] = try await client
            .rpc("places_near", params: NearParams(lat: latitude, lon: longitude, k: 1, res: 9))
            .select(Self.columns(for: language))
            .limit(Self.nearbyLimit)
            .execute()
            .value
        return rows.compactMap { $0.place(in: language) }
    }

    /// Most rows for "Nearby". The busiest spots in the City have about 100.
    static let nearbyLimit = 150

    private nonisolated struct NearParams: Encodable, Sendable {
        let lat: Double
        let lon: Double
        let k: Int
        let res: Int
    }

    /// Which of these ids are visible places.
    func visibleIDs(_ ids: [String]) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let rows: [CurioIDRow] = try await client
            .from("places")
            .select("curio_id")
            .in("curio_id", values: ids)
            .eq("visible_flag", value: true)
            .execute()
            .value
        return Set(rows.map(\.curioID))
    }

    private nonisolated struct CurioIDRow: Decodable, Sendable {
        let curioID: String

        enum CodingKeys: String, CodingKey {
            case curioID = "curio_id"
        }
    }

    /// Only columns the live Expo server already selects, so the query can't fail
    /// on a column that exists only in the inventory's INFERRED list.
    static func columns(for language: AppLanguage) -> String {
        var columns = ["curio_id", "name", "lat", "lon", "detail_overview", "attributes"]
        if let column = language.overviewColumn { columns.append(column) }
        return columns.joined(separator: ",")
    }
}
