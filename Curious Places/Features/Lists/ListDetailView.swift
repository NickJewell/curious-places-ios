//
//  ListDetailView.swift
//  Curious Places
//

import SwiftUI

/// One saved list: rename, reorder, remove, and walk it as a route (the Expo ListDetailScreen).
/// Expo's "Start Hunt" only ever went to the first place; here the hunt moves on stop by stop.
struct ListDetailView: View {
    let list: PlaceList
    @Environment(ListStore.self) private var lists
    @Environment(HuntStore.self) private var hunt
    @Environment(CheckinStore.self) private var checkins
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.deviceDefault()

    @State private var entries: [ListEntry] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showsRename = false
    @State private var pendingRemove: ListEntry?
    @State private var detailPlace: Place?
    /// Set when "Navigate Here" is tapped in the detail sheet; the route starts once it closes.
    @State private var pendingStart: Int?
    @State private var errorMessage: String?

    /// The name as saved, which a rename changes.
    private var name: String {
        lists.lists.first { $0.id == list.id }?.name ?? list.name
    }

    var body: some View {
        List {
            if !entries.isEmpty {
                Section {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            detailPlace = entry.place
                        } label: {
                            StopRow(number: index + 1, place: entry.place,
                                    isVisited: checkins.isCheckedIn(entry.place.id))
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) { pendingRemove = entry }
                        }
                    }
                    .onMove(perform: move)
                } header: {
                    Text(entries.count == 1 ? "1 place" : "\(entries.count) places")
                } footer: {
                    if entries.count > 1 {
                        Text("Tap Edit to reorder. Start Hunt walks the list in this order.")
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .themedList()
        .overlay {
            if entries.isEmpty {
                if isLoading {
                    ProgressView()
                } else if loadFailed {
                    ContentUnavailableView {
                        Label("Couldn't load this list", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else {
                    ContentUnavailableView(
                        "No Places Yet",
                        systemImage: "mappin",
                        description: Text("Find places on the map and save them to this list.")
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !entries.isEmpty {
                HuntButton(title: hunt.route?.id == list.id ? "Resume Hunt" : "Start Hunt") {
                    start(at: nil)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if entries.count > 1 {
                EditButton()
            }
            Button("Rename", systemImage: "pencil") { showsRename = true }
        }
        .task(id: language) { await load() }
        .refreshable { await load() }
        .listNameAlert("Rename List", isPresented: $showsRename, initialName: name, actionTitle: "Save") { newName in
            Task {
                do {
                    try await lists.rename(list, to: newName)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Remove \u{201C}\(pendingRemove?.place.name ?? "")\u{201D} from this list?",
                            isPresented: Binding { pendingRemove != nil } set: { if !$0 { pendingRemove = nil } },
                            titleVisibility: .visible,
                            presenting: pendingRemove) { entry in
            Button("Remove", role: .destructive) { remove(entry) }
            Button("Cancel", role: .cancel) { pendingRemove = nil }
        }
        .sheet(item: $detailPlace, onDismiss: {
            if let index = pendingStart {
                pendingStart = nil
                start(at: index)
            }
        }) { place in
            PlaceDetailView(place: place) {
                pendingStart = entries.firstIndex { $0.place.id == place.id }
                detailPlace = nil
            }
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await lists.entries(in: list, language: language)
            loadFailed = false
        } catch {
            if !(error is CancellationError) { loadFailed = true }
        }
    }

    /// Starts at `index`, or at the first place not yet checked in.
    private func start(at index: Int?) {
        if index == nil, hunt.route?.id == list.id {
            hunt.resume()
            return
        }
        let stops = entries.map(\.place)
        guard !stops.isEmpty else { return }
        let start = index ?? HuntRoute.startIndex(of: stops, checkedIn: checkins.checkedInIDs)
        hunt.begin(HuntRoute(id: list.id, title: name, isTour: false, stops: stops, startingAt: start))
    }

    private func move(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        let itemIDs = entries.map(\.id)
        Task {
            do {
                try await lists.reorder(list, itemIDs: itemIDs)
            } catch {
                errorMessage = "Couldn't save the new order. \(error.localizedDescription)"
                await load()
            }
        }
    }

    private func remove(_ entry: ListEntry) {
        pendingRemove = nil
        Task {
            do {
                try await lists.removeItem(entry.id, from: list)
                entries.removeAll { $0.id == entry.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A numbered place in a list or tour.
struct StopRow: View {
    let number: Int
    let place: Place
    let isVisited: Bool
    var tint = Theme.gold

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: .circle)
                .overlay(Circle().stroke(tint.opacity(0.5)))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if !place.overviewText.isEmpty {
                    Text(place.overviewText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isVisited {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.gold)
                    .accessibilityLabel("Visited")
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
