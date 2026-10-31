//
//  PlaceDetailView.swift
//  Curious Places
//

import MapKit
import SwiftUI

/// Place detail: narration, description, "Did you know?" facts, votes and issue reports.
/// Narration and fact audio have their own players; starting one pauses the other.
struct PlaceDetailView: View {
    let place: Place
    /// Starts a hunt for the place. The presenter closes this sheet first.
    let onHunt: (() -> Void)?
    @Environment(LocationProvider.self) private var location
    @Environment(SessionStore.self) private var session
    @Environment(CheckinStore.self) private var checkins
    @Environment(\.dismiss) private var dismiss

    @State private var narrationPlayer = NarrationPlayer()
    @State private var factPlayer = NarrationPlayer()
    @State private var feedback: PlaceFeedbackModel
    @State private var reportSource: IssueSource?
    @State private var didReport = false
    @State private var showsThanks = false
    @State private var showsSignIn = false

    init(place: Place, onHunt: (() -> Void)? = nil) {
        self.place = place
        self.onHunt = onHunt
        _feedback = State(initialValue: PlaceFeedbackModel(curioID: place.id, service: FeedbackService(client: supabase)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: place.coordinate, latitudinalMeters: 400, longitudinalMeters: 400
                    )), interactionModes: []) {
                        Marker(place.name, systemImage: place.category.systemImage, coordinate: place.coordinate)
                            .tint(place.category.color)
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .frame(height: 200)
                    .clipShape(.rect(cornerRadius: 18))

                    HStack(spacing: 8) {
                        CategoryBadge(category: place.category)
                        if let distance = location.distance(to: place.coordinate) {
                            Label(distance.formattedDistance, systemImage: "location.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if checkins.isCheckedIn(place.id) {
                            VisitedBadge()
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(place.name)
                            .font(.title.weight(.bold))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VoteButtons(vote: feedback.vote, onUp: voteUp, onDown: voteDown)
                            .disabled(feedback.isSaving)
                    }

                    if let onHunt {
                        HuntButton(title: "Navigate Here", action: onHunt)
                    }

                    NarrationView(place: place, player: narrationPlayer)

                    StoryDivider()

                    if place.overviewText.isEmpty {
                        Text("There's no description for this place yet.")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        if place.language != .english && !place.isShowingTranslation {
                            Label("Not yet translated into \(place.language.displayName). Showing English.",
                                  systemImage: "globe")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        // Stories in serif, as the Expo design guidelines asked; controls stay in SF.
                        OverviewText(place: place)
                            .font(.body)
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                    }

                    StoryDivider()

                    FactCard(place: place, player: factPlayer) { fact in
                        reportSource = .fact(fact.id)
                    }
                }
                .padding()
            }
            .background(Theme.backgroundRoot)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: voterID) { await feedback.load(userID: voterID) }
        .onChange(of: narrationPlayer.isPlaying) { _, playing in
            if playing { factPlayer.pause() }
        }
        .onChange(of: factPlayer.isPlaying) { _, playing in
            if playing { narrationPlayer.pause() }
        }
        .onChange(of: session.status) {
            if session.status == .signedIn { showsSignIn = false }
        }
        .onDisappear {
            narrationPlayer.release()
            factPlayer.release()
        }
        .sheet(item: $reportSource, onDismiss: {
            if didReport { showsThanks = true }
            didReport = false
        }) { source in
            ReportIssueSheet(source: source) { issueType, details in
                try await report(source, issueType: issueType, details: details)
            }
        }
        .sheet(isPresented: $showsSignIn) {
            SignInView(allowsGuest: false)
        }
        .alert("Thank you", isPresented: $showsThanks) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We'll look into it.")
        }
    }

    /// Votes belong to the signed-in user (`content_votes.user_id` → auth.users).
    private var voterID: UUID? {
        session.status == .signedIn ? session.userID : nil
    }

    private func voteUp() {
        guard let voterID else {
            showsSignIn = true
            return
        }
        Task { await feedback.toggleUp(userID: voterID) }
    }

    /// Removes a thumbs down, or opens a report (guests can report but not vote).
    private func voteDown() {
        if feedback.vote == .down, let voterID {
            Task { await feedback.removeDown(userID: voterID) }
        } else {
            reportSource = .place(place.id)
        }
    }

    private func report(_ source: IssueSource, issueType: IssueType, details: String) async throws {
        // `issues.user_id` references profiles, so use the profile id, if the profile exists.
        let report = IssueReport(source: source, issueType: issueType, description: details,
                                 userID: session.profile?.id)
        try await feedback.submit(report, about: source, voterID: voterID)
        didReport = true
    }
}

/// A gold hairline that fades out at both ends, between the player, the story and the facts.
private struct StoryDivider: View {
    var body: some View {
        LinearGradient(colors: [.clear, Theme.gold.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}
