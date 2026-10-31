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
    @State private var location = LocationProvider()
    @State private var narration = NarrationService()
    private let placeService = PlaceService(client: supabase)

    var body: some View {
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
        .environment(location)
        .environment(narration)
        .task { await location.run() }
    }
}
