//
//  PlaceList.swift
//  Curious Places
//

import Foundation

/// A row of `lists` with `list_type = 'list'`: places a user has saved.
nonisolated struct PlaceList: Decodable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date?
    /// "list", "tour", or nil (the column default is "list").
    let listType: String?

    var isTour: Bool { listType == "tour" }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case listType = "list_type"
    }
}

/// A new row of `lists`. `user_id` is the auth user.
nonisolated struct PlaceListWrite: Encodable, Sendable {
    let userID: UUID
    let name: String
    let listType = "list"

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name
        case listType = "list_type"
    }
}

/// A rename. There's no trigger on `lists`, so `updated_at` is set by hand (as in lists.ts:74).
nonisolated struct PlaceListRename: Encodable, Sendable {
    let name: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case updatedAt = "updated_at"
    }
}

/// A row of `lists` with `list_type = 'tour'`: an official walking tour.
/// The live table has no `metadata` column, so there are no hero images.
nonisolated struct Tour: Decodable, Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let description: String?
    /// `tour_length`: roughly how long it takes, e.g. "2-3 hours".
    let duration: String?
    /// `tour_length_category`: Short, Medium, Long or Half Day.
    let lengthCategory: String?
    let startRegion: String?
    let endRegion: String?
    let promotedFlag: Bool?

    var isPromoted: Bool { promotedFlag == true }

    /// The heading the tour is grouped under (ListsScreen.tsx groups by start region).
    var region: String {
        guard let startRegion, !startRegion.isEmpty else { return Tour.otherRegion }
        return startRegion
    }

    static let otherRegion = "Other"
    static let columns = "id,name,description,tour_length,tour_length_category,tour_start_region,tour_end_region,promoted_flag"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case duration = "tour_length"
        case lengthCategory = "tour_length_category"
        case startRegion = "tour_start_region"
        case endRegion = "tour_end_region"
        case promotedFlag = "promoted_flag"
    }

    /// Region headings in order: alphabetical, with "Other" last.
    static func grouped(_ tours: [Tour]) -> [(region: String, tours: [Tour])] {
        Dictionary(grouping: tours, by: \.region)
            .sorted { a, b in
                if a.key == otherRegion { return false }
                if b.key == otherRegion { return true }
                return a.key.localizedStandardCompare(b.key) == .orderedAscending
            }
            .map { (region: $0.key, tours: $0.value) }
    }
}

/// A row of `list_items`: one place in a list or tour.
///
/// The live table differs from the Expo migration: the key is `list_item_uuid`,
/// rows point at their list through `list_uuid` (`list_id` holds the same id as
/// text), and there are no copied place names or coordinates.
nonisolated struct ListItemRow: Decodable, Identifiable, Sendable, Hashable {
    let id: UUID
    let listID: UUID?
    let placeID: String
    let orderIndex: Int?
    let createdAt: Date?

    static let columns = "list_item_uuid,list_uuid,place_id,order_index,created_at"

    enum CodingKeys: String, CodingKey {
        case id = "list_item_uuid"
        case listID = "list_uuid"
        case placeID = "place_id"
        case orderIndex = "order_index"
        case createdAt = "created_at"
    }

    /// By `order_index`, then oldest first. Rows with no index go last.
    static func ordered(_ rows: [ListItemRow]) -> [ListItemRow] {
        rows.sorted { a, b in
            switch (a.orderIndex, b.orderIndex) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
            }
        }
    }
}

/// A new row of `list_items`. `list_id` must be the list's id as lowercase text,
/// which the insert policy in supabase/proposed/07 checks.
nonisolated struct ListItemWrite: Encodable, Sendable {
    let listID: UUID
    let placeID: String
    let orderIndex: Int

    enum CodingKeys: String, CodingKey {
        case listIDText = "list_id"
        case listID = "list_uuid"
        case placeID = "place_id"
        case orderIndex = "order_index"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(listID.uuidString.lowercased(), forKey: .listIDText)
        try container.encode(listID, forKey: .listID)
        try container.encode(placeID, forKey: .placeID)
        try container.encode(orderIndex, forKey: .orderIndex)
    }
}

/// A list item or tour stop with its place. Items whose place is hidden or gone
/// are left out, as the Expo server did for tours.
nonisolated struct ListEntry: Identifiable, Sendable, Hashable {
    /// `list_item_uuid`.
    let id: UUID
    let place: Place

    static func entries(rows: [ListItemRow], places: [Place]) -> [ListEntry] {
        let byID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ListItemRow.ordered(rows).compactMap { row in
            byID[row.placeID].map { ListEntry(id: row.id, place: $0) }
        }
    }
}

/// A row of `tour_completions`, written by the database (supabase/proposed/07).
nonisolated struct TourCompletion: Decodable, Sendable {
    let tourID: UUID

    enum CodingKeys: String, CodingKey {
        case tourID = "tour_id"
    }
}
