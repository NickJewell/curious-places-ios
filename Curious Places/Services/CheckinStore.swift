//
//  CheckinStore.swift
//  Curious Places
//

import Foundation
import Observation

/// The signed-in user's check-ins and badges, shared by the map markers, the
/// hunt and the profile (the Expo app's CheckinContext). Empty for guests.
@Observable
final class CheckinStore {
    /// Newest first.
    private(set) var checkins: [Checkin] = []
    private(set) var checkedInIDs: Set<String> = []
    /// Every badge definition, easiest first.
    private(set) var badges: [Badge] = []
    private(set) var earned: [EarnedBadge] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false

    private let service: CheckinService
    private var userID: UUID?

    init(service: CheckinService) {
        self.service = service
    }

    func isCheckedIn(_ placeID: String) -> Bool {
        checkedInIDs.contains(placeID)
    }

    func earnedBadge(_ badge: Badge) -> EarnedBadge? {
        earned.first { $0.badgeID == badge.id }
    }

    /// Loads everything for `userID`, or clears it all when nil (guests, signed out).
    func load(userID: UUID?) async {
        self.userID = userID
        guard let userID else {
            setCheckins([])
            earned = []
            isLoading = false
            loadFailed = false
            return
        }
        isLoading = true
        defer { if self.userID == userID { isLoading = false } }
        do {
            async let checkins = service.checkins(userID: userID)
            async let earned = service.earnedBadges(userID: userID)
            async let badges = service.badges()
            let loaded = try await (checkins, earned, badges)
            // The user may have signed out or switched while this was loading.
            guard self.userID == userID else { return }
            setCheckins(loaded.0)
            self.earned = loaded.1
            self.badges = loaded.2
            loadFailed = false
        } catch {
            guard self.userID == userID, !(error is CancellationError) else { return }
            loadFailed = true
        }
    }

    func reload() async {
        await load(userID: userID)
    }

    /// Checks in, then works out which badges the database awarded for it.
    func checkIn(_ place: Place, userID: UUID) async throws -> CheckinOutcome {
        let before = Set((try? await service.earnedBadges(userID: userID))?.map(\.badgeID)
            ?? earned.map(\.badgeID))
        let isNew = try await service.checkIn(place, userID: userID)

        // Show the place as visited straight away; the refresh below fills in the real row.
        checkedInIDs.insert(place.id)
        if let rows = try? await service.checkins(userID: userID), self.userID == userID {
            setCheckins(rows)
        }
        if badges.isEmpty, let catalog = try? await service.badges() {
            badges = catalog
        }
        var newBadges: [Badge] = []
        if let after = try? await service.earnedBadges(userID: userID), self.userID == userID {
            earned = after
            newBadges = CheckinOutcome.newBadges(catalog: badges, before: before, after: Set(after.map(\.badgeID)))
        }
        return CheckinOutcome(isNew: isNew, totalCheckins: max(checkins.count, 1), newBadges: newBadges)
    }

    /// Badges are kept when a check-in is removed, as in the Expo app.
    func remove(placeID: String, userID: UUID) async throws {
        try await service.removeCheckin(placeID: placeID, userID: userID)
        guard self.userID == userID else { return }
        setCheckins(checkins.filter { $0.placeID != placeID })
    }

    private func setCheckins(_ rows: [Checkin]) {
        checkins = rows
        checkedInIDs = Set(rows.map(\.placeID))
    }
}
