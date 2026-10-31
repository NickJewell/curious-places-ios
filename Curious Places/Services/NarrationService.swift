//
//  NarrationService.swift
//  Curious Places
//

import Foundation
import Observation
import Supabase

/// A narration file the app can stream.
nonisolated struct NarrationTrack: Equatable, Sendable {
    let url: URL
    /// The language actually spoken, which may differ from the one asked for.
    let language: AppLanguage
}

/// Where narration may be stored, in the order to try.
/// Paths match the Expo server: `routes.ts:244-345` (current) and
/// `server_dist/index.js:94-125` (legacy pre-generated audio).
nonisolated enum NarrationLocator {
    static func candidates(curioID: String, language: AppLanguage, baseURL: URL) -> [NarrationTrack] {
        guard let number = curioNumber(curioID) else { return [] }
        var tracks: [NarrationTrack] = []
        if language != .english {
            tracks.append(NarrationTrack(url: overviewURL(number: number, language: language, baseURL: baseURL),
                                         language: language))
        }
        tracks.append(NarrationTrack(url: overviewURL(number: number, language: .english, baseURL: baseURL),
                                     language: .english))
        let legacy = legacyFolder(number: number)
        tracks.append(NarrationTrack(url: publicURL(bucket: legacy.bucket, path: "\(legacy.folder)/curio_detail_\(number).mp3",
                                                    baseURL: baseURL),
                                     language: .english))
        return tracks
    }

    /// The fact's file in `en_audio`, then the legacy one keyed by fact id.
    static func factCandidates(for fact: Fact, baseURL: URL) -> [URL] {
        guard fact.hasAudio, let number = curioNumber(fact.curioID) else { return [] }
        let legacy = legacyFolder(number: number)
        return [
            publicURL(bucket: "en_audio", path: factPath(for: fact, number: number), baseURL: baseURL),
            publicURL(bucket: legacy.bucket, path: "\(legacy.folder)/curio_\(number)_\(fact.id).mp3", baseURL: baseURL),
        ]
    }

    /// By position as the server named it (`en_curio_41_fact_03_v2.mp3`), or by fact id
    /// (`en_curio_41_fact_<uuid>.mp3`) when the position is ambiguous. The Edge Function
    /// uses the same rule.
    static func factPath(for fact: Fact, number: Int) -> String {
        guard let position = fact.position else { return "en_curio_\(number)_fact_\(fact.id).mp3" }
        let padded = position < 10 ? "0\(position)" : "\(position)"
        return "en_curio_\(number)_fact_\(padded)_v2.mp3"
    }

    static func overviewURL(number: Int, language: AppLanguage, baseURL: URL) -> URL {
        publicURL(bucket: "\(language.rawValue)_audio",
                  path: "\(language.rawValue)_curio_\(number)_detail_overview.mp3", baseURL: baseURL)
    }

    /// The trailing number of a curio ID ("CURIO-41" → 41), as the server parses it.
    static func curioNumber(_ curioID: String) -> Int? {
        guard let range = curioID.range(of: #"\d+$"#, options: .regularExpression) else { return nil }
        return Int(curioID[range])
    }

    /// 1,000 places per bucket, 100 per folder: CURIO-41 → audio_overviews_1_1000, 1-100
    static func legacyFolder(number: Int) -> (bucket: String, folder: String) {
        let bucketStart = (number - 1) / 1000 * 1000 + 1
        let folderStart = (number - 1) / 100 * 100 + 1
        return ("audio_overviews_\(bucketStart)_\(bucketStart + 999)", "\(folderStart)-\(folderStart + 99)")
    }

    static func publicURL(bucket: String, path: String, baseURL: URL) -> URL {
        baseURL.appending(path: "storage/v1/object/public/\(bucket)/\(path)")
    }
}

/// What the `narration` Edge Function reports for an overview it was asked to make.
nonisolated enum NarrationGeneration: Equatable, Sendable {
    /// The file exists now.
    case ready(NarrationTrack)
    /// The file is being generated in the background. The function also returns its
    /// English "loading" clip; the app doesn't play it, and shows "Preparing narration…" instead.
    case generating(NarrationTrack)
}

/// Finds which narration file exists for a place, and asks the `narration` Edge Function
/// (supabase/functions/narration) to generate missing ones with InWorld TTS.
/// Needs the audio buckets to be public (supabase/proposed/04_public_audio_buckets.sql).
@Observable
final class NarrationService {
    /// How long to wait for a generated overview before giving up.
    static let generationTimeout: Duration = .seconds(90)
    static let pollInterval: Duration = .seconds(3)

    @ObservationIgnored private let baseURL: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let functions: FunctionsClient
    @ObservationIgnored private var cache: [String: NarrationTrack?] = [:]
    @ObservationIgnored private var factCache: [Fact.ID: URL] = [:]

    init(baseURL: URL = Config.supabaseURL, session: URLSession = .shared, functions: FunctionsClient = supabase.functions) {
        self.baseURL = baseURL
        self.session = session
        self.functions = functions
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

    /// Asks the Edge Function to generate the overview in `language`. Called once per
    /// miss; afterwards poll with `waitUntilAvailable` rather than calling this again,
    /// so InWorld isn't asked twice for the same file.
    func requestGeneration(for curioID: String, language: AppLanguage) async throws -> NarrationGeneration {
        let response: GenerationResponse = try await functions.invoke(
            "narration",
            options: FunctionInvokeOptions(body: GenerationRequest(curioId: curioID, language: language.rawValue, factId: nil)),
            decoder: JSONDecoder()
        )
        let track = NarrationTrack(url: NarrationLocator.publicURL(bucket: response.bucket, path: response.path, baseURL: baseURL),
                                   language: language)
        return response.status == "generating" ? .generating(track) : .ready(track)
    }

    /// Polls until a generated track appears, up to `generationTimeout`. False if it
    /// never does or the task is cancelled.
    func waitUntilAvailable(_ track: NarrationTrack, curioID: String) async -> Bool {
        let deadline = ContinuousClock.now + Self.generationTimeout
        while ContinuousClock.now < deadline {
            do { try await Task.sleep(for: Self.pollInterval) } catch { return false }
            if await exists(track.url) {
                cache["\(curioID)|\(track.language.rawValue)"] = track
                return true
            }
        }
        return false
    }

    /// The audio for an English fact: a cached file, or one the Edge Function generates
    /// on the spot (facts are short). Nil for non-English facts or when nothing is available.
    func factAudio(for fact: Fact) async -> URL? {
        guard fact.hasAudio else { return nil }
        if let cached = factCache[fact.id] { return cached }

        for url in NarrationLocator.factCandidates(for: fact, baseURL: baseURL) {
            if await exists(url) {
                factCache[fact.id] = url
                return url
            }
            if Task.isCancelled { return nil }
        }

        guard let response: GenerationResponse = try? await functions.invoke(
            "narration",
            options: FunctionInvokeOptions(body: GenerationRequest(curioId: fact.curioID, language: nil, factId: fact.id)),
            decoder: JSONDecoder()
        ), response.status == "ready" else { return nil }
        let url = NarrationLocator.publicURL(bucket: response.bucket, path: response.path, baseURL: baseURL)
        factCache[fact.id] = url
        return url
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

/// The `narration` Edge Function's request and response bodies.
nonisolated private struct GenerationRequest: Encodable, Sendable {
    let curioId: String
    let language: String?
    let factId: String?
}

nonisolated private struct GenerationResponse: Decodable, Sendable {
    /// "ready" or "generating".
    let status: String
    let bucket: String
    let path: String
}
