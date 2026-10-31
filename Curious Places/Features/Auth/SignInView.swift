//
//  SignInView.swift
//  Curious Places
//

import AuthenticationServices
import SwiftUI

/// The sign-in screen. Shown full screen when signed out, and as a sheet from
/// Profile for guests (`allowsGuest: false`).
struct SignInView: View {
    let allowsGuest: Bool

    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsEmailForm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero

                VStack(spacing: 12) {
                    if Config.isSignInWithAppleEnabled {
                        SignInWithAppleButton(.continue) { request in
                            nonce = AppleSignInNonce.make()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = AppleSignInNonce.sha256(nonce)
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 52)
                        .clipShape(.capsule)
                    }

                    Button {
                        run { try await session.signInWithGoogle() }
                    } label: {
                        // A card-surface capsule: the bordered style's grey fill read as disabled.
                        Label("Continue with Google", systemImage: "globe")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.surface, in: .capsule)
                            .overlay(Capsule().stroke(Theme.border))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)

                    if showsEmailForm {
                        EmailSignInForm(isWorking: $isWorking, errorMessage: $errorMessage)
                    } else {
                        Button("Continue with Email") {
                            withAnimation(.snappy) { showsEmailForm = true }
                        }
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44)
                    }
                }
                .disabled(isWorking)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if allowsGuest {
                    Button("Continue as Guest") { session.continueAsGuest() }
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.backgroundRoot)
        .overlay {
            if isWorking { ProgressView().controlSize(.large) }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image("LoginHero")
                .resizable()
                .scaledToFill()
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Theme.backgroundRoot], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                }
                .padding(.horizontal, -24)
                .accessibilityHidden(true)

            Text("Discover\n\(Text("Hidden London").foregroundStyle(Theme.gold))")
                .font(.largeTitle.weight(.bold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.textPrimary)

            Text("Uncover mysteries, legends, and forgotten stories scattered across the city.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .multilineTextAlignment(.center)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            let nonce = nonce
            run { try await session.signInWithApple(authorization, nonce: nonce) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct EmailSignInForm: View {
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?

    @Environment(SessionStore.self) private var session
    @State private var isCreatingAccount = false
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationSentTo: String?

    var body: some View {
        VStack(spacing: 12) {
            if let confirmationSentTo {
                Label("Check \(confirmationSentTo) for a link to confirm your account, then sign in.",
                      systemImage: "envelope.badge")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }

            if isCreatingAccount {
                field("Full name (optional)", text: $fullName)
                    .textContentType(.name)
            }
            field("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Theme.surface, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))

            Button(action: submit) {
                Text(isCreatingAccount ? "Create Account" : "Sign In")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!canSubmit)

            Button(isCreatingAccount ? "Already have an account? Sign In" : "Don't have an account? Sign Up") {
                withAnimation(.snappy) { isCreatingAccount.toggle() }
            }
            .font(.footnote)
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Theme.surface, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private func submit() {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if isCreatingAccount {
                    let result = try await session.signUp(email: email, password: password, fullName: fullName)
                    if result == .needsEmailConfirmation {
                        confirmationSentTo = email
                        isCreatingAccount = false
                    }
                } else {
                    try await session.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
