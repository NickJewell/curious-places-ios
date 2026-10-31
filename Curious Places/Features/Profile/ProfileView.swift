//
//  ProfileView.swift
//  Curious Places
//

import SwiftUI

/// Account, progress (visits and badges), language and appearance.
struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckinStore.self) private var checkins
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.deviceDefault()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var showsSignIn = false
    @State private var confirmsDelete = false
    @State private var selectedBadge: Badge?
    @State private var errorTitle = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if session.status == .signedIn {
                    ProfileHeader()
                    progressSections
                } else {
                    Section {
                        Text("You're exploring as a guest. Sign in to save places, check in and earn badges.")
                            .foregroundStyle(Theme.textSecondary)
                        Button { showsSignIn = true } label: {
                            Text("Sign In or Create Account")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(Theme.gold)
                        .foregroundStyle(Theme.backgroundRoot)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Picker("Descriptions", selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Text("Language").sectionTitleStyle()
                } footer: {
                    Text("Place descriptions are shown in this language when a translation exists.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance").sectionTitleStyle()
                }
                .listRowBackground(Theme.surface)

                if session.status == .signedIn {
                    Section {
                        Button("Sign Out") {
                            Task { await session.signOut() }
                        }
                        Button("Delete Account", role: .destructive) { confirmsDelete = true }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .themedList()
            .navigationTitle("Profile")
            .refreshable { await checkins.reload() }
            .sheet(item: $selectedBadge) { badge in
                BadgeDetailView(badge: badge, earned: checkins.earnedBadge(badge))
            }
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
            .alert(errorTitle, isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var progressSections: some View {
        Section {
            let visits = checkins.isLoading && checkins.checkins.isEmpty ? nil : checkins.checkins.count
            HStack {
                stat(visits.map(String.init) ?? "–", label: "Places visited",
                     spoken: visits.map(String.init) ?? "Loading")
                Divider().frame(height: 36)
                stat("\(checkins.earned.count)/\(checkins.badges.count)", label: "Badges",
                     spoken: "\(checkins.earned.count) of \(checkins.badges.count)")
            }
            .padding(.vertical, 4)

            NavigationLink {
                VisitedPlacesView()
            } label: {
                Label("Places Visited", systemImage: "mappin.and.ellipse")
            }
            if checkins.loadFailed {
                HStack {
                    Label("Couldn't load your progress.", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Retry") { Task { await checkins.reload() } }
                }
            }
        }
        .listRowBackground(Theme.surface)

        if !checkins.badges.isEmpty {
            Section {
                TrophyCase(badges: checkins.badges, isEarned: { checkins.earnedBadge($0) != nil }) { badge in
                    selectedBadge = badge
                }
            } header: {
                Text("Trophy Case").sectionTitleStyle()
            }
            .listRowBackground(Theme.surface)
        }

        Section {
            if checkins.checkins.isEmpty {
                Text(checkins.isLoading ? "Loading…" : "No visits yet. Hunt for a place on the map and check in when you get there.")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(checkins.checkins.prefix(5)) { checkin in
                CheckinRow(checkin: checkin)
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) { remove(checkin) }
                    }
            }
        } header: {
            Text("Recent Visits").sectionTitleStyle()
        }
        .listRowBackground(Theme.surface)
    }

    /// A headline number: visits or badges.
    private func stat(_ value: String, label: String, spoken: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .foregroundStyle(Theme.gold)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }

    private func remove(_ checkin: Checkin) {
        guard let userID = session.userID else { return }
        Task {
            do {
                try await checkins.remove(placeID: checkin.placeID, userID: userID)
            } catch {
                errorTitle = "Couldn't remove the check-in"
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await session.deleteAccount()
            } catch {
                errorTitle = "Couldn't delete your account"
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
        .listRowBackground(Theme.surface)
    }
}

extension AppLanguage {
    static let storageKey = "preferredLanguage"
}
