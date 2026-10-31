//
//  PlaceFeedbackModel.swift
//  Curious Places
//

import Foundation
import Observation

/// The signed-in user's vote on one place, and issue reports about it or its facts.
/// Follows the Expo detail screen: thumbs up toggles; thumbs down opens a report, and
/// sending a report about the place records the thumbs down.
@Observable
final class PlaceFeedbackModel {
    private(set) var vote: VoteType?
    /// True while a vote is being saved. Further taps are ignored, so two
    /// delete-then-insert sequences can't interleave and leave duplicate rows.
    private(set) var isSaving = false

    private let curioID: String
    private let service: FeedbackService

    init(curioID: String, service: FeedbackService) {
        self.curioID = curioID
        self.service = service
    }

    func load(userID: UUID?) async {
        guard let userID else {
            vote = nil
            return
        }
        let stored = try? await service.vote(on: curioID, userID: userID)
        // A tap made while this was loading wins over what was stored before it.
        guard !isSaving else { return }
        vote = stored
    }

    func toggleUp(userID: UUID) async {
        await setVote(vote == .up ? nil : .up, userID: userID)
    }

    func removeDown(userID: UUID) async {
        await setVote(nil, userID: userID)
    }

    /// Throws only if the report itself couldn't be saved. `voterID` is nil for guests,
    /// who can report but not vote.
    func submit(_ report: IssueReport, about source: IssueSource, voterID: UUID?) async throws {
        try await service.report(report)
        if case .place = source, let voterID {
            await setVote(.down, userID: voterID)
        }
    }

    private func setVote(_ newVote: VoteType?, userID: UUID) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let previous = vote
        vote = newVote
        do {
            try await service.setVote(newVote, on: curioID, userID: userID)
        } catch {
            // The delete may have gone through without the insert, so ask what's stored.
            if let stored = try? await service.vote(on: curioID, userID: userID) {
                vote = stored
            } else {
                vote = previous
            }
        }
    }
}
