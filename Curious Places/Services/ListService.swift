//
//  ListService.swift
//  Curious Places
//

import Foundation
import Supabase

/// Saved lists and official tours, read and written directly with the user's
/// session. Needs the `list_items` policies in supabase/proposed/07: the live
/// table has none, so without them every item read and write fails.
///
/// Items are always matched on `list_uuid`, the column the Expo server reads
/// tours by. There's no foreign key to embed, so places are fetched separately.
struct ListService {
    let client: SupabaseClient
    let places: PlaceService

    // MARK: - Lists

    /// The user's own lists, newest first. Tours are excluded even when the user
    /// owns them (the admin account owns every tour).
    func lists(userID: UUID) async throws -> [PlaceList] {
        let rows: [PlaceList] = try await client
            .from("lists")
            .select("id,name,created_at,list_type")
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.filter { !$0.isTour }
    }

    func createList(named name: String, userID: UUID) async throws -> PlaceList {
        try await client
            .from("lists")
            .insert(PlaceListWrite(userID: userID, name: name))
            .select("id,name,created_at,list_type")
            .single()
            .execute()
            .value
    }

    func renameList(_ listID: UUID, to name: String) async throws {
        let updated: [IDRow] = try await client
            .from("lists")
            .update(PlaceListRename(name: name, updatedAt: .now))
            .eq("id", value: listID)
            .select("id")
            .execute()
            .value
        if updated.isEmpty { throw ListError.notSaved }
    }

    /// The items go too, by the cascade in supabase/proposed/07.
    func deleteList(_ listID: UUID) async throws {
        let deleted: [IDRow] = try await client
            .from("lists")
            .delete()
            .eq("id", value: listID)
            .select("id")
            .execute()
            .value
        if deleted.isEmpty { throw ListError.notSaved }
    }

    // MARK: - Items

    /// Every item in these lists or tours, unordered.
    func items(inLists listIDs: [UUID]) async throws -> [ListItemRow] {
        guard !listIDs.isEmpty else { return [] }
        return try await client
            .from("list_items")
            .select(ListItemRow.columns)
            .in("list_uuid", values: listIDs)
            .execute()
            .value
    }

    /// A list's or tour's places in order, in the user's language. Hidden places are left out.
    func entries(inList listID: UUID, language: AppLanguage) async throws -> [ListEntry] {
        let rows = try await items(inLists: [listID])
        let found = try await places.places(ids: Array(Set(rows.map(\.placeID))), language: language)
        return ListEntry.entries(rows: rows, places: found)
    }

    /// Returns nil if the place is already in the list (`23505`, as in lists.ts:137).
    func addItem(placeID: String, to listID: UUID, orderIndex: Int) async throws -> ListItemRow? {
        do {
            return try await client
                .from("list_items")
                .insert(ListItemWrite(listID: listID, placeID: placeID, orderIndex: orderIndex))
                .select(ListItemRow.columns)
                .single()
                .execute()
                .value
        } catch let error as PostgrestError where error.code == "23505" {
            return nil
        }
    }

    func removeItem(_ itemID: UUID) async throws {
        let deleted: [ItemIDRow] = try await client
            .from("list_items")
            .delete()
            .eq("list_item_uuid", value: itemID)
            .select("list_item_uuid")
            .execute()
            .value
        if deleted.isEmpty { throw ListError.notSaved }
    }

    /// Numbers the items 1, 2, 3… in the given order, one update per row (as in lists.ts:167).
    func reorder(_ itemIDs: [UUID]) async throws {
        let client = client
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, itemID) in itemIDs.enumerated() {
                group.addTask {
                    try await client
                        .from("list_items")
                        .update(["order_index": index + 1])
                        .eq("list_item_uuid", value: itemID)
                        .execute()
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Tours

    /// Every official tour, newest first (as the Expo server's `/api/tours`).
    func tours() async throws -> [Tour] {
        try await client
            .from("lists")
            .select(Tour.columns)
            .eq("list_type", value: "tour")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// How many visible stops each tour has. Hidden places are left out, as on the tour page.
    func stopCounts(for tours: [Tour]) async throws -> [UUID: Int] {
        let rows = try await items(inLists: tours.map(\.id))
        let visible = try await places.visibleIDs(Array(Set(rows.map(\.placeID))))
        var counts: [UUID: Int] = [:]
        for row in rows where visible.contains(row.placeID) {
            if let listID = row.listID { counts[listID, default: 0] += 1 }
        }
        return counts
    }

    /// Tours the user has completed, recorded by the trigger in supabase/proposed/07.
    func completedTourIDs(userID: UUID) async throws -> Set<UUID> {
        let rows: [TourCompletion] = try await client
            .from("tour_completions")
            .select("tour_id")
            .eq("user_id", value: userID)
            .execute()
            .value
        return Set(rows.map(\.tourID))
    }

    private nonisolated struct IDRow: Decodable, Sendable {
        let id: UUID
    }

    private nonisolated struct ItemIDRow: Decodable, Sendable {
        let listItemUUID: UUID

        enum CodingKeys: String, CodingKey {
            case listItemUUID = "list_item_uuid"
        }
    }
}

enum ListError: LocalizedError {
    case notSaved

    var errorDescription: String? {
        switch self {
        case .notSaved: "The change couldn't be saved. Please try again later."
        }
    }
}
