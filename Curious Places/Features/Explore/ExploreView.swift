//
//  ExploreView.swift
//  Curious Places
//

import MapKit
import SwiftUI

struct ExploreView: View {
    @Environment(LocationProvider.self) private var location
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.deviceDefault()
    @State private var model: ExploreModel
    @State private var position: MapCameraPosition = .userLocation(fallback: .region(.london))
    @State private var detailPlace: Place?

    init(service: PlaceService) {
        _model = State(initialValue: ExploreModel(service: service))
    }

    var body: some View {
        Map(position: $position, selection: selection) {
            UserAnnotation()
            ForEach(model.visiblePlaces) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                    PlaceMarker(category: place.category, isSelected: place.id == model.selectedPlace?.id)
                }
                .annotationTitles(.hidden)
                .tag(place.id)
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
            ExploreHeader(model: model, language: language)
        }
        .safeAreaInset(edge: .bottom) {
            if let place = model.selectedPlace {
                PlacePanel(
                    place: place,
                    distance: location.distance(to: place.coordinate),
                    onRead: { detailPlace = place },
                    onClose: { model.select(id: nil) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.selectedPlace?.id)
        .sheet(item: $detailPlace) { place in
            PlaceDetailView(place: place)
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedPlace?.id },
            set: { model.select(id: $0) }
        )
    }
}

/// Filter chips, plus the loading, error and "zoom in" states.
private struct ExploreHeader: View {
    let model: ExploreModel
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(PlaceFilter.allCases) { filter in
                    FilterChip(filter: filter, isSelected: model.filter == filter) {
                        model.filter = filter
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
