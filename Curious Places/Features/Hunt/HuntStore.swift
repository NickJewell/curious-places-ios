//
//  HuntStore.swift
//  Curious Places
//

import Foundation
import Observation

/// The hunt in progress, shared across tabs (the Expo app's HuntContext).
/// The compass can be put away while the hunt carries on; the map then offers
/// "Resume Compass". The model lives here, so arrival and the smoothed heading
/// survive that; its sensors run only while the compass is on screen.
///
/// A hunt can be one place, or one stop of a route (a tour or a saved list)
/// that moves on to the next stop.
@Observable
final class HuntStore {
    private(set) var model: HuntModel?
    private(set) var route: HuntRoute?
    var isCompassPresented = false

    var target: Place? { model?.target }
    var isHunting: Bool { model != nil }

    /// Sets the target without opening the compass, so the map can show it first.
    func begin(_ place: Place) {
        guard model?.target.id != place.id || route != nil else { return }
        route = nil
        model = HuntModel(target: place)
    }

    /// Starts a route at its current stop and opens the compass.
    func begin(_ route: HuntRoute) {
        self.route = route
        model = HuntModel(target: route.current)
        isCompassPresented = true
    }

    /// Moves on to the route's next stop, keeping the compass open.
    func advance() {
        guard var route, route.next != nil else { return }
        route.index += 1
        self.route = route
        model = HuntModel(target: route.current)
    }

    func resume() {
        isCompassPresented = model != nil
    }

    func end() {
        isCompassPresented = false
        model = nil
        route = nil
    }
}

/// The stops of a tour or saved list, walked in order.
nonisolated struct HuntRoute: Sendable {
    /// The tour's or list's id.
    let id: UUID
    let title: String
    /// Official tours are marked complete by the database once every stop is checked in.
    let isTour: Bool
    let stops: [Place]
    var index: Int

    init(id: UUID, title: String, isTour: Bool, stops: [Place], startingAt index: Int = 0) {
        precondition(stops.indices.contains(index), "A route starts at one of its stops")
        self.id = id
        self.title = title
        self.isTour = isTour
        self.stops = stops
        self.index = index
    }

    var current: Place { stops[index] }
    var next: Place? { stops.indices.contains(index + 1) ? stops[index + 1] : nil }
    var progress: String { "Stop \(index + 1) of \(stops.count)" }

    /// Whether every stop is in `checkedIn`, which is when the database records a tour as complete.
    func isComplete(checkedIn: Set<String>) -> Bool {
        stops.allSatisfy { checkedIn.contains($0.id) }
    }

    /// The first stop not yet checked in, or the first stop if all are.
    static func startIndex(of stops: [Place], checkedIn: Set<String>) -> Int {
        stops.firstIndex { !checkedIn.contains($0.id) } ?? 0
    }
}
