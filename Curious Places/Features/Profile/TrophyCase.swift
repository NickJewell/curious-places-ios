//
//  TrophyCase.swift
//  Curious Places
//

import SwiftUI

/// Every badge, earned ones lit in gold (the Expo profile's trophy case).
struct TrophyCase: View {
    let badges: [Badge]
    let isEarned: (Badge) -> Bool
    let onSelect: (Badge) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 3), spacing: 16) {
            ForEach(badges) { badge in
                Button { onSelect(badge) } label: {
                    BadgeTile(badge: badge, isEarned: isEarned(badge))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct BadgeTile: View {
    let badge: Badge
    let isEarned: Bool

    var body: some View {
        VStack(spacing: 6) {
            BadgeIcon(badge: badge, isEarned: isEarned, size: 56)
            Text(badge.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(isEarned ? Theme.textPrimary : Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .opacity(isEarned ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isEarned ? "Earned" : "Not earned yet")
    }
}

struct BadgeIcon: View {
    let badge: Badge
    let isEarned: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: badge.systemImage)
            .font(.system(size: size * 0.42))
            .foregroundStyle(isEarned ? Theme.gold : Theme.textSecondary)
            .frame(width: size, height: size)
            .background(isEarned ? Theme.gold.opacity(0.15) : Theme.surfaceSecondary, in: .circle)
            .overlay(Circle().stroke(isEarned ? Theme.gold.opacity(0.6) : Theme.border))
            .accessibilityHidden(true)
    }
}

struct BadgeDetailView: View {
    let badge: Badge
    let earned: EarnedBadge?

    var body: some View {
        VStack(spacing: 12) {
            BadgeIcon(badge: badge, isEarned: earned != nil, size: 88)
            Text(badge.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(badge.description)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Group {
                if let earned {
                    if let date = earned.earnedAt {
                        Label("Earned \(date.formatted(date: .long, time: .omitted))", systemImage: "checkmark.seal.fill")
                    } else {
                        Label("Earned", systemImage: "checkmark.seal.fill")
                    }
                } else {
                    Label("Not earned yet", systemImage: "lock.fill")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(earned != nil ? Theme.gold : Theme.textSecondary)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundRoot)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
