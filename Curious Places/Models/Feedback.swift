//
//  Feedback.swift
//  Curious Places
//

import Foundation

/// A thumbs up or down on a place (`content_votes.vote_type`).
nonisolated enum VoteType: String, Codable, Sendable {
    case up
    case down
}

/// One row of `content_votes`, for reading the user's vote back.
nonisolated struct VoteRow: Decodable, Sendable {
    let voteType: VoteType

    enum CodingKeys: String, CodingKey {
        case voteType = "vote_type"
    }
}

nonisolated struct VoteWrite: Encodable, Sendable {
    let curioID: String
    let voteType: VoteType
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case curioID = "curio_id"
        case voteType = "vote_type"
        case userID = "user_id"
    }
}

/// The reasons offered in "Report an Issue" (PlaceDetailScreen.tsx:63-70).
nonisolated enum IssueType: String, CaseIterable, Identifiable, Sendable {
    case incorrectLocation = "incorrect_location"
    case incorrectInfo = "incorrect_info"
    case typo
    case badAudio = "bad_audio"
    case offensive
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .incorrectLocation: "Incorrect location"
        case .incorrectInfo: "Incorrect info"
        case .typo: "Typo"
        case .badAudio: "Bad audio"
        case .offensive: "Offensive"
        case .other: "Other"
        }
    }
}

/// What a report is about: a place (by `curio_id`) or one of its facts (by fact id).
nonisolated enum IssueSource: Hashable, Identifiable, Sendable {
    case place(String)
    case fact(String)

    var id: String { "\(type):\(sourceID)" }

    var type: String {
        switch self {
        case .place: "place"
        case .fact: "fact"
        }
    }

    var sourceID: String {
        switch self {
        case .place(let id), .fact(let id): id
        }
    }
}

/// A new row of `issues`.
nonisolated struct IssueReport: Encodable, Sendable {
    /// `other_desc` is capped at this length, as the Expo server did (`routes.ts:502`).
    static let maxDescriptionLength = 200

    let sourceID: String
    let sourceType: String
    let issueType: IssueType
    let otherDescription: String?
    /// A `profiles.id` (the column's foreign key), or nil for guests.
    let userID: UUID?

    /// The description is kept only for `.other`, trimmed and capped.
    init(source: IssueSource, issueType: IssueType, description: String?, userID: UUID?) {
        sourceID = source.sourceID
        sourceType = source.type
        self.issueType = issueType
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        otherDescription = issueType == .other && !trimmed.isEmpty
            ? String(trimmed.prefix(Self.maxDescriptionLength))
            : nil
        self.userID = userID
    }

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case sourceType = "source_type"
        case issueType = "issue_type"
        case otherDescription = "other_desc"
        case userID = "user_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(issueType.rawValue, forKey: .issueType)
        try container.encodeIfPresent(otherDescription, forKey: .otherDescription)
        try container.encodeIfPresent(userID, forKey: .userID)
    }
}
