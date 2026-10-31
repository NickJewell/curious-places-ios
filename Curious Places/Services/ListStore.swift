//
//  ListStore.swift
//  Curious Places
//

import Foundation
import Observation

/// The signed-in user's saved lists, shared by the map's Save sheet and the
/// Tours tab. Holds every item row too, for counts and "already saved" ticks.
/// Empty for guests.
@Observable
final class ListStore {
    /// Newest first.
    private(set) var lists: [PlaceList] = []
    /// Each list's items, unordered.
    private(set) var items: [UUID: [ListItemRow]] = [:]
    private(set) var isLoading = false
    private(set) var loadFailed = false

    private let service: ListService
    private var userID: UUID?

    init(service: ListService) {
        self.service = service
    }

    func itemCount(_ list: PlaceList) -> Int {
        items[list.id]?.count ?? 0
    }

    func contains(_ placeID: String, in list: PlaceList) -> Bool {
        items[list.id]?.contains { $0.placeID == placeID } ?? false
    }

    func isSaved(_ placeID: String) -> Bool {
        lists.contains { contains(placeID, in: $0) }
    }

    /// Loads everything for `userID`, or clears it all when nil (guests, signed out).
    func load(userID: UUID?) async {
        self.userID = userID
        guard let userID else {
            lists = []
            items = [:]
            isLoading = false
            loadFailed = false
            return
        }
        isLoading = true
        defer { if self.userID == userID { isLoading = false } }
        do {
            let lists = try await service.lists(userID: userID)
            let rows = try await service.items(inLists: lists.map(\.id))
            guard self.userID == userID else { return }
            self.lists = lists
            // Every row has a list_uuid: that's what they were fetched by.
            items = Dictionary(grouping: rows.filter { $0.listID != nil }) { $0.listID! }
            loadFailed = false
        } catch {
            guard self.userID == userID, !(error is CancellationError) else { return }
            loadFailed = true
        }
    }

    func reload() async {
        await load(userID: userID)
    }

    func entries(in list: PlaceList, language: AppLanguage) async throws -> [ListEntry] {
        try await service.entries(inList: list.id, language: language)
    }

    @discardableResult
    func create(named name: String) async throws -> PlaceList {
        guard let userID else { throw ListError.notSaved }
        let list = try await service.createList(named: name, userID: userID)
        lists.insert(list, at: 0)
        return list
    }

    func rename(_ list: PlaceList, to name: String) async throws {
        try await service.renameList(list.id, to: name)
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            lists[index].name = name
        }
    }

    func delete(_ list: PlaceList) async throws {
        try await service.deleteList(list.id)
        lists.removeAll { $0.id == list.id }
        items[list.id] = nil
    }

    /// Adds the place at the end of the list. Does nothing if it's already there.
    func add(_ place: Place, to list: PlaceList) async throws {
        guard !contains(place.id, in: list) else { return }
        let next = (items[list.id]?.compactMap(\.orderIndex).max() ?? 0) + 1
        if let row = try await service.addItem(placeID: place.id, to: list.id, orderIndex: next) {
            items[list.id, default: []].append(row)
        } else if let rows = try? await service.items(inLists: [list.id]) {
            // Already there (saved from another device): catch up.
            items[list.id] = rows
        }
    }

    func remove(_ placeID: String, from list: PlaceList) async throws {
        guard let row = items[list.id]?.first(where: { $0.placeID == placeID }) else { return }
        try await removeItem(row.id, from: list)
    }

    func removeItem(_ itemID: UUID, from list: PlaceList) async throws {
        try await service.removeItem(itemID)
        items[list.id]?.removeAll { $0.id == itemID }
    }

    /// Saves a new order for the list's items, given as `list_item_uuid`s.
    func reorder(_ list: PlaceList, itemIDs: [UUID]) async throws {
        try await service.reorder(itemIDs)
        let rows = try await service.items(inLists: [list.id])
        items[list.id] = rows
    }
}
