//
//  NarrationService.swift
//  Curious Places
//

import Foundation
import Observation

/// A narration file the app can stream.
nonisolated struct NarrationTrack: Equatable, Sendable {
    let url: URL
    /// The language actually spoken, which may differ from the one asked for.
    let language: AppLanguage
}

/// Where a place's narration may be stored, in the order to try.
/// Paths match the Expo server: `routes.ts:244-326` (current) and
/// `server_dist/index.js:94-105` (legacy pre-generated audio).
nonisolated enum NarrationLocator {
    static func candidates(curioID: String, language: AppLanguage, baseURL: URL) -> [NarrationTrack] {
        guard let number = curioNumber(curioID) else { return [] }
        var tracks: [NarrationTrack] = []
        if language != .english {
            tracks.append(track(bucket: "\(language.rawValue)_audio",
                                path: "\(language.rawValue)_curio_\(number)_detail_overview.mp3",
                                language: language, baseURL: baseURL))
        }
        tracks.append(track(bucket: "en_audio", path: "en_curio_\(number)_detail_overview.mp3",
                            language: .english, baseURL: baseURL))
        let legacy = legacyLocation(number: number)
        tracks.append(track(bucket: legacy.bucket, path: legacy.path, language: .english, baseURL: baseURL))
        return tracks
    }

    /// The trailing number of a curio ID ("CURIO-41" → 41), as the server parses it.
    static func curioNumber(_ curioID: String) -> Int? {
        guard let range = curioID.range(of: #"\d+$"#, options: .regularExpression) else { return nil }
        return Int(curioID[range])
    }

    /// 1,000 places per bucket, 100 per folder: CURIO-41 → audio_overviews_1_1000/1-100/curio_detail_41.mp3
    static func legacyLocation(number: Int) -> (bucket: String, path: String) {
        let bucketStart = (number - 1) / 1000 * 1000 + 1
        let folderStart = (number - 1) / 100 * 100 + 1
        return ("audio_overviews_\(bucketStart)_\(bucketStart + 999)",
                "\(folderStart)-\(folderStart + 99)/curio_detail_\(number).mp3")
    }

    private static func track(bucket: String, path: String, language: AppLanguage, baseURL: URL) -> NarrationTrack {
        let url = baseURL.appending(path: "storage/v1/object/public/\(bucket)/\(path)")
        return NarrationTrack(url: url, language: language)
    }
}

/// Finds which narration file exists for a place. Needs the audio buckets to be
/// public (supabase/proposed/04_public_audio_buckets.sql).
@Observable
final class NarrationService {
    @ObservationIgnored private let baseURL: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var cache: [String: NarrationTrack?] = [:]

    init(baseURL: URL = Config.supabaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// The first existing track: the requested language, then English, then legacy audio.
    /// Nil when the place has no narration yet.
    func track(for curioID: String, language: AppLanguage) async -> NarrationTrack? {
        let key = "\(curioID)|\(language.rawValue)"
        if let cached = cache[key] { return cached }

        for candidate in NarrationLocator.candidates(curioID: curioID, language: language, baseURL: baseURL) {
            if await exists(candidate.url) {
                cache[key] = candidate
                return candidate
            }
            if Task.isCancelled { return nil }
        }
        cache[key] = .some(nil)
        return nil
    }

    /// Asks for the first byte only. Storage answers 400 for a missing file or a private bucket.
    private func exists(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return false }
        return status == 200 || status == 206
    }
}
