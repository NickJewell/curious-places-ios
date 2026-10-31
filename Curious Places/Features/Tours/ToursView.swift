//
//  ToursView.swift
//  Curious Places
//

import SwiftUI

/// The Tours tab: official tours and the user's saved lists (the Expo ListsScreen).
struct ToursView: View {
    enum Page: String, CaseIterable, Identifiable {
        case tours = "Official Tours"
        case lists = "My Lists"

        var id: String { rawValue }
    }

    let service: ListService
    @Environment(SessionStore.self) private var session
    @Environment(ListStore.self) private var lists
    @Environment(CheckinStore.self) private var checkins
    @SceneStorage("toursPage") private var page = Page.tours
    @State private var catalog: TourCatalog
    @State private var showsNewList = false
    @State private var errorMessage: String?

    init(service: ListService) {
        self.service = service
        _catalog = State(initialValue: TourCatalog(service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .tours: TourListView(catalog: catalog, reload: loadTours)
                case .lists: MyListsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundRoot)
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $page) {
                    ForEach(Page.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                // Only behind the picker: the default spreads into the top safe area, over the large title.
                .background(Theme.backgroundRoot, ignoresSafeAreaEdges: [])
            }
            .navigationTitle("Tours")
            .toolbar {
                if page == .lists && session.status == .signedIn {
                    Button("New List", systemImage: "plus") { showsNewList = true }
                }
            }
            .navigationDestination(for: Tour.self) { tour in
                TourDetailView(tour: tour, isCompleted: catalog.completed.contains(tour.id), service: service)
            }
            .navigationDestination(for: PlaceList.self) { list in
                ListDetailView(list: list)
            }
            .listNameAlert("New List", isPresented: $showsNewList, actionTitle: "Create") { name in
                Task {
                    do {
                        try await lists.create(named: name)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Couldn't create the list", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task(id: signedInUserID) { await loadTours() }
        // A check-in can complete a tour.
        .onChange(of: checkins.checkins.count) { Task { await loadTours() } }
    }

    private var signedInUserID: UUID? {
        session.status == .signedIn ? session.userID : nil
    }

    private func loadTours() async {
        await catalog.load(userID: signedInUserID)
    }
}
