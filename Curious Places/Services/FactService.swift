//
//  FactService.swift
//  Curious Places
//

import Foundation
import Supabase

/// Reads a place's facts straight from Supabase (the live `facts` table has a public read policy).
struct FactService {
    let client: SupabaseClient

    /// Every fact for the place, in every language, with positions matching the audio files.
    func facts(for curioID: String) async throws -> [Fact] {
        // Same filter and order as the server's fact-audio route, so positions agree with it.
        let rows: [FactRow] = try await client
            .from("facts")
            .select("id,curio_id,fact_info,language_code,created_at")
            .eq("curio_id", value: curioID)
            .order("created_at", ascending: true)
            .execute()
            .value
        return FactRow.facts(from: rows)
    }
}
