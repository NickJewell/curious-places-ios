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

    var color: Color {
        switch self {
        case .open: Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)
        case .landmark: Color(red: 0x6D / 255, green: 0x4C / 255, blue: 0x8E / 255)
        case .built: Color(red: 0x54 / 255, green: 0x6E / 255, blue: 0x7A / 255)
        case .other: Theme.bronze
        }
    }
}
