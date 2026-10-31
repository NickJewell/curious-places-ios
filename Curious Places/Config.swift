//
//  Congif.swift
//  Curious Places
//
//  Created by Nick Jewell on 31/10/2026.
//

import Foundation
import Supabase

enum Config {
    static let supabaseURL = URL(string: "https://\(value("SUPABASE_HOST"))")!
    static let supabaseKey = value("SUPABASE_ANON_KEY")

    /// Where Supabase sends the user back after Google sign-in or an email
    /// confirmation link. Must be listed in Supabase → Auth → URL Configuration.
    static let authRedirectURL = URL(string: "curiousplaces://auth/callback")!

    /// Off while the app is signed with a free Personal Team, which can't use the
    /// Sign in with Apple capability. To turn on: join the Apple Developer Program,
    /// select that team, set CODE_SIGN_ENTITLEMENTS = Curious-Places.entitlements
    /// on the app target, and set this to true.
    static let isSignInWithAppleEnabled = false

    private static func value(_ key: String) -> String {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !v.isEmpty else {
            fatalError("Missing \(key). Check Secrets.xcconfig")
        }
        return v
    }
}

let supabase = SupabaseClient(
    supabaseURL: Config.supabaseURL,
    supabaseKey: Config.supabaseKey,
    options: SupabaseClientOptions(
        auth: .init(
            redirectToURL: Config.authRedirectURL,
            emitLocalSessionAsInitialSession: true
        )
    )
)
