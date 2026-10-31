//
//  Theme.swift
//  Curious Places
//

import SwiftUI

/// Colour tokens ported from the Expo app's `client/constants/theme.ts`.
/// Each has light and dark variants in the asset catalog.
enum Theme {
    static let backgroundRoot = Color("BackgroundRoot")
    static let surface = Color("Surface")
    static let surfaceSecondary = Color("SurfaceSecondary")
    static let border = Color("Border")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let gold = Color.accentColor
    static let bronze = Color("Bronze")
}

extension View {
    /// Puts a `List` or `Form` on the app background instead of the system grouped grey.
    /// Rows take `Theme.surface` through `.listRowBackground`.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.backgroundRoot)
    }

    /// List section headers in small caps, echoing the hunt's tracked-caps labels.
    func sectionTitleStyle() -> some View {
        font(.subheadline.smallCaps())
            .textCase(nil)
    }
}

/// Light / dark / system, chosen in Profile (the Expo app's theme picker).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension PlaceCategory {
    var label: String {
        switch self {
        case .open: "Open space"
        case .landmark: "Landmark"
        case .built: "Built"
        case .other: "Place"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "leaf.fill"
        case .landmark: "building.columns.fill"
        case .built: "building.2.fill"
        case .other: "mappin"
        }
    }

    /// Not the Expo values (#4CAF50, #6D4C8E, #546E7A, bronze), which were the same in both
    /// modes and fell below 4.5:1 as badge text in one or the other. These are darker in light
    /// mode and lighter in dark mode, and pass in both (docs/design/ui-audit-2026-10-31.md #3).
    var color: Color {
        switch self {
        case .open: Color("CategoryOpen")
        case .landmark: Color("CategoryLandmark")
        case .built: Color("CategoryBuilt")
        case .other: Color("CategoryOther")
        }
    }
}
