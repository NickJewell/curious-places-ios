//
//  TourListView.swift
//  Curious Places
//

import Observation
import SwiftUI

/// Official tours, their stop counts, and which ones the user has completed.
@Observable
final class TourCatalog {
    private(set) var tours: [Tour] = []
    private(set) var stopCounts: [UUID: Int] = [:]
    private(set) var completed: Set<UUID> = []
    private(set) var isLoading = false
    private(set) var loadFailed = false

    private let service: ListService

    init(service: ListService) {
        self.service = service
    }

    var featured: [Tour] { tours.filter(\.isPromoted) }

    func load(userID: UUID?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let tours = try await service.tours()
            // Counts need the stop policy in proposed/07; show the tours without them until then.
            stopCounts = (try? await service.stopCounts(for: tours)) ?? [:]
            self.tours = tours
            loadFailed = false
        } catch {
            if !(error is CancellationError) { loadFailed = true }
        }
        if let userID {
            // tour_completions only exists once proposed/07 is applied.
            completed = (try? await service.completedTourIDs(userID: userID)) ?? []
        } else {
            completed = []
        }
    }
}

/// Official tours: a Featured section, then the rest grouped by start region (ListsScreen.tsx).
struct TourListView: View {
    let catalog: TourCatalog
    let reload: () async -> Void

    var body: some View {
        List {
            if !catalog.featured.isEmpty {
                Section {
                    ForEach(catalog.featured) { tour in
                        row(tour, isFeatured: true)
                    }
                } header: {
                    Label("Featured Tours", systemImage: "star.fill")
                        .sectionTitleStyle()
                        .foregroundStyle(Theme.gold)
                }
                .listRowBackground(Theme.surface)
            }
            ForEach(Tour.grouped(catalog.tours), id: \.region) { group in
                Section {
                    ForEach(group.tours) { tour in
                        row(tour, isFeatured: false)
                    }
                } header: {
                    Text(group.region).sectionTitleStyle()
                }
                .listRowBackground(Theme.surface)
            }
        }
        .themedList()
        .overlay {
            if catalog.tours.isEmpty {
                if catalog.isLoading {
                    ProgressView()
                } else if catalog.loadFailed {
                    ContentUnavailableView {
                        Label("Couldn't load tours", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Retry") { Task { await reload() } }
                    }
                } else {
                    ContentUnavailableView(
                        "No Tours Available",
                        systemImage: "map",
                        description: Text("Official curated tours will appear here. Check back soon!")
                    )
                }
            }
        }
        .refreshable { await reload() }
    }

    private func row(_ tour: Tour, isFeatured: Bool) -> some View {
        NavigationLink(value: tour) {
            TourRow(tour: tour, stopCount: catalog.stopCounts[tour.id],
                    isCompleted: catalog.completed.contains(tour.id), isFeatured: isFeatured)
        }
    }
}

struct TourRow: View {
    let tour: Tour
    let stopCount: Int?
    let isCompleted: Bool
    let isFeatured: Bool

    var body: some View {
        HStack(spacing: 12) {
            // The stop count gives each tour its own tile; the stats repeat it for VoiceOver.
            VStack(spacing: 0) {
                if let stopCount {
                    Text("\(stopCount)")
                        .font(.title3.bold())
                        .fontDesign(.rounded)
                        .monospacedDigit()
                    Text(stopCount == 1 ? "stop" : "stops")
                        .font(.caption2)
                } else {
                    Image(systemName: isFeatured ? "star.fill" : "map")
                        .font(.title3)
                }
            }
            .foregroundStyle(Theme.gold)
            .frame(width: 48, height: 48)
            .background(Theme.gold.opacity(isFeatured ? 0.2 : 0.12), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(tour.name)
                    .font(.headline)
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                TourStats(tour: tour, stopCount: stopCount)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isCompleted {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(Theme.gold)
                    .accessibilityLabel("Completed")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Duration, length and stop count, each shown only when known.
struct TourStats: View {
    let tour: Tour
    let stopCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let duration = tour.duration, !duration.isEmpty {
                Label(duration, systemImage: "clock")
            }
            if let category = tour.lengthCategory, !category.isEmpty {
                Label(category, systemImage: "figure.walk")
            }
            if let stopCount {
                Label(stopCount == 1 ? "1 stop" : "\(stopCount) stops", systemImage: "mappin")
            }
        }
        .labelStyle(TightLabelStyle())
        .foregroundStyle(Theme.textSecondary)
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
