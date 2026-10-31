//
//  SessionStore.swift
//  Curious Places
//

import AuthenticationServices
import Foundation
import Observation
import Supabase

/// The signed-in user, their profile, and guest mode.
@Observable
final class SessionStore {
    enum Status: Equatable {
        case loading
        case signedOut
        case guest
        case signedIn
    }

    enum SignUpResult {
        case signedIn
        /// Supabase sent a confirmation email; the link opens the app via `curiousplaces://`.
        case needsEmailConfirmation
    }

    static let guestKey = "isGuest"

    private(set) var status: Status = .loading
    private(set) var user: User?
    private(set) var profile: Profile?

    private let client: SupabaseClient
    private let defaults: UserDefaults

    init(client: SupabaseClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    var isAdmin: Bool {
        AdminAccess.isAdmin(
            adminFlag: profile?.adminFlag,
            email: user?.email,
            emailVerified: user?.emailConfirmedAt != nil
        )
    }

    var email: String? { user?.email }

    var displayName: String {
        profile?.fullName ?? metadataName ?? user?.email ?? "Explorer"
    }

    var avatarURL: URL? {
        (profile?.avatarURL ?? metadataAvatar).flatMap(URL.init(string:))
    }

    // MARK: - Session

    /// Follows Supabase auth events for the life of the app. The first event is
    /// the session restored from the Keychain (or none).
    func listen() async {
        for await (event, session) in client.auth.authStateChanges {
            await apply(event: event, session: session)
        }
    }

    private func apply(event: AuthChangeEvent, session: Session?) async {
        guard let session else {
            user = nil
            profile = nil
            status = defaults.bool(forKey: Self.guestKey) ? .guest : .signedOut
            return
        }
        let isNewUser = user?.id != session.user.id
        user = session.user
        status = .signedIn
        defaults.set(false, forKey: Self.guestKey)
        if isNewUser || event == .userUpdated {
            await loadProfile()
        }
    }

    /// Completes Google sign-in or an email confirmation link opened from outside the app.
    func handleOpenURL(_ url: URL) async {
        _ = try? await client.auth.session(from: url)
    }

    // MARK: - Sign in

    func signInWithApple(_ authorization: ASAuthorization, nonce: String) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw SignInError.appleTokenMissing
        }
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        // Apple sends the name only on the first authorisation, so save it now or lose it.
        if let components = credential.fullName {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty {
                _ = try? await client.auth.update(user: UserAttributes(data: ["full_name": .string(name)]))
            }
        }
    }

    func signInWithGoogle() async throws {
        do {
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: Config.authRedirectURL)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        }
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String, fullName: String) async throws -> SignUpResult {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: name.isEmpty ? nil : ["full_name": .string(name)],
            redirectTo: Config.authRedirectURL
        )
        return response.session == nil ? .needsEmailConfirmation : .signedIn
    }

    func continueAsGuest() {
        defaults.set(true, forKey: Self.guestKey)
        status = .guest
    }

    func signOut() async {
        defaults.set(false, forKey: Self.guestKey)
        if user == nil {
            status = .signedOut
            return
        }
        try? await client.auth.signOut()
    }

    /// Needs `public.delete_own_account()` (supabase/proposed/03_account_and_admin.sql).
    func deleteAccount() async throws {
        try await client.rpc("delete_own_account").execute()
        // The server session is gone with the user, so only clear the local one.
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: - Profile

    private func loadProfile() async {
        guard let user else { return }
        do {
            let rows: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .limit(1)
                .execute()
                .value
            if var profile = rows.first {
                profile = try await backfill(profile, from: user)
                self.profile = profile
            } else {
                profile = try await createProfile(for: user)
            }
            await syncLanguage()
        } catch {
            // Stay signed in without a profile; it's retried on the next sign-in or user update.
        }
    }

    private func createProfile(for user: User) async throws -> Profile {
        let row = ProfileWrite(id: user.id, email: user.email, fullName: metadataName, avatarURL: metadataAvatar)
        try await client.from("profiles").upsert(row, onConflict: "id").execute()
        return Profile(id: user.id, email: row.email, fullName: row.fullName, avatarURL: row.avatarURL)
    }

    /// Fills in a missing name or avatar from the sign-in provider (as the Expo app did for Google).
    private func backfill(_ profile: Profile, from user: User) async throws -> Profile {
        let name = profile.fullName ?? metadataName
        let avatar = profile.avatarURL ?? metadataAvatar
        guard name != profile.fullName || avatar != profile.avatarURL else { return profile }
        let row = ProfileWrite(id: profile.id, email: profile.email ?? user.email, fullName: name, avatarURL: avatar)
        try await client.from("profiles").update(row).eq("id", value: profile.id).execute()
        var updated = profile
        updated.fullName = name
        updated.avatarURL = avatar
        updated.email = row.email
        return updated
    }

    private func syncLanguage() async {
        guard let profile else { return }
        let local = defaults.string(forKey: AppLanguage.storageKey).flatMap(AppLanguage.init(rawValue:))
            ?? .deviceDefault()
        switch LanguageSync.reconcile(remote: profile.preferredLanguage, local: local) {
        case .useRemote(let language):
            defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        case .pushLocal(let language):
            await updateLanguage(language)
        case .none:
            break
        }
    }

    /// Saves the description language to the profile. No-op for guests.
    func updateLanguage(_ language: AppLanguage) async {
        guard let user, let profile else { return }
        let value = LanguageSync.remoteValue(for: language)
        guard profile.preferredLanguage != value else { return }
        do {
            try await client.from("profiles")
                .update(LanguageWrite(preferredLanguage: value))
                .eq("id", value: user.id)
                .execute()
            self.profile?.preferredLanguage = value
        } catch {
            // The choice is still saved on the device; it's pushed again at next sign-in.
        }
    }

    // MARK: - Provider metadata

    private var metadataName: String? {
        user?.userMetadata["full_name"]?.stringValue ?? user?.userMetadata["name"]?.stringValue
    }

    private var metadataAvatar: String? {
        user?.userMetadata["avatar_url"]?.stringValue ?? user?.userMetadata["picture"]?.stringValue
    }
}

enum SignInError: LocalizedError {
    case appleTokenMissing

    var errorDescription: String? {
        switch self {
        case .appleTokenMissing: "Apple didn't return a sign-in token. Please try again."
        }
    }
}
