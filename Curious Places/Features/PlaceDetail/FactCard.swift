//
//  FactCard.swift
//  Curious Places
//

import SwiftUI

/// "Did you know?": tap for a random fact, without repeats until all have been seen.
/// English facts are read aloud (voice Clive) as they appear, as in the Expo app.
/// Facts are shown in the description language when there are any, otherwise in English.
struct FactCard: View {
    let place: Place
    let player: NarrationPlayer
    let onReport: (Fact) -> Void

    @Environment(NarrationService.self) private var narration
    @State private var deck = FactDeck([])
    @State private var current: Fact?
    @State private var isLoading = true
    @State private var isFindingAudio = false
    private let service = FactService(client: supabase)

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(14)
            } else if deck.isEmpty {
                Label("No facts for this place yet", systemImage: "bolt")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.surface, in: .rect(cornerRadius: 18))
            } else if let current {
                factView(current)
            } else {
                Button(action: showNext) {
                    Label("Did you know? Tap for a fact", systemImage: "bolt.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(Theme.surface, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current?.id)
        .task(id: place.id) {
            isLoading = true
            current = nil
            let facts = (try? await service.facts(for: place.id)) ?? []
            deck = FactDeck(Fact.displayed(facts, in: place.language))
            isLoading = false
        }
        .task(id: current?.id) {
            guard let current, current.hasAudio else { return }
            isFindingAudio = true
            let url = await narration.factAudio(for: current)
            isFindingAudio = false
            guard !Task.isCancelled, let url else { return }
            await player.load(url, autoplay: true)
        }
    }

    private func factView(_ fact: Fact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label("Did you know?", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
                Spacer(minLength: 0)
                if fact.hasAudio {
                    audioButton
                }
                Button { onReport(fact) } label: {
                    Image(systemName: "flag")
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Report this fact")
            }

            Button(action: showNext) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(fact.text)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, fact.language.isRightToLeft ? .rightToLeft : .leftToRight)
                    Text("Tap for another fact")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows another fact")
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
        .id(fact.id)
        .transition(.opacity)
    }

    @ViewBuilder
    private var audioButton: some View {
        if isFindingAudio || player.state == .loading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 32, height: 32)
        } else if player.state == .ready {
            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.gold)
            .accessibilityLabel(player.isPlaying ? "Pause fact" : "Play fact")
        }
    }

    private func showNext() {
        player.stop()
        current = deck.next()
    }
}
