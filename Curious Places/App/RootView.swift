//
//  RootView.swift
//  Curious Places
//

import SwiftUI

struct RootView: View {
    @State private var session = SessionStore(client: supabase)
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    var body: some View {
        Group {
            switch session.status {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.backgroundRoot)
            case .signedOut:
                SignInView(allowsGuest: true)
            case .guest, .signedIn:
                MainTabView()
            }
        }
        .environment(session)
        .preferredColorScheme(appearance.colorScheme)
        .task { await session.listen() }
        .onOpenURL { url in
            Task { await session.handleOpenURL(url) }
        }
    }
}

private struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @State private var location = LocationProvider()
    @State private var narration = NarrationService()
    @State private var checkins = CheckinStore(service: CheckinService(client: supabase))
    @State private var hunt = HuntStore()
    private let placeService = PlaceService(client: supabase)

    var body: some View {
        @Bindable var hunt = hunt
        TabView {
            Tab("Explore", systemImage: "map") {
                ExploreView(service: placeService)
            }
            Tab("Tours", systemImage: "figure.walk") {
                ToursView()
            }
            Tab("Profile", systemImage: "person") {
                ProfileView()
            }
        }
        .fullScreenCover(isPresented: $hunt.isCompassPresented) {
            if let model = hunt.model {
                HuntView(model: model)
                    .id(model.target.id)
            }
        }
        .environment(location)
        .environment(narration)
        .environment(checkins)
        .environment(hunt)
        .task { await location.run() }
        // Check-ins belong to the auth user; guests have none.
        .task(id: signedInUserID) { await checkins.load(userID: signedInUserID) }
    }

    private var signedInUserID: UUID? {
        session.status == .signedIn ? session.userID : nil
    }
}
