//
//  PlaceMarker.swift
//  Curious Places
//

import SwiftUI

/// Map marker: a small category-coloured disc, enlarged with a glow when selected
/// (the "ambient" and "selected" tiers from the Expo map).
struct PlaceMarker: View {
    let category: PlaceCategory
    let isSelected: Bool

    var body: some View {
        let size: CGFloat = isSelected ? 38 : 26
        Image(systemName: category.systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color, in: .circle)
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: isSelected ? 2.5 : 1.5))
            .shadow(color: isSelected ? Theme.gold.opacity(0.8) : .black.opacity(0.3), radius: isSelected ? 8 : 2)
            .animation(.snappy, value: isSelected)
            .accessibilityLabel(category.label)
    }
}
