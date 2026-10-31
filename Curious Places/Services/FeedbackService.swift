//
//  FeedbackService.swift
//  Curious Places
//

import Foundation
import Supabase

/// Votes and issue reports, written directly with the user's session.
/// Votes need a signed-in user (supabase/proposed/01 §6); anyone may report (§7).
struct FeedbackService {
    let client: SupabaseClient

    /// The user's current vote on a place. There's no unique constraint on
    /// `content_votes`, so if old duplicates exist the newest wins.
    func vote(on curioID: String, userID: UUID) async throws -> VoteType? {
        let rows: [VoteRow] = try await client
            .from("content_votes")
            .select("vote_type")
            .eq("curio_id", value: curioID)
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.voteType
    }

    /// Replaces the user's vote. Clearing all their rows first also tidies up any duplicates.
    /// The delete is always scoped to the user: the live policy would let it remove anyone's votes.
    func setVote(_ vote: VoteType?, on curioID: String, userID: UUID) async throws {
        try await client
            .from("content_votes")
            .delete()
            .eq("curio_id", value: curioID)
            .eq("user_id", value: userID)
            .execute()
        if let vote {
            try await client
                .from("content_votes")
                .insert(VoteWrite(curioID: curioID, voteType: vote, userID: userID))
                .execute()
        }
    }

    /// No row is asked for back: `issues` has no read policy, so `return=representation` would fail.
    func report(_ report: IssueReport) async throws {
        try await client.from("issues").insert(report).execute()
    }
}
