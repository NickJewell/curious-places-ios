//
//  VisitedPlacesView.swift
//  Curious Places
//

import SwiftUI

/// Every check-in, newest first, with swipe to remove (the Expo VisitedPlacesScreen).
struct VisitedPlacesView: View {
    @Environment(CheckinStore.self) private var checkins
    @Environment(SessionStore.self) private var session
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(checkins.checkins) { checkin in
                CheckinRow(checkin: checkin)
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) { remove(checkin) }
                    }
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .overlay {
            if checkins.checkins.isEmpty && !checkins.isLoading {
                ContentUnavailableView(
                    "No places visited yet",
                    systemImage: "mappin.slash",
                    description: Text("Hunt for a place on the map, then check in when you get there.")
                )
            }
        }
        .navigationTitle("Places Visited")
        .refreshable { await checkins.reload() }
        .alert("Couldn't remove the check-in", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func remove(_ checkin: Checkin) {
        guard let userID = session.userID else { return }
        Task {
            do {
                try await checkins.remove(placeID: checkin.placeID, userID: userID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct CheckinRow: View {
    let checkin: Checkin

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(HuntPalette.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(checkin.placeName)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let date = checkin.checkedInAt {
                    Text("Visited \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
