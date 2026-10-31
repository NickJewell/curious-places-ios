//
//  NarrationView.swift
//  Curious Places
//

import SwiftUI

/// Finds a place's narration and plays it, starting automatically as the Expo app did.
/// When the narration for the description's language is missing, asks the Edge Function
/// to generate it (playing the English "loading" clip meanwhile) and falls back to any
/// other narration if that fails. Shows nothing when the place has no audio at all.
struct NarrationView: View {
    let place: Place
    let player: NarrationPlayer

    private enum Phase: Equatable {
        case searching
        case preparing
        case ready(NarrationTrack)
        case unavailable
    }

    @Environment(NarrationService.self) private var service
    @State private var phase = Phase.searching
    @State private var scrubPosition: Double?

    var body: some View {
        Group {
            switch phase {
            case .searching:
                status("Finding narration…")
            case .preparing:
                status("Preparing narration…")
            case .ready(let track):
                controls(for: track)
            case .unavailable:
                EmptyView()
            }
        }
        .task(id: place.id) { await start() }
    }

    private func start() async {
        phase = .searching
        let found = await service.track(for: place.id, language: place.language)
        if Task.isCancelled { return }

        let wanted = place.overviewLanguage
        if found?.language != wanted, !place.overviewText.isEmpty {
            phase = .preparing
            if let generated = await generate(wanted) {
                await play(generated)
                return
            }
            if Task.isCancelled { return }
        }

        if let found {
            await play(found)
        } else {
            player.stop()
            phase = .unavailable
        }
    }

    /// One request to the Edge Function, then polling for the file. Nil if the function
    /// isn't deployed, fails, or the file doesn't appear in time.
    private func generate(_ language: AppLanguage) async -> NarrationTrack? {
        guard let result = try? await service.requestGeneration(for: place.id, language: language) else { return nil }
        switch result {
        case .ready(let track):
            return track
        case .generating(let track, let loadingClip):
            if let loadingClip {
                await player.load(loadingClip, autoplay: true)
            }
            return await service.waitUntilAvailable(track, curioID: place.id) ? track : nil
        }
    }

    private func play(_ track: NarrationTrack) async {
        phase = .ready(track)
        await player.load(track.url, autoplay: true)
    }

    private func status(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.textSecondary)
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
