//
//  Profile.swift
//  Curious Places
//

import Foundation

/// A row of `profiles` (id = auth.users.id). Everything but `id` is optional so a
/// missing column or a half-filled row still decodes.
nonisolated struct Profile: Decodable, Sendable, Equatable {
    let id: UUID
    var email: String?
    var fullName: String?
    var avatarURL: String?
    var adminFlag: Bool?
    /// NULL means English.
    var preferredLanguage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case avatarURL = "avatar_url"
        case adminFlag = "admin_flag"
        case preferredLanguage = "preferred_language"
    }
}

/// The columns the app may write when creating or back-filling a profile.
/// Matches the column grants in supabase/proposed/01_rls_policies.sql.
nonisolated struct ProfileWrite: Encodable, Sendable {
    let id: UUID
    let email: String?
    let fullName: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case avatarURL = "avatar_url"
    }
}

/// `preferred_language` update. Encodes an explicit null for English.
nonisolated struct LanguageWrite: Encodable, Sendable {
    let preferredLanguage: String?

    enum CodingKeys: String, CodingKey {
        case preferredLanguage = "preferred_language"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preferredLanguage, forKey: .preferredLanguage)
    }
}

/// How the device's language choice and the profile's are reconciled at sign-in.
nonisolated enum LanguageSync {
    enum Action: Equatable {
        /// The profile has a choice; adopt it on this device.
        case useRemote(AppLanguage)
        /// The profile has none; save this device's non-English choice to it
        /// (the Expo app's one-time backfill).
        case pushLocal(AppLanguage)
        case none
    }

    static func reconcile(remote: String?, local: AppLanguage) -> Action {
        if let remote, let language = AppLanguage(rawValue: remote) {
            return language == local ? .none : .useRemote(language)
        }
        return local == .english ? .none : .pushLocal(local)
    }

    /// The value stored in `profiles.preferred_language` for a language.
    static func remoteValue(for language: AppLanguage) -> String? {
        language == .english ? nil : language.rawValue
    }
}

/// Who gets admin access. `profiles.admin_flag`, plus Nick's address however he
/// signs in (Apple, Google or email can each create a separate account).
/// The database has the same rule in `public.is_admin()` (supabase/proposed/03).
nonisolated enum AdminAccess {
    static let emails: Set<String> = ["nick.jewell@gmail.com"]

    /// The email only counts once it's verified, so nobody can claim it by
    /// signing up with it unconfirmed.
    static func isAdmin(adminFlag: Bool?, email: String?, emailVerified: Bool) -> Bool {
        if adminFlag == true { return true }
        guard emailVerified, let email else { return false }
        return emails.contains(email.lowercased())
    }
}
