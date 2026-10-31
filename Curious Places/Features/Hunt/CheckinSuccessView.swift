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
    /// The tour this check-in finished, if any.
    var completedTour: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set on appear, so the rows come in one after another.
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            Text("First discovery")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 48)
            Text(placeName)
                .font(.title.weight(.bold))
                .fontDesign(.serif)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 32)

            ScrollView {
                VStack(spacing: 0) {
                    let lines = CheckinCelebration.lines(placeName: placeName, outcome: outcome,
                                                         completedTour: completedTour)
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
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed || reduceMotion ? 0 : 12)
                        .animation(reduceMotion ? nil : .snappy.delay(Double(index) * 0.12), value: revealed)
                        .accessibilityElement(children: .combine)
                    }
                }
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1)))
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("Continue") { dismiss() }
                .font(.headline)
                .foregroundStyle(Theme.backgroundRoot)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white, in: .capsule)
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 24)
        .background {
            // The app's navy, with a gold glow from the top.
            ZStack {
                LinearGradient(colors: [Theme.backgroundRoot, Theme.surface], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.gold.opacity(0.18), .clear], center: .top,
                               startRadius: 0, endRadius: 320)
            }
            .ignoresSafeArea()
        }
        // Always dark, like the hunt; this only changes how the theme colours resolve here.
        .environment(\.colorScheme, .dark)
        .presentationDragIndicator(.visible)
        .onAppear { revealed = true }
    }
}

/// The rows of the check-in celebration.
nonisolated enum CheckinCelebration {
    struct Line: Equatable {
        let systemImage: String
        let title: String
        var detail: String?
    }

    static func lines(placeName: String, outcome: CheckinOutcome, completedTour: String? = nil) -> [Line] {
        var lines = [Line(systemImage: "star.fill", title: "First discovery of \(placeName)! The mystery unfolds.")]
        lines.append(Line(systemImage: outcome.totalCheckins == 1 ? "mappin" : "rosette",
                          title: milestone(outcome.totalCheckins)))
        if let completedTour {
            lines.append(Line(systemImage: "flag.checkered", title: "Tour complete: \(completedTour)!",
                              detail: "You've checked in at every stop."))
        }
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
