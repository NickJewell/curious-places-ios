//
//  CheckinService.swift
//  Curious Places
//

import Foundation
import Supabase

/// Check-ins and badges, read and written directly with the user's session.
/// `user_id` here is the auth user id, not the profile id (unlike `issues`).
struct CheckinService {
    let client: SupabaseClient

    /// Every check-in, newest first. One row per place, so this stays small.
    func checkins(userID: UUID) async throws -> [Checkin] {
        try await client
            .from("checkins")
            .select("id,place_id,place_name,place_latitude,place_longitude,checked_in_at")
            .eq("user_id", value: userID)
            .order("checked_in_at", ascending: false)
            .execute()
            .value
    }

    /// Returns false if the place was already checked in (`23505`, as in the Expo app).
    func checkIn(_ place: Place, userID: UUID) async throws -> Bool {
        do {
            try await client.from("checkins").insert(CheckinWrite(place: place, userID: userID)).execute()
            return true
        } catch let error as PostgrestError where error.code == "23505" {
            return false
        }
    }

    /// Throws `CheckinError.notRemoved` when nothing was deleted. Without the DELETE
    /// policy in supabase/proposed/06 the request "succeeds" but removes nothing,
    /// which is how the Expo app's remove button failed silently.
    func removeCheckin(placeID: String, userID: UUID) async throws {
        let deleted: [IDRow] = try await client
            .from("checkins")
            .delete()
            .eq("user_id", value: userID)
            .eq("place_id", value: placeID)
            .select("id")
            .execute()
            .value
        if deleted.isEmpty { throw CheckinError.notRemoved }
    }

    /// All badge definitions, easiest first.
    func badges() async throws -> [Badge] {
        try await client
            .from("badges")
            .select("id,name,description,icon_name,requirement_type,requirement_value")
            .order("requirement_value", ascending: true)
            .execute()
            .value
    }

    func earnedBadges(userID: UUID) async throws -> [EarnedBadge] {
        try await client
            .from("user_badges")
            .select("badge_id,earned_at")
            .eq("user_id", value: userID)
            .execute()
            .value
    }

    private nonisolated struct IDRow: Decodable, Sendable {
        let id: UUID
    }
}

enum CheckinError: LocalizedError {
    case notRemoved

    var errorDescription: String? {
        switch self {
        case .notRemoved: "The check-in couldn't be removed. Please try again later."
        }
    }
}
