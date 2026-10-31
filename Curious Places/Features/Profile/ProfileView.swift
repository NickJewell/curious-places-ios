//
//  ProfileView.swift
//  Curious Places
//

import SwiftUI

/// Account, language and appearance. Badges and visited places arrive with check-ins.
struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.deviceDefault()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var showsSignIn = false
    @State private var confirmsDelete = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if session.status == .signedIn {
                    ProfileHeader()
                } else {
                    Section {
                        Text("You're exploring as a guest. Sign in to save places, check in and earn badges.")
                            .foregroundStyle(Theme.textSecondary)
                        Button("Sign In or Create Account") { showsSignIn = true }
                    }
                }

                Section {
                    Picker("Descriptions", selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Place descriptions are shown in this language when a translation exists.")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if session.status == .signedIn {
                    Section {
                        Button("Sign Out") {
                            Task { await session.signOut() }
                        }
                        Button("Delete Account", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .navigationTitle("Profile")
            .onChange(of: language) {
                Task { await session.updateLanguage(language) }
            }
            .sheet(isPresented: $showsSignIn) {
                SignInView(allowsGuest: false)
            }
            .onChange(of: session.status) {
                if session.status == .signedIn { showsSignIn = false }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) { deleteAccount() }
            } message: {
                Text("This permanently deletes your account, saved lists and check-ins. It can't be undone.")
            }
            .alert("Couldn't delete your account", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await session.deleteAccount()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ProfileHeader: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Section {
            HStack(spacing: 16) {
                AsyncImage(url: session.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(Theme.bronze)
                }
                .frame(width: 64, height: 64)
                .clipShape(.circle)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let email = session.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if session.isAdmin {
                        Label("Admin", systemImage: "shield.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

extension AppLanguage {
    static let storageKey = "preferredLanguage"
}
