//
//  PlaceDetailView.swift
//  Curious Places
//

import MapKit
import SwiftUI

/// Place detail with narration. Facts, votes and reporting come in milestone 3.
struct PlaceDetailView: View {
    let place: Place
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: place.coordinate, latitudinalMeters: 400, longitudinalMeters: 400
                    )), interactionModes: []) {
                        Marker(place.name, systemImage: place.category.systemImage, coordinate: place.coordinate)
                            .tint(place.category.color)
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .frame(height: 200)
                    .clipShape(.rect(cornerRadius: 18))

                    HStack(spacing: 8) {
                        CategoryBadge(category: place.category)
                        if let distance = location.distance(to: place.coordinate) {
                            Label(distance.formattedDistance, systemImage: "location.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Text(place.name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)

                    NarrationView(place: place)

                    if place.overviewText.isEmpty {
                        Text("There's no description for this place yet.")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        if place.language != .english && !place.isShowingTranslation {
                            Label("Not yet translated into \(place.language.displayName). Showing English.",
                                  systemImage: "globe")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        OverviewText(place: place)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .background(Theme.backgroundRoot)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
