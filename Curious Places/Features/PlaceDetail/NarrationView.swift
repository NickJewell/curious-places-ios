//
//  NarrationView.swift
//  Curious Places
//

import SwiftUI

/// Finds a place's narration and plays it, starting automatically as the Expo app did.
/// Shows nothing when the place has no audio.
struct NarrationView: View {
    let place: Place

    @Environment(NarrationService.self) private var service
    @State private var player = NarrationPlayer()
    @State private var track: NarrationTrack?
    @State private var isSearching = true
    @State private var scrubPosition: Double?

    var body: some View {
        Group {
            if isSearching {
                Label("Finding narration…", systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else if let track {
                controls(for: track)
            }
        }
        .task(id: place.id) {
            isSearching = true
            track = await service.track(for: place.id, language: place.language)
            isSearching = false
            if let track {
                await player.load(track.url, autoplay: true)
            }
        }
        .onDisappear { player.stop() }
    }

    private func controls(for track: NarrationTrack) -> some View {
        HStack(spacing: 14) {
            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.backgroundRoot)
                    .frame(width: 48, height: 48)
                    .background(Theme.gold, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(player.state != .ready)
            .accessibilityLabel(player.isPlaying ? "Pause narration" : "Play narration")

            VStack(alignment: .leading, spacing: 4) {
                switch player.state {
                case .failed:
                    Text("Couldn't play the narration.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                case .loading, .idle:
                    ProgressView().controlSize(.small)
                case .ready:
                    Slider(
                        value: Binding(
                            get: { scrubPosition ?? player.progress },
                            set: { scrubPosition = $0 }
                        ),
                        onEditingChanged: { editing in
                            if !editing, let position = scrubPosition {
                                player.seek(toProgress: position)
                                scrubPosition = nil
                            }
                        }
                    )
                    .tint(Theme.gold)
                    .accessibilityLabel("Narration position")

                    HStack {
                        Text(timestamp(player.currentTime))
                        Spacer()
                        if track.language != place.language {
                            Text("\(track.language.displayName) narration")
                        }
                        Spacer()
                        Text(timestamp(player.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }

    private func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
