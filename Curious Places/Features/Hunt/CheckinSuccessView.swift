//
//  CheckinSuccessView.swift
//  Curious Places
//

import SwiftUI

/// Shown after a new check-in. Based on the Expo CheckinSuccessModal, but lists
/// only what really happened: the Expo version also awarded "points" that were
/// never stored anywhere.
struct CheckinSuccessView: View {
    let placeName: String
    let outcome: CheckinOutcome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("First discovery")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 48)
            Text(placeName)
                .font(.title.weight(.heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 32)

            ScrollView {
                VStack(spacing: 0) {
                    let lines = CheckinCelebration.lines(placeName: placeName, outcome: outcome)
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        if index > 0 { Divider().overlay(.white.opacity(0.1)) }
                        HStack(spacing: 12) {
                            Image(systemName: line.systemImage)
                                .font(.subheadline)
                                .foregroundStyle(Theme.gold)
                                .frame(width: 34, height: 34)
                                .background(Theme.gold.opacity(0.12), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                if let detail = line.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                    }
                }
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1)))
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("Continue") { dismiss() }
                .font(.headline)
                .foregroundStyle(Color(red: 0x0D / 255, green: 0x0B / 255, blue: 0x18 / 255))
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white, in: .capsule)
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 24)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0x0D / 255, green: 0x0B / 255, blue: 0x18 / 255),
                    Color(red: 0x13 / 255, green: 0x10 / 255, blue: 0x2A / 255),
                    Color(red: 0x0A / 255, green: 0x0E / 255, blue: 0x14 / 255),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .presentationDragIndicator(.visible)
    }
}

/// The rows of the check-in celebration.
nonisolated enum CheckinCelebration {
    struct Line: Equatable {
        let systemImage: String
        let title: String
        var detail: String?
    }

    static func lines(placeName: String, outcome: CheckinOutcome) -> [Line] {
        var lines = [Line(systemImage: "star.fill", title: "First discovery of \(placeName)! The mystery unfolds.")]
        lines.append(Line(systemImage: outcome.totalCheckins == 1 ? "mappin" : "rosette",
                          title: milestone(outcome.totalCheckins)))
        for badge in outcome.newBadges {
            lines.append(Line(systemImage: badge.systemImage, title: "Badge unlocked: \(badge.name)!",
                              detail: badge.description))
        }
        return lines
    }

    /// The Expo copy for 1, 5, 10, 25 and every tenth check-in; a plain count otherwise.
    static func milestone(_ total: Int) -> String {
        switch total {
        case 1: "Your very first curio discovered!"
        case 5: "5 curios discovered — you're on a roll."
        case 10: "10 curios! A seasoned explorer emerges."
        case 25: "25 curios discovered. A true Curio master."
        case let n where n % 10 == 0: "\(n) total discoveries — remarkable."
        default: "\(total) places visited so far."
        }
    }
}
