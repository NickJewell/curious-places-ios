//
//  PlaceMarker.swift
//  Curious Places
//

import SwiftUI

/// The Expo map's marker tiers, plus selection.
enum MarkerState: Equatable {
    /// A category-coloured disc.
    case ambient
    case selected
    /// The place being hunted: large and gold.
    case target
    /// Already checked in: dark with a gold tick.
    case visited
    /// Any other place while a hunt is on.
    case dimmed
}

struct PlaceMarker: View {
    let category: PlaceCategory
    let state: MarkerState

    var body: some View {
        Image(systemName: state == .visited ? "checkmark" : category.systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            // Only selection and check-ins bounce, not every marker dimming when a hunt starts.
            .symbolEffect(.bounce, value: state == .selected || state == .visited)
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: .circle)
            .overlay(Circle().stroke(stroke, lineWidth: strokeWidth))
            .shadow(color: shadow, radius: shadowRadius)
            .opacity(state == .dimmed ? 0.5 : 1)
            .animation(.snappy, value: state)
            .accessibilityLabel(state == .visited ? "\(category.label), visited" : category.label)
    }

    private var size: CGFloat {
        switch state {
        case .target: 44
        case .selected: 38
        case .visited: 30
        case .ambient, .dimmed: 26
        }
    }

    private var background: Color {
        switch state {
        case .ambient, .selected: category.color
        case .target: Theme.gold
        case .visited: Self.visitedFill
        case .dimmed: Self.dimmedFill
        }
    }

    /// The background colour on the disc, as on the gold buttons: category discs are dark in
    /// light mode and light in dark mode, so white would fail contrast in one of them.
    private var foreground: Color {
        switch state {
        case .visited: Self.visitedGold
        case .dimmed: .white.opacity(0.75)
        default: Theme.backgroundRoot
        }
    }

    private var stroke: Color {
        switch state {
        case .visited: Self.visitedGold
        case .dimmed: .clear
        default: .white.opacity(0.9)
        }
    }

    private var strokeWidth: CGFloat {
        switch state {
        case .target: 3
        case .selected: 2.5
        case .visited: 2
        default: 1.5
        }
    }

    private var shadow: Color {
        switch state {
        case .target, .selected: Theme.gold.opacity(0.8)
        case .visited: Self.visitedGold.opacity(0.4)
        default: .black.opacity(0.3)
        }
    }

    private var shadowRadius: CGFloat {
        switch state {
        case .target: 12
        case .selected: 8
        case .visited: 6
        default: 2
        }
    }

    private static let visitedFill = Color(red: 0x2A / 255, green: 0x25 / 255, blue: 0x20 / 255)
    private static let visitedGold = Color(red: 0xD4 / 255, green: 0xAF / 255, blue: 0x37 / 255)
    private static let dimmedFill = Color(red: 0x3A / 255, green: 0x3D / 255, blue: 0x44 / 255)
}
