//
//  Fact.swift
//  Curious Places
//

import Foundation

/// A "Did you know?" fact from the `facts` table.
nonisolated struct Fact: Identifiable, Equatable, Sendable {
    let id: String
    let curioID: String
    /// `fact_info` with URLs removed, as the Expo app showed it.
    let text: String
    let language: AppLanguage
    /// 1-based position among *all* the place's facts by `created_at`, whatever their
    /// language. Fact audio files are named by it (`routes.ts:328-345`). Nil when another
    /// fact has the same `created_at` (bulk imports), since then the order, and so the
    /// file name, is arbitrary; those facts' audio is keyed by fact id instead.
    let position: Int?

    /// Fact audio exists only in English (voice Clive).
    var hasAudio: Bool { language == .english }

    /// Removes links, which read badly and can't be narrated (PlaceDetailScreen.tsx `stripUrls`).
    static func stripURLs(_ text: String) -> String {
        text.replacing(#/https?://[^\s)>\]]+/#.ignoresCase(), with: "")
            .replacing(#/\s{2,}/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Facts to show for `language`: those in that language, or English ones when it has none.
    static func displayed(_ facts: [Fact], in language: AppLanguage) -> [Fact] {
        let matching = facts.filter { $0.language == language }
        return matching.isEmpty ? facts.filter { $0.language == .english } : matching
    }
}

/// One row of `facts`.
nonisolated struct FactRow: Decodable, Sendable {
    let id: String
    let curioID: String
    let factInfo: String?
    /// NULL is treated as English, the column's default. The live data has both "en" and "EN".
    let languageCode: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case curioID = "curio_id"
        case factInfo = "fact_info"
        case languageCode = "language_code"
        case createdAt = "created_at"
    }

    /// `rows` must be in `created_at` order. Empty facts and unknown languages are dropped
    /// only after positions are assigned, so positions still match the audio files.
    static func facts(from rows: [FactRow]) -> [Fact] {
        let timestampCounts = Dictionary(rows.map { ($0.createdAt, 1) }, uniquingKeysWith: +)
        return rows.enumerated().compactMap { index, row in
            let text = Fact.stripURLs(row.factInfo ?? "")
            guard !text.isEmpty,
                  let language = AppLanguage(rawValue: (row.languageCode ?? "en").lowercased()) else { return nil }
            let hasUniqueTimestamp = row.createdAt != nil && timestampCounts[row.createdAt] == 1
            return Fact(id: row.id, curioID: row.curioID, text: text, language: language,
                        position: hasUniqueTimestamp ? index + 1 : nil)
        }
    }
}

/// Deals facts at random without repeats until every one has been seen, then starts over
/// (`handleShowRandomFact` in the Expo app).
nonisolated struct FactDeck: Sendable {
    private(set) var facts: [Fact]
    private var seen: Set<Fact.ID> = []

    init(_ facts: [Fact]) {
        self.facts = facts
    }

    var isEmpty: Bool { facts.isEmpty }

    mutating func next<G: RandomNumberGenerator>(using generator: inout G) -> Fact? {
        var unseen = facts.filter { !seen.contains($0.id) }
        if unseen.isEmpty {
            seen.removeAll()
            unseen = facts
        }
        guard let fact = unseen.randomElement(using: &generator) else { return nil }
        seen.insert(fact.id)
        return fact
    }

    mutating func next() -> Fact? {
        var generator = SystemRandomNumberGenerator()
        return next(using: &generator)
    }
}
