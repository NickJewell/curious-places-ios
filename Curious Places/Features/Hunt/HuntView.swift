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
        /// The tour this check-in finished, if any.
        let completedTour: String?
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
    @State private var showsDetail = false

    private var target: Place { model.target }
    private var route: HuntRoute? { hunt.route }
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

                HStack(spacing: 12) {
                    Button(action: hunt.end) {
                        Label(route == nil ? "End Hunt" : "End Tour", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(HuntButtonStyle(fill: HuntPalette.surface, foreground: .secondary))
                    if route?.next != nil {
                        Button(action: hunt.advance) {
                            Label(isCheckedIn ? "Next Stop" : "Skip Stop", systemImage: "forward.end")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(HuntButtonStyle(fill: HuntPalette.surface,
                                                     foreground: isCheckedIn ? Theme.gold : .secondary))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(Theme.backgroundRoot.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay {
            if model.isAuthorizationDenied {
                ContentUnavailableView(
                    "Location is off",
                    systemImage: "location.slash",
                    description: Text("Allow Curious Places to use your location in Settings to hunt for places.")
                )
                .background(Theme.backgroundRoot)
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
            CheckinSuccessView(placeName: target.name, outcome: celebration.outcome,
                               completedTour: celebration.completedTour)
        }
        .sheet(isPresented: $showsDetail) {
            PlaceDetailView(place: target)
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

            VStack(spacing: 2) {
                Text(target.name)
                    .font(.headline)
                    .lineLimit(1)
                if let route {
                    Text("\(route.progress) · \(route.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            // Spoken turn-by-turn is Apple Maps' job; the hunt carries on meanwhile.
            Button(action: model.openInMaps) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Walking directions in Maps")
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
                .symbolEffect(.bounce, value: isCheckedIn)
            // Gold until the check-in lands, then green, matching the icon above.
            Text(isCheckedIn ? "Checked In!" : "You Arrived!")
                .font(.largeTitle.bold())
                .fontDesign(.serif)
                .foregroundStyle(isCheckedIn ? HuntPalette.green : Theme.gold)
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
            Button("Read More") { showsDetail = true }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.gold)
            Spacer()
            checkInControls
            if let next = route?.next {
                Button(action: hunt.advance) {
                    Label("Next Stop: \(next.name)", systemImage: "forward.end")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HuntButtonStyle(fill: Theme.gold, foreground: .black))
                Button("End Tour", action: hunt.end)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(HuntButtonStyle(fill: HuntPalette.surface, foreground: .white))
            } else {
                Button(finishTitle, action: hunt.end)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(HuntButtonStyle(fill: HuntPalette.surface, foreground: .white))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var finishTitle: String {
        if route != nil { return "Finish Tour" }
        return isCheckedIn ? "Done" : "Complete Hunt"
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
                guard outcome.isNew else { return }
                // The database records a tour as complete once every stop is checked in (proposed/07).
                let completedTour = route.flatMap { route in
                    route.isTour && route.isComplete(checkedIn: checkins.checkedInIDs) ? route.title : nil
                }
                celebration = Celebration(outcome: outcome, completedTour: completedTour)
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

/// Colours for the hunt screens, which are always dark. The fixed ones are the Expo app's;
/// the surface is the theme's, so the hunt sits on the same navy as the rest of the app.
enum HuntPalette {
    static let green = Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)
    static let red = Color(red: 0xE7 / 255, green: 0x4C / 255, blue: 0x3C / 255)
    static let needle = Color(red: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255)
    static let surface = Theme.surface
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
