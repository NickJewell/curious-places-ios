//
//  HuntStore.swift
//  Curious Places
//

import Observation

/// The hunt in progress, shared across tabs (the Expo app's HuntContext).
/// The compass can be put away while the hunt carries on; the map then offers
/// "Resume Compass". The model lives here, so arrival and the smoothed heading
/// survive that; its sensors run only while the compass is on screen.
@Observable
final class HuntStore {
    private(set) var model: HuntModel?
    var isCompassPresented = false

    var target: Place? { model?.target }
    var isHunting: Bool { model != nil }

    /// Sets the target without opening the compass, so the map can show it first.
    func begin(_ place: Place) {
        guard model?.target.id != place.id else { return }
        model = HuntModel(target: place)
    }

    func resume() {
        isCompassPresented = model != nil
    }

    func end() {
        isCompassPresented = false
        model = nil
    }
}
