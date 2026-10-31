//
//  VoteButtons.swift
//  Curious Places
//

import SwiftUI

/// Thumbs up and down beside the place name. Colours are the Expo app's (#4CAF50, #F44336).
struct VoteButtons: View {
    let vote: VoteType?
    let onUp: () -> Void
    let onDown: () -> Void

    private static let upColor = Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)
    private static let downColor = Color(red: 0xF4 / 255, green: 0x43 / 255, blue: 0x36 / 255)

    var body: some View {
        HStack(spacing: 4) {
            button(systemImage: "hand.thumbsup", isOn: vote == .up, color: Self.upColor,
                   label: "I like this place", action: onUp)
            button(systemImage: "hand.thumbsdown", isOn: vote == .down, color: Self.downColor,
                   label: vote == .down ? "Remove thumbs down" : "Report a problem", action: onDown)
        }
    }

    private func button(systemImage: String, isOn: Bool, color: Color, label: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? "\(systemImage).fill" : systemImage)
                .font(.title3)
                .foregroundStyle(isOn ? color : Theme.textSecondary)
                .symbolEffect(.bounce, value: isOn)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
