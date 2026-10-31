//
//  ExploreModel.swift
//  Curious Places
//

import MapKit
import Observation

enum PlaceFilter: String, CaseIterable, Identifiable {
    case all, open, landmarks, built

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .open: "Open"
        case .landmarks: "Landmarks"
        case .built: "Built"
        }
    }

    func includes(_ place: Place) -> Bool {
        switch self {
        case .all: true
        case .open: place.category == .open
        case .landmarks: place.category == .landmark
        case .built: place.category == .built
        }
    }
}

/// Loads places for the visible map area. Behaviour follows the Expo MapScreen:
/// fetch the viewport plus a 30% buffer, debounce 350 ms, ignore stale responses,
/// and hide markers behind a "zoom in" prompt when more than 150 are in view.
@Observable
final class ExploreModel {
    static let tooManyThreshold = 150
    static let buffer = 0.3
    static let debounce: Duration = .milliseconds(350)

    var filter: PlaceFilter = .all
    private(set) var isLoading = false
    private(set) var tooManyPlaces = false
    private(set) var loadFailed = false
    private(set) var selectedPlace: Place?

    private let service: PlaceService
    private var fetched: [Place] = []
    private var fetchedBox: BoundingBox?
    private var fetchedLanguage: AppLanguage?
    private var fetchedSpan: Double = 0
    private var lastRegion: MKCoordinateRegion?
    private var pendingFetch: Task<Void, Never>?
    private var generation = 0

    init(service: PlaceService) {
        self.service = service
    }

    /// Markers to show: everything fetched, filtered, unless there are too many in view.
    var visiblePlaces: [Place] {
        tooManyPlaces ? [] : fetched.filter(filter.includes)
    }

    func select(id: String?) {
        selectedPlace = id.flatMap { id in fetched.first { $0.id == id } }
    }

    func regionDidChange(_ region: MKCoordinateRegion, language: AppLanguage) {
        lastRegion = region
        if needsFetch(for: region, language: language) {
            scheduleFetch(region: region, language: language, after: Self.debounce)
        } else {
            updateTooMany(for: region)
        }
    }

    /// Refetch the last region immediately, e.g. after the language changes or a retry.
    func reload(language: AppLanguage) {
        guard let lastRegion else { return }
        scheduleFetch(region: lastRegion, language: language, after: .zero)
    }

    private func needsFetch(for region: MKCoordinateRegion, language: AppLanguage) -> Bool {
        guard let fetchedBox, fetchedLanguage == language, !loadFailed else { return true }
        if !fetchedBox.contains(BoundingBox(region: region)) { return true }
        // A capped result is incomplete, so zooming well into it should fetch the denser detail.
        let wasCapped = fetched.count >= PlaceService.viewportLimit
        return wasCapped && region.span.latitudeDelta < fetchedSpan * 0.5
    }

    private func scheduleFetch(region: MKCoordinateRegion, language: AppLanguage, after delay: Duration) {
        pendingFetch?.cancel()
        generation += 1
        let generation = generation
        pendingFetch = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            await fetch(region: region, language: language, generation: generation)
        }
    }

    private func fetch(region: MKCoordinateRegion, language: AppLanguage, generation: Int) async {
        isLoading = true
        let box = BoundingBox(region: region, buffer: Self.buffer)
        do {
            let places = try await service.places(in: box, language: language)
            guard generation == self.generation else { return }
            fetched = places
            fetchedBox = box
            fetchedLanguage = language
            fetchedSpan = region.span.latitudeDelta
            loadFailed = false
            if let selected = selectedPlace {
                // Keep the panel open, refreshed in the new language if the place is still loaded.
                selectedPlace = places.first { $0.id == selected.id } ?? selected
            }
            updateTooMany(for: lastRegion ?? region)
        } catch {
            guard generation == self.generation, !(error is CancellationError) else { return }
            loadFailed = true
        }
        isLoading = false
    }

    private func updateTooMany(for region: MKCoordinateRegion) {
        let visible = BoundingBox(region: region)
        let inView = fetched.lazy.filter { visible.contains(latitude: $0.latitude, longitude: $0.longitude) }.count
        tooManyPlaces = inView > Self.tooManyThreshold
    }
}

extension MKCoordinateRegion {
    /// Central London, where the content is. Used until the user's location is known.
    static let london = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
}
