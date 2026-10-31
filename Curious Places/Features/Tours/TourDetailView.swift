//
//  TourDetailView.swift
//  Curious Places
//

import MapKit
import SwiftUI

/// One tour: its route on a map, stats, description and numbered stops (the Expo TourDetailScreen).
/// Unlike Expo, "Start Tour" walks the stops one hunt at a time, and checking in at
/// every stop completes the tour (recorded by the database, supabase/proposed/07).
struct TourDetailView: View {
    let tour: Tour
    let isCompleted: Bool
    let service: ListService
    @Environment(HuntStore.self) private var hunt
    @Environment(CheckinStore.self) private var checkins
    @Environment(SessionStore.self) private var session
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.deviceDefault()

    @State private var stops: [Place] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var detailPlace: Place?
    /// Set when "Navigate Here" is tapped in the detail sheet; the tour starts once it closes.
    @State private var pendingStart: Int?

    private var visitedCount: Int {
        stops.count { checkins.isCheckedIn($0.id) }
    }

    private var isOnThisTour: Bool { hunt.route?.id == tour.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TourRouteMap(stops: stops)
                    .frame(height: 240)
                    .clipShape(.rect(cornerRadius: 18))

                Text(tour.name)
                    .font(.title.weight(.bold))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.textPrimary)

                TourStats(tour: tour, stopCount: isLoading ? nil : stops.count)
                    .font(.subheadline)

                if let regions {
                    Label(regions, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let description = tour.description, !description.isEmpty {
                    Text(description)
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(6)
                }

                progress

                Text(stops.isEmpty ? "Route" : "Route (\(stops.count) \(stops.count == 1 ? "stop" : "stops"))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 8)

                stopList
            }
            .padding()
        }
        .background(Theme.backgroundRoot)
        .navigationTitle(tour.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !stops.isEmpty {
                HuntButton(title: startTitle) { start(at: nil) }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .task(id: language) { await load() }
        .sheet(item: $detailPlace, onDismiss: {
            if let index = pendingStart {
                pendingStart = nil
                start(at: index)
            }
        }) { place in
            PlaceDetailView(place: place) {
                pendingStart = stops.firstIndex { $0.id == place.id }
                detailPlace = nil
            }
        }
    }

    private var regions: String? {
        guard let start = tour.startRegion, !start.isEmpty else { return nil }
        guard let end = tour.endRegion, !end.isEmpty, end != start else { return "Starts and ends in \(start)" }
        return "\(start) to \(end)"
    }

    @ViewBuilder
    private var progress: some View {
        if session.status == .signedIn, !stops.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if isCompleted || visitedCount == stops.count {
                    Label("Tour complete", systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                } else {
                    Text("\(visitedCount) of \(stops.count) stops checked in")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                ProgressView(value: Double(visitedCount), total: Double(stops.count))
                    .tint(Theme.gold)
            }
        } else if session.status != .signedIn, !stops.isEmpty {
            Label("Sign in and check in at every stop to complete this tour.", systemImage: "flag.checkered")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var stopList: some View {
        if isLoading && stops.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if loadFailed && stops.isEmpty {
            VStack(spacing: 8) {
                Text("Couldn't load the stops.")
                    .foregroundStyle(Theme.textSecondary)
                Button("Retry") { Task { await load() } }
            }
            .frame(maxWidth: .infinity)
        } else if stops.isEmpty {
            Text("This tour has no stops yet.")
                .foregroundStyle(Theme.textSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                    Button {
                        detailPlace = place
                    } label: {
                        HStack {
                            StopRow(number: index + 1, place: place, isVisited: checkins.isCheckedIn(place.id),
                                    tint: TourRouteMap.color(forStop: index, of: stops.count))
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if index < stops.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    private var startTitle: String {
        if isOnThisTour { return "Resume Tour" }
        let index = HuntRoute.startIndex(of: stops, checkedIn: checkins.checkedInIDs)
        return index == 0 ? "Start Tour" : "Continue from Stop \(index + 1)"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stops = try await service.entries(inList: tour.id, language: language).map(\.place)
            loadFailed = false
        } catch {
            if !(error is CancellationError) { loadFailed = true }
        }
    }

    /// Starts at `index`, or picks up at the first stop not yet checked in.
    private func start(at index: Int?) {
        if index == nil, isOnThisTour {
            hunt.resume()
            return
        }
        guard !stops.isEmpty else { return }
        let start = index ?? HuntRoute.startIndex(of: stops, checkedIn: checkins.checkedInIDs)
        hunt.begin(HuntRoute(id: tour.id, title: tour.name, isTour: true, stops: stops, startingAt: start))
    }
}

/// The tour's stops joined in order, with the start green and the finish red (TourDetailScreen.tsx).
struct TourRouteMap: View {
    let stops: [Place]

    static func color(forStop index: Int, of count: Int) -> Color {
        if index == 0 { return HuntPalette.green }
        if index == count - 1 { return Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x6B / 255) }
        return Theme.gold
    }

    var body: some View {
        if let region = MKCoordinateRegion(covering: stops.map(\.coordinate)) {
            Map(initialPosition: .region(region), interactionModes: []) {
                if stops.count > 1 {
                    MapPolyline(coordinates: stops.map(\.coordinate))
                        .stroke(Theme.gold, lineWidth: 3)
                }
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Self.color(forStop: index, of: stops.count), in: .circle)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            // A new set of stops (e.g. after loading) needs a new initial position.
            .id(stops.map(\.id))
            .accessibilityLabel("Map of the tour's \(stops.count) stops")
        } else {
            Rectangle()
                .fill(Theme.surface)
                .overlay {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.textSecondary)
                }
        }
    }
}

extension MKCoordinateRegion {
    /// The smallest region showing every coordinate with 30% to spare (TourDetailScreen.tsx), or nil if there are none.
    init?(covering coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        self.init(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.005),
                                   longitudeDelta: max((maxLon - minLon) * 1.3, 0.005))
        )
    }
}
