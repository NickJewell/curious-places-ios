//
//  NarrationPlayer.swift
//  Curious Places
//

import AVFoundation
import Observation

/// Streams one narration track with play/pause and scrubbing.
@Observable
final class NarrationPlayer {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    private(set) var state: State = .idle
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: Task<Void, Never>?

    var progress: Double {
        duration > 0 ? min(currentTime / duration, 1) : 0
    }

    func load(_ url: URL, autoplay: Bool) async {
        stop()
        state = .loading
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        do {
            let seconds = try await item.asset.load(.duration).seconds
            guard player.currentItem === item else { return }
            duration = seconds.isFinite ? seconds : 0
            state = .ready
            observe(item)
            if autoplay { play() }
        } catch {
            guard player.currentItem === item else { return }
            state = .failed
        }
    }

    func play() {
        guard state == .ready else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        if duration > 0, currentTime >= duration - 0.5 { seek(to: 0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Seeks to a fraction (0–1) of the track.
    func seek(toProgress fraction: Double) {
        seek(to: fraction * duration)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        endObserver?.cancel()
        endObserver = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        state = .idle
    }

    /// Stops and hands the audio session back to other apps. Call only when no other
    /// player on screen needs the session (the place page has two: narration and facts).
    func release() {
        stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    private func observe(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
        endObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item) {
                self?.isPlaying = false
            }
        }
    }
}
