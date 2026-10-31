//
//  SaveToListSheet.swift
//  Curious Places
//

import SwiftUI

/// Saves a place to one of the user's lists, or a new one (the Expo map's "Save to List" modal).
/// Lists that already hold the place are ticked; tapping one removes it again.
struct SaveToListSheet: View {
    let place: Place
    @Environment(ListStore.self) private var lists
    @Environment(\.dismiss) private var dismiss
    @State private var showsNewList = false
    @State private var saving: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if lists.lists.isEmpty {
                        Text(lists.isLoading ? "Loading…" : "No lists yet. Create your first one!")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(lists.lists) { list in
                        Button {
                            toggle(list)
                        } label: {
                            HStack {
                                PlaceListRow(list: list, count: lists.itemCount(list))
                                Spacer()
                                if saving.contains(list.id) {
                                    ProgressView()
                                } else {
                                    let isSaved = lists.contains(place.id, in: list)
                                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.title3)
                                        .foregroundStyle(isSaved ? Theme.gold : Theme.textSecondary)
                                        .accessibilityLabel(isSaved ? "Saved" : "Not saved")
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(saving.contains(list.id))
                    }
                } header: {
                    Text(place.name)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button("New List", systemImage: "plus") { showsNewList = true }
                }
                .listRowBackground(Theme.surface)
            }
            .themedList()
            .navigationTitle("Save to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .listNameAlert("New List", isPresented: $showsNewList, actionTitle: "Create and Save") { name in
                createAndSave(named: name)
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: lists.isSaved(place.id)) { _, saved in saved }
    }

    private func toggle(_ list: PlaceList) {
        saving.insert(list.id)
        Task {
            defer { saving.remove(list.id) }
            do {
                if lists.contains(place.id, in: list) {
                    try await lists.remove(place.id, from: list)
                } else {
                    try await lists.add(place, to: list)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createAndSave(named name: String) {
        Task {
            do {
                let list = try await lists.create(named: name)
                saving.insert(list.id)
                defer { saving.remove(list.id) }
                try await lists.add(place, to: list)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
