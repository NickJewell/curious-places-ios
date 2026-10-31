//
//  PlacePanel.swift
//  Curious Places
//

import CoreLocation
import SwiftUI

/// The card shown above the tab bar when a marker is selected.
struct PlacePanel: View {
    let place: Place
    let distance: CLLocationDistance?
    let isVisited: Bool
    let onRead: () -> Void
    let onHunt: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CategoryBadge(category: place.category)
                if let distance {
                    Label(distance.formattedDistance, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if isVisited {
                    VisitedBadge()
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text(place.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            Button(action: onRead) {
                VStack(alignment: .leading, spacing: 4) {
                    if !place.overviewText.isEmpty {
                        OverviewText(place: place)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Text("Read more")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            HuntButton(action: onHunt)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct CategoryBadge: View {
    let category: PlaceCategory

    var body: some View {
        Label(category.label, systemImage: category.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(category.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(category.color.opacity(0.15), in: .capsule)
            .overlay(Capsule().stroke(category.color.opacity(0.4)))
    }
}

/// Starts a compass hunt for a place (the Expo map's "Hunt" and detail page's "Navigate Here").
struct HuntButton: View {
    var title = "Hunt"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "location.north.line.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Theme.gold)
        .foregroundStyle(Theme.backgroundRoot)
    }
}

struct VisitedBadge: View {
    var body: some View {
        Label("Visited", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.gold)
    }
}

/// A place's description, laid out right-to-left when it's an Arabic translation.
struct OverviewText: View {
    let place: Place

    var body: some View {
        Text(place.overviewText)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
    }

    private var isRightToLeft: Bool {
        place.isShowingTranslation && place.language.isRightToLeft
    }
}

extension CLLocationDistance {
    var formattedDistance: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
