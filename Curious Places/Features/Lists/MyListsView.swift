//
//  MyListsView.swift
//  Curious Places
//

import SwiftUI

/// The user's saved lists, newest first, with swipe to delete (the "My Lists" half of ListsScreen).
struct MyListsView: View {
    @Environment(ListStore.self) private var lists
    @Environment(SessionStore.self) private var session
    @State private var showsSignIn = false
    @State private var pendingDelete: PlaceList?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if session.status == .signedIn {
                content
            } else {
                ContentUnavailableView {
                    Label("Sign In Required", systemImage: "lock")
                } description: {
                    Text("Create an account to save your favourite places into lists.")
                } actions: {
                    Button("Sign In") { showsSignIn = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $showsSignIn) {
            SignInView(allowsGuest: false)
        }
        .onChange(of: session.status) {
            if session.status == .signedIn { showsSignIn = false }
        }
    }

    private var content: some View {
        List {
            ForEach(lists.lists) { list in
                NavigationLink(value: list) {
                    PlaceListRow(list: list, count: lists.itemCount(list))
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = list }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .overlay {
            if lists.lists.isEmpty {
                if lists.isLoading {
                    ProgressView()
                } else if lists.loadFailed {
                    ContentUnavailableView {
                        Label("Couldn't load your lists", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Retry") { Task { await lists.reload() } }
                    }
                } else {
                    ContentUnavailableView(
                        "No Lists Yet",
                        systemImage: "list.bullet",
                        description: Text("Save places from the map, or tap + to start a list.")
                    )
                }
            }
        }
        .refreshable { await lists.reload() }
        .confirmationDialog("Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
                            isPresented: Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } },
                            titleVisibility: .visible,
                            presenting: pendingDelete) { list in
            Button("Delete List", role: .destructive) { delete(list) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert("Couldn't delete the list", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func delete(_ list: PlaceList) {
        pendingDelete = nil
        Task {
            do {
                try await lists.delete(list)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PlaceListRow: View {
    let list: PlaceList
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 40, height: 40)
                .background(Theme.gold.opacity(0.12), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let places = count == 1 ? "1 place" : "\(count) places"
        guard let date = list.createdAt else { return places }
        return "\(places) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
