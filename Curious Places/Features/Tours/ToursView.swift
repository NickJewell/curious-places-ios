//
//  ToursView.swift
//  Curious Places
//

import SwiftUI

/// Placeholder until tours and lists are ported.
struct ToursView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Tours are on the way",
                systemImage: "figure.walk",
                description: Text("Curated walking tours and your saved lists will appear here.")
            )
            .navigationTitle("Tours")
        }
    }
}
