//
//  AppleSignInNonce.swift
//  Curious Places
//

import CryptoKit
import Foundation

/// Sign in with Apple nonce: Apple gets the SHA-256 hash, Supabase gets the raw
/// value, and Supabase checks they match the token Apple issued.
nonisolated enum AppleSignInNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func make(length: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
