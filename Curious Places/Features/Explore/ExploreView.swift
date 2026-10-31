//
//  ExploreView.swift
//  Curious Places
//

import MapKit
import SwiftUI

struct ExploreView: View {
    @Environment(LocationProvider.self) private var location
    @Environment(HuntStore.self) private var hunt
    @Environment(CheckinStore.self) private var checkins
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.deviceDefault()
    @State private var model: ExploreModel
    @State private var position: MapCameraPosition = .userLocation(fallback: .region(.london))
    @State private var detailPlace: Place?
    /// Set when "Navigate Here" is tapped in the detail sheet; the hunt starts once it closes.
    @State private var pendingHunt: Place?

    init(service: PlaceService) {
        _model = State(initialValue: ExploreModel(service: service))
    }

    var body: some View {
        Map(position: $position, selection: selection) {
            UserAnnotation()
            ForEach(markerPlaces) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                    PlaceMarker(category: place.category, state: markerState(for: place))
                }
                .annotationTitles(.hidden)
                .tag(place.id)
            }
            // The target stays on the map even when it's outside the loaded area.
            if let target = hunt.target {
                Annotation(target.name, coordinate: target.coordinate, anchor: .center) {
                    PlaceMarker(category: target.category, state: .target)
                        .onTapGesture { hunt.resume() }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            model.regionDidChange(context.region, language: language)
        }
        .onChange(of: language) {
            model.reload(language: language)
        }
        .safeAreaInset(edge: .top) {
            ExploreHeader(model: model, language: language, showsFilters: !hunt.isHunting)
        }
        .safeAreaInset(edge: .bottom) {
            if hunt.isHunting {
                ResumeCompassButton(action: hunt.resume)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let place = model.selectedPlace {
                PlacePanel(
                    place: place,
                    distance: location.distance(to: place.coordinate),
                    isVisited: checkins.isCheckedIn(place.id),
                    onRead: { detailPlace = place },
                    onHunt: { startHunt(place) },
                    onClose: { model.select(id: nil) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.selectedPlace?.id)
        .animation(.snappy, value: hunt.isHunting)
        .sheet(item: $detailPlace, onDismiss: {
            if let place = pendingHunt {
                pendingHunt = nil
                startHunt(place)
            }
        }) { place in
            PlaceDetailView(place: place) {
                pendingHunt = place
                detailPlace = nil
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedPlace?.id },
            set: { id in
                // As in the Expo map, the place panel stays closed during a hunt.
                if !hunt.isHunting { model.select(id: id) }
            }
        )
    }

    private var markerPlaces: [Place] {
        model.visiblePlaces.filter { $0.id != hunt.target?.id }
    }

    private func markerState(for place: Place) -> MarkerState {
        if checkins.isCheckedIn(place.id) { return .visited }
        if hunt.isHunting { return .dimmed }
        return place.id == model.selectedPlace?.id ? .selected : .ambient
    }

    /// Shows the user and the target together, then opens the compass (MapScreen.tsx:352-368).
    private func startHunt(_ place: Place) {
        model.select(id: nil)
        hunt.begin(place)
        if let user = location.location?.coordinate {
            withAnimation { position = .region(MKCoordinateRegion(fitting: user, place.coordinate)) }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if hunt.target?.id == place.id { hunt.resume() }
        }
    }
}

private struct ResumeCompassButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Resume Compass", systemImage: "location.north.line.fill")
                .font(.headline)
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: .capsule)
                .overlay(Capsule().stroke(Theme.gold.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }
}

/// Filter chips, plus the loading, error and "zoom in" states.
private struct ExploreHeader: View {
    let model: ExploreModel
    let language: AppLanguage
    let showsFilters: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if showsFilters {
                    ForEach(PlaceFilter.allCases) { filter in
                        FilterChip(filter: filter, isSelected: model.filter == filter) {
                            model.filter = filter
                        }
                    }
                }
                Spacer(minLength: 0)
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if model.loadFailed {
                StatusBanner(text: "Couldn't load places.", systemImage: "wifi.exclamationmark") {
                    Button("Retry") { model.reload(language: language) }
                        .font(.subheadline.weight(.semibold))
                }
            } else if model.tooManyPlaces {
                StatusBanner(text: "Zoom in to see places", systemImage: "plus.magnifyingglass")
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

private struct FilterChip: View {
    let filter: PlaceFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(filter.label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Theme.backgroundRoot : Theme.textPrimary)
                .background {
                    Capsule().fill(isSelected ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(.regularMaterial))
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct StatusBanner<Accessory: View>: View {
    let text: String
    let systemImage: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Label(text, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }
}

extension StatusBanner where Accessory == EmptyView {
    init(text: String, systemImage: String) {
        self.init(text: text, systemImage: systemImage) { EmptyView() }
    }
}
