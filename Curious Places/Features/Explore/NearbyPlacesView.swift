//
//  NearbyPlacesView.swift
//  Curious Places
//

import CoreLocation
import SwiftUI

/// Places in the user's r9 H3 cell and the six around it, opened from the map's Nearby button.
/// Tapping one hands it back to the map, which selects it as if its marker had been tapped.
struct NearbyPlacesView: View {
    let service: PlaceService
    let onSelect: (Place) -> Void
    @Environment(LocationProvider.self) private var location
    @Environment(CheckinStore.self) private var checkins
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.deviceDefault()

    @State private var places: [Place] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    /// Set after the first load, so an empty result shows "Nothing Nearby" rather than a spinner.
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            List {
                if !places.isEmpty {
                    Section {
                        ForEach(places) { place in
                            Button {
                                onSelect(place)
                                dismiss()
                            } label: {
                                NearbyRow(place: place, user: location.location?.coordinate,
                                          isVisited: checkins.isCheckedIn(place.id))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(places.count == 1 ? "1 place" : "\(places.count) places")
                            .sectionTitleStyle()
                    } footer: {
                        Text("Within a few hundred metres of where you are.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .themedList()
            .overlay { emptyState }
            .refreshable { await load() }
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Loads once the first fix arrives, if the sheet opened before it did.
        .task(id: location.location != nil) {
            if !hasLoaded { await load() }
        }
        .onChange(of: language) { Task { await load() } }
    }

    @ViewBuilder
    private var emptyState: some View {
        if places.isEmpty {
            if location.location == nil {
                if location.isAuthorizationDenied {
                    ContentUnavailableView(
                        "Location Off",
                        systemImage: "location.slash",
                        description: Text("Allow location access in Settings to see what's nearby.")
                    )
                } else {
                    ProgressView("Finding you…")
                }
            } else if isLoading || !hasLoaded {
                ProgressView()
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Couldn't load nearby places", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else {
                ContentUnavailableView(
                    "Nothing Nearby",
                    systemImage: "location.magnifyingglass",
                    description: Text("There are no places within a few hundred metres. Explore the map to find some.")
                )
            }
        }
    }

    private func load() async {
        guard let user = location.location?.coordinate else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            places = try await service.placesNear(
                latitude: user.latitude, longitude: user.longitude, language: language
            )
            loadFailed = false
        } catch {
            guard !(error is CancellationError) else { return }
            loadFailed = true
        }
        hasLoaded = true
    }
}

/// Name, type, distance and direction. Distance and direction follow the user as they walk;
/// the order stays as loaded so rows don't jump about (pull to refresh re-sorts).
private struct NearbyRow: View {
    let place: Place
    let user: CLLocationCoordinate2D?
    let isVisited: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(place.name)
                    .font(.body.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    CategoryBadge(category: place.category)
                    if isVisited {
                        VisitedBadge()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let user {
                let bearing = HuntMath.bearing(from: user, to: place.coordinate)
                let distance = CLLocation(latitude: user.latitude, longitude: user.longitude)
                    .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                VStack(alignment: .trailing, spacing: 4) {
                    Text(distance.formattedDistance)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    // North-up, like the map: the arrow points the way the place lies on a map.
                    Label {
                        Text(HuntMath.cardinal(bearing))
                    } icon: {
                        Image(systemName: "location.north.fill")
                            .rotationEffect(.degrees(bearing))
                            .accessibilityHidden(true)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(distance.formattedDistance) \(Self.spokenDirection(bearing))")
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private static func spokenDirection(_ bearing: Double) -> String {
        switch HuntMath.cardinal(bearing) {
        case "N": "north"
        case "NE": "north-east"
        case "E": "east"
        case "SE": "south-east"
        case "S": "south"
        case "SW": "south-west"
        case "W": "west"
        default: "north-west"
        }
    }
}
