//
//  HuntView.swift
//  Curious Places
//

import SwiftUI

/// The full-screen hunt (the Expo CompassScreen): a map page and a compass page,
/// check-in when within 40 m, and an "arrived" screen under 10 m.
struct HuntView: View {
    /// Identifies one celebration, so checking in again (after removing) shows a fresh one.
    private struct Celebration: Identifiable {
        let id = UUID()
        let outcome: CheckinOutcome
    }

    @Environment(HuntStore.self) private var hunt
    @Environment(CheckinStore.self) private var checkins
    @Environment(SessionStore.self) private var session

    @Bindable var model: HuntModel
    @State private var isSaving = false
    @State private var celebration: Celebration?
    @State private var confirmsRemove = false
    @State private var showsSignIn = false
    @State private var errorMessage: String?

    private var target: Place { model.target }
    private var isCheckedIn: Bool { checkins.isCheckedIn(target.id) }

    var body: some View {
        VStack(spacing: 12) {
            header
            if model.progress.hasArrived {
                arrived
            } else {
                Picker("View", selection: $model.page) {
                    ForEach(HuntModel.Page.allCases) { page in
                        Label(page.rawValue, systemImage: page.systemImage).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    switch model.page {
                    case .map: HuntMapView(model: model)
                    case .compass: CompassView(model: model)
                    }
                }
                .frame(maxHeight: .infinity)

                checkInControls
                    .padding(.horizontal)

                Button(action: hunt.end) {
                    Label("End Hunt", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HuntButtonStyle(fill: HuntPalette.surface, foreground: .secondary))
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay {
            if model.isAuthorizationDenied {
                ContentUnavailableView(
                    "Location is off",
                    systemImage: "location.slash",
                    description: Text("Allow Curious Places to use your location in Settings to hunt for places.")
                )
                .background(Color.black)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .sensoryFeedback(.success, trigger: model.progress.hasArrived) { _, arrived in arrived }
        .sensoryFeedback(.success, trigger: isCheckedIn)
        .onChange(of: session.status) {
            if session.status == .signedIn { showsSignIn = false }
        }
        .sheet(item: $celebration) { celebration in
            CheckinSuccessView(placeName: target.name, outcome: celebration.outcome)
        }
        .sheet(isPresented: $showsSignIn) {
            SignInView(allowsGuest: false)
        }
        .confirmationDialog("Remove your check-in at \(target.name)?", isPresented: $confirmsRemove,
                            titleVisibility: .visible) {
            Button("Remove Check-in", role: .destructive) { removeCheckin() }
        } message: {
            Text("You can check in again while you're here. Badges you've earned are kept.")
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            Button {
                hunt.isCompassPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Back to the map")
            .accessibilityHint("The hunt carries on")

            Text(target.name)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
    }

    // MARK: - Arrived

    private var arrived: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: isCheckedIn ? "checkmark.circle.fill" : "mappin.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(isCheckedIn ? HuntPalette.green : Theme.gold)
                .contentTransition(.symbolEffect(.replace))
            Text(isCheckedIn ? "Checked In!" : "You Arrived!")
                .font(.largeTitle.bold())
                .foregroundStyle(HuntPalette.green)
            Text(target.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if !target.overviewText.isEmpty {
                OverviewText(place: target)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Spacer()
            checkInControls
            Button(isCheckedIn ? "Done" : "Complete Hunt", action: hunt.end)
                .frame(maxWidth: .infinity)
                .buttonStyle(HuntButtonStyle(fill: HuntPalette.surface, foreground: .white))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Check-in

    @ViewBuilder
    private var checkInControls: some View {
        if isCheckedIn {
            VStack(spacing: 4) {
                Label("Checked In", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(HuntPalette.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(HuntPalette.green.opacity(0.15), in: .rect(cornerRadius: 12))
                Button(role: .destructive) {
                    confirmsRemove = true
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("Remove Check-in", systemImage: "xmark.circle")
                            .font(.subheadline)
                    }
                }
                .tint(HuntPalette.red)
                .frame(minHeight: 44)
                .disabled(isSaving)
            }
        } else if model.progress.canCheckIn {
            if session.status == .signedIn {
                Button(action: checkIn) {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Label("Check In Now", systemImage: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(HuntButtonStyle(fill: HuntPalette.green, foreground: .white))
                .disabled(isSaving)
            } else {
                Button("Sign In to Check In") { showsSignIn = true }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(HuntButtonStyle(fill: HuntPalette.surface, foreground: Theme.gold))
            }
        } else if model.progress.hasArrived || (model.progress.distance ?? .infinity) < HuntMath.nearbyDistance {
            Label("Get within \(Int(HuntMath.checkInDistance)) m to check in", systemImage: "mappin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(HuntPalette.surface, in: .rect(cornerRadius: 12))
        }
    }

    private func checkIn() {
        guard session.status == .signedIn, let userID = session.userID, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let outcome = try await checkins.checkIn(target, userID: userID)
                if outcome.isNew { celebration = Celebration(outcome: outcome) }
            } catch {
                errorMessage = "Couldn't check in. Check your connection and try again."
            }
        }
    }

    private func removeCheckin() {
        guard let userID = session.userID, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await checkins.remove(placeID: target.id, userID: userID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Fixed colours from the Expo hunt screens, which are always dark.
enum HuntPalette {
    static let green = Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)
    static let red = Color(red: 0xE7 / 255, green: 0x4C / 255, blue: 0x3C / 255)
    static let needle = Color(red: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255)
    static let surface = Color(white: 0.12)
}

struct HuntButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(fill, in: .rect(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
