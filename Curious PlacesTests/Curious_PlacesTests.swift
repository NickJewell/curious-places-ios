//
//  Curious_PlacesTests.swift
//  Curious PlacesTests
//
//  Created by Nick Jewell on 31/10/2026.
//

import Foundation
import MapKit
import Testing
@testable import Curious_Places

struct PlaceRowTests {
    private func decode(_ json: String) throws -> PlaceRow {
        try JSONDecoder().decode(PlaceRow.self, from: Data(json.utf8))
    }

    @Test func decodesViewportRow() throws {
        let row = try decode("""
        {"curio_id":"CURIO-42","name":"Cleopatra's Needle","lat":51.5085,"lon":-0.1204,
         "detail_overview":"An obelisk.","fr_detail_overview":"Un obélisque.",
         "attributes":{"physical":{"setting":"monument_or_memorial","weather_dependent":true}}}
        """)
        let place = try #require(row.place(in: .french))
        #expect(place.id == "CURIO-42")
        #expect(place.overviewText == "Un obélisque.")
        #expect(place.isShowingTranslation)
        #expect(place.category == .landmark)
    }

    @Test func fallsBackToEnglishWhenTranslationMissingOrEmpty() throws {
        let row = try decode("""
        {"curio_id":"CURIO-1","name":"A","lat":51.5,"lon":-0.1,"detail_overview":"English text","de_detail_overview":""}
        """)
        let place = try #require(row.place(in: .german))
        #expect(place.overviewText == "English text")
        #expect(!place.isShowingTranslation)
    }

    @Test func acceptsNumericStringsAndDropsRowsWithoutCoordinates() throws {
        let stringCoords = try decode(#"{"curio_id":"CURIO-2","lat":"51.5","lon":"-0.12"}"#)
        #expect(stringCoords.place(in: .english)?.latitude == 51.5)

        let noCoords = try decode(#"{"curio_id":"CURIO-3","name":"Nowhere","lat":null,"lon":null}"#)
        #expect(noCoords.place(in: .english) == nil)
    }

    @Test func malformedAttributesDoNotDropThePlace() throws {
        let row = try decode(#"{"curio_id":"CURIO-4","lat":51.5,"lon":-0.1,"attributes":"not an object"}"#)
        let place = try #require(row.place(in: .english))
        #expect(place.attributes == nil)
        #expect(place.category == .other)
    }

    @Test func selectsOnlyKnownColumns() {
        #expect(PlaceService.columns(for: .english) == "curio_id,name,lat,lon,detail_overview,attributes")
        #expect(PlaceService.columns(for: .arabic).hasSuffix(",ar_detail_overview"))
    }
}

struct AppLanguageTests {
    @Test func picksFirstSupportedDeviceLanguage() {
        #expect(AppLanguage.deviceDefault(preferredLanguages: ["nl-NL", "fr-BE", "en-GB"]) == .french)
        #expect(AppLanguage.deviceDefault(preferredLanguages: ["zh-Hans-CN"]) == .chinese)
        #expect(AppLanguage.deviceDefault(preferredLanguages: ["nl-NL"]) == .english)
    }

    @Test func englishUsesTheBaseColumn() {
        #expect(AppLanguage.english.overviewColumn == nil)
        #expect(AppLanguage.korean.overviewColumn == "ko_detail_overview")
    }
}

struct BoundingBoxTests {
    @Test func bufferGrowsEachSideByAFractionOfTheSpan() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.04)
        )
        let box = BoundingBox(region: region, buffer: 0.3)
        #expect(abs(box.minLatitude - 51.484) < 1e-9)
        #expect(abs(box.maxLatitude - 51.516) < 1e-9)
        #expect(abs(box.minLongitude - -0.132) < 1e-9)
        #expect(abs(box.maxLongitude - -0.068) < 1e-9)
        #expect(box.contains(BoundingBox(region: region)))
        #expect(!BoundingBox(region: region).contains(box))
    }
}

struct PlaceCategoryTests {
    @Test(arguments: [
        ("public_space", PlaceCategory.open),
        ("church_or_religious", .landmark),
        ("street_or_passage", .built),
        ("something_new", .other),
    ])
    func mapsSettingToCategory(setting: String, expected: PlaceCategory) {
        #expect(PlaceCategory(setting: setting) == expected)
    }
}

struct AdminAccessTests {
    @Test func adminFlagGrantsAccess() {
        #expect(AdminAccess.isAdmin(adminFlag: true, email: nil, emailVerified: false))
    }

    @Test func nicksVerifiedEmailIsAdminWhateverTheCase() {
        #expect(AdminAccess.isAdmin(adminFlag: nil, email: "Nick.Jewell@gmail.com", emailVerified: true))
        #expect(AdminAccess.isAdmin(adminFlag: false, email: "nick.jewell@gmail.com", emailVerified: true))
    }

    @Test func unverifiedOrOtherEmailsAreNotAdmin() {
        #expect(!AdminAccess.isAdmin(adminFlag: nil, email: "nick.jewell@gmail.com", emailVerified: false))
        #expect(!AdminAccess.isAdmin(adminFlag: false, email: "someone@example.com", emailVerified: true))
        #expect(!AdminAccess.isAdmin(adminFlag: nil, email: "abc123@privaterelay.appleid.com", emailVerified: true))
    }
}

struct LanguageSyncTests {
    @Test func profileChoiceWinsOverDevice() {
        #expect(LanguageSync.reconcile(remote: "fr", local: .german) == .useRemote(.french))
        #expect(LanguageSync.reconcile(remote: "fr", local: .french) == .none)
    }

    @Test func nullProfileTakesTheDevicesNonEnglishChoice() {
        #expect(LanguageSync.reconcile(remote: nil, local: .japanese) == .pushLocal(.japanese))
        #expect(LanguageSync.reconcile(remote: nil, local: .english) == .none)
    }

    @Test func englishIsStoredAsNull() {
        #expect(LanguageSync.remoteValue(for: .english) == nil)
        #expect(LanguageSync.remoteValue(for: .arabic) == "ar")
    }

    @Test func languageWriteEncodesExplicitNull() throws {
        let data = try JSONEncoder().encode(LanguageWrite(preferredLanguage: nil))
        #expect(String(decoding: data, as: UTF8.self) == #"{"preferred_language":null}"#)
    }
}

struct AppleSignInNonceTests {
    @Test func nonceHasRequestedLengthAndVaries() {
        let a = AppleSignInNonce.make()
        #expect(a.count == 32)
        #expect(a != AppleSignInNonce.make())
    }

    @Test func hashIsLowercaseHexSHA256() {
        #expect(AppleSignInNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

struct ProfileDecodingTests {
    @Test func decodesFullRowAndIgnoresExtraColumns() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","email":"a@b.com","full_name":"Ada",
         "avatar_url":null,"admin_flag":true,"preferred_language":"ja","created_at":"2026-01-01"}
        """
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(profile.fullName == "Ada")
        #expect(profile.adminFlag == true)
        #expect(profile.preferredLanguage == "ja")
    }

    @Test func decodesRowMissingOptionalColumns() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(profile.adminFlag == nil)
        #expect(profile.preferredLanguage == nil)
    }
}

struct NarrationLocatorTests {
    private let base = URL(string: "https://example.supabase.co")!

    @Test func triesLanguageThenEnglishThenLegacy() {
        let paths = NarrationLocator.candidates(curioID: "CURIO-41", language: .french, baseURL: base)
            .map(\.url.absoluteString)
        #expect(paths == [
            "https://example.supabase.co/storage/v1/object/public/fr_audio/fr_curio_41_detail_overview.mp3",
            "https://example.supabase.co/storage/v1/object/public/en_audio/en_curio_41_detail_overview.mp3",
            "https://example.supabase.co/storage/v1/object/public/audio_overviews_1_1000/1-100/curio_detail_41.mp3",
        ])
    }

    @Test func englishSkipsTheLanguageBucket() {
        let tracks = NarrationLocator.candidates(curioID: "CURIO-7", language: .english, baseURL: base)
        #expect(tracks.count == 2)
        #expect(tracks.allSatisfy { $0.language == .english })
    }

    @Test(arguments: [
        (1, "audio_overviews_1_1000", "1-100"),
        (100, "audio_overviews_1_1000", "1-100"),
        (101, "audio_overviews_1_1000", "101-200"),
        (1000, "audio_overviews_1_1000", "901-1000"),
        (1001, "audio_overviews_1001_2000", "1001-1100"),
    ])
    func legacyBucketsHold1000AndFoldersHold100(number: Int, bucket: String, folder: String) {
        let location = NarrationLocator.legacyFolder(number: number)
        #expect(location.bucket == bucket)
        #expect(location.folder == folder)
    }

    @Test func factAudioUsesPaddedPositionThenLegacyFactID() {
        let fact = Fact(id: "abc-123", curioID: "CURIO-141", text: "A fact.", language: .english, position: 3)
        #expect(NarrationLocator.factCandidates(for: fact, baseURL: base).map(\.absoluteString) == [
            "https://example.supabase.co/storage/v1/object/public/en_audio/en_curio_141_fact_03_v2.mp3",
            "https://example.supabase.co/storage/v1/object/public/audio_overviews_1_1000/101-200/curio_141_abc-123.mp3",
        ])
        let tenth = Fact(id: "x", curioID: "CURIO-1", text: "A fact.", language: .english, position: 10)
        #expect(NarrationLocator.factCandidates(for: tenth, baseURL: base).first?.lastPathComponent
            == "en_curio_1_fact_10_v2.mp3")
    }

    @Test func factWithoutPositionIsKeyedByID() {
        let fact = Fact(id: "abc-123", curioID: "CURIO-5970", text: "A fact.", language: .english, position: nil)
        #expect(NarrationLocator.factCandidates(for: fact, baseURL: base).first?.lastPathComponent
            == "en_curio_5970_fact_abc-123.mp3")
    }

    @Test func nonEnglishFactsHaveNoAudio() {
        let fact = Fact(id: "x", curioID: "CURIO-1", text: "Un fait.", language: .french, position: 1)
        #expect(NarrationLocator.factCandidates(for: fact, baseURL: base).isEmpty)
    }

    @Test func parsesTrailingNumberOnly() {
        #expect(NarrationLocator.curioNumber("CURIO-1234") == 1234)
        #expect(NarrationLocator.curioNumber("no-number") == nil)
        #expect(NarrationLocator.candidates(curioID: "bad", language: .english, baseURL: base).isEmpty)
    }
}

struct FactTests {
    private func rows(_ json: String) throws -> [FactRow] {
        try JSONDecoder().decode([FactRow].self, from: Data(json.utf8))
    }

    @Test func positionsCountEveryRowBeforeFiltering() throws {
        let facts = FactRow.facts(from: try rows("""
        [{"id":"a","curio_id":"CURIO-1","fact_info":"First","language_code":"en","created_at":"2025-01-01T00:00:01"},
         {"id":"b","curio_id":"CURIO-1","fact_info":"Premier","language_code":"fr","created_at":"2025-01-01T00:00:02"},
         {"id":"c","curio_id":"CURIO-1","fact_info":"","language_code":"en","created_at":"2025-01-01T00:00:03"},
         {"id":"d","curio_id":"CURIO-1","fact_info":"Fourth","language_code":null,"created_at":"2025-01-01T00:00:04"}]
        """))
        #expect(facts.map(\.id) == ["a", "b", "d"])
        #expect(facts.map(\.position) == [1, 2, 4])
        #expect(facts.last?.language == .english)
    }

    @Test func tiedTimestampsHaveNoPositionAndUppercaseCodesAreEnglish() throws {
        let facts = FactRow.facts(from: try rows("""
        [{"id":"a","curio_id":"CURIO-1","fact_info":"One","language_code":"EN","created_at":"2025-01-01T00:00:00"},
         {"id":"b","curio_id":"CURIO-1","fact_info":"Two","language_code":"en","created_at":"2025-01-01T00:00:00"},
         {"id":"c","curio_id":"CURIO-1","fact_info":"Three","language_code":"en","created_at":"2025-01-02T00:00:00"}]
        """))
        #expect(facts.map(\.position) == [nil, nil, 3])
        #expect(facts.allSatisfy { $0.language == .english })
    }

    @Test func showsFactsInTheLanguageOrFallsBackToEnglish() {
        let facts = [
            Fact(id: "a", curioID: "CURIO-1", text: "One", language: .english, position: 1),
            Fact(id: "b", curioID: "CURIO-1", text: "Un", language: .french, position: 2),
        ]
        #expect(Fact.displayed(facts, in: .french).map(\.id) == ["b"])
        #expect(Fact.displayed(facts, in: .german).map(\.id) == ["a"])
        #expect(Fact.displayed(facts, in: .english).map(\.id) == ["a"])
    }

    @Test func stripsLinks() {
        #expect(Fact.stripURLs("Built in 1666 (see https://example.com/a?b=c) by Wren.  ")
            == "Built in 1666 (see ) by Wren.")
        #expect(Fact.stripURLs("HTTP://EXAMPLE.COM only") == "only")
    }

    @Test func deckShowsEveryFactOnceBeforeRepeating() {
        let facts = (1...5).map { Fact(id: "\($0)", curioID: "CURIO-1", text: "F\($0)", language: .english, position: $0) }
        var deck = FactDeck(facts)
        let firstRound = (0..<5).compactMap { _ in deck.next()?.id }
        #expect(Set(firstRound).count == 5)
        let afterRound = deck.next()
        #expect(afterRound != nil)
        var empty = FactDeck([])
        let none = empty.next()
        #expect(none == nil)
    }
}

struct IssueReportTests {
    private func json(_ report: IssueReport) throws -> [String: String] {
        let data = try JSONEncoder().encode(report)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    @Test func otherKeepsATrimmedCappedDescription() throws {
        let long = "  " + String(repeating: "x", count: 250) + "  "
        let report = IssueReport(source: .place("CURIO-9"), issueType: .other, description: long, userID: nil)
        let body = try json(report)
        #expect(body["source_id"] == "CURIO-9")
        #expect(body["source_type"] == "place")
        #expect(body["issue_type"] == "other")
        #expect(body["other_desc"]?.count == IssueReport.maxDescriptionLength)
        #expect(body["user_id"] == nil)
    }

    @Test func otherReasonsDropTheDescription() throws {
        let user = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        let report = IssueReport(source: .fact("f-1"), issueType: .badAudio, description: "ignored", userID: user)
        let body = try json(report)
        #expect(body["source_type"] == "fact")
        #expect(body["issue_type"] == "bad_audio")
        #expect(body["other_desc"] == nil)
        #expect(body["user_id"] == user.uuidString)
    }
}

struct HuntMathTests {
    @Test func circularMeanTakesTheShortWayAcrossNorth() {
        // Halfway between 350° and 10° is 0°, not 180°.
        #expect(abs(HuntMath.circularMean(350, 10, factor: 0.5)) < 1e-9
                || abs(HuntMath.circularMean(350, 10, factor: 0.5) - 360) < 1e-9)
        // A vector mean, not a linear one: atan2(0.8, -0.2) = 104.04°.
        #expect(abs(HuntMath.circularMean(90, 180, factor: 0.2) - 104.04) < 0.01)
    }

    @Test func unwrappingKeepsAccumulatedTurnsAndNeverJumpsMoreThanHalfATurn() {
        #expect(HuntMath.unwrapped(5, from: 355) == 365)
        #expect(HuntMath.unwrapped(355, from: 365) == 355)
        #expect(HuntMath.unwrapped(-10, from: 720) == 710)
        #expect(HuntMath.unwrapped(180, from: 0) == 180)
    }

    @Test func bearingAndCardinal() {
        let origin = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)
        let north = CLLocationCoordinate2D(latitude: 51.6, longitude: -0.12)
        let east = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.02)
        #expect(abs(HuntMath.bearing(from: origin, to: north)) < 0.01)
        #expect(abs(HuntMath.bearing(from: origin, to: east) - 90) < 0.1)
        #expect(HuntMath.cardinal(0) == "N")
        #expect(HuntMath.cardinal(359) == "N")
        #expect(HuntMath.cardinal(22.4) == "N")
        #expect(HuntMath.cardinal(22.6) == "NE")
        #expect(HuntMath.cardinal(-90) == "W")
    }

    @Test func coordinatesAndDistancesFormatLikeTheExpoApp() {
        #expect(HuntMath.formatted(51.5075, isLatitude: true) == "N 51° 30.450'")
        #expect(HuntMath.formatted(-0.1278, isLatitude: false) == "W 0° 7.668'")
        #expect(HuntMath.formattedDistance(42.4) == "42 m")
        #expect(HuntMath.formattedDistance(1234) == "1.2 km")
    }

    @Test func pulseSpeedsUpOverFourTiers() {
        #expect(HuntMath.pulseDuration(distance: 2000) == 2)
        #expect(HuntMath.pulseDuration(distance: 30) == 0.4)
        #expect(abs(HuntMath.pulseDuration(distance: 525) - 1.2) < 1e-9)
        #expect([1200.0, 700, 300, 100, 20].map { HuntMath.pulseTier(distance: $0) } == [0, 1, 2, 3, 4])
    }
}

struct HuntProgressTests {
    @Test func checkInNeedsAnAccurateFixWithin40Metres() {
        var progress = HuntProgress()
        progress.update(distance: 30, accuracy: 50)
        #expect(progress.distance == 30)
        #expect(!progress.canCheckIn)

        progress.update(distance: 30, accuracy: 15)
        #expect(progress.canCheckIn)
        #expect(!progress.hasArrived)

        progress.update(distance: 45, accuracy: 15)
        #expect(!progress.canCheckIn)
    }

    @Test func invalidAccuracyDoesNotCount() {
        var progress = HuntProgress()
        progress.update(distance: 5, accuracy: -1)
        #expect(!progress.canCheckIn)
        #expect(!progress.hasArrived)
    }

    @Test func arrivalUnder10MetresSticks() {
        var progress = HuntProgress()
        progress.update(distance: 8, accuracy: 10)
        #expect(progress.hasArrived)
        progress.update(distance: 80, accuracy: 10)
        #expect(progress.hasArrived)
        #expect(!progress.canCheckIn)
    }
}

struct RouteGeometryTests {
    /// An L-shaped route near St Paul's: 200 m east, then 100 m north.
    private let corner = MKMapPoint(CLLocationCoordinate2D(latitude: 51.5138, longitude: -0.0984))
    private var path: [MKMapPoint] {
        let perMetre = 1 / MKMetersPerMapPointAtLatitude(51.5138)
        let east = MKMapPoint(x: corner.x - 200 * perMetre, y: corner.y)
        let north = MKMapPoint(x: corner.x, y: corner.y - 100 * perMetre)
        return [east, corner, north]
    }
    private func offset(_ point: MKMapPoint, east: Double = 0, north: Double = 0) -> MKMapPoint {
        let perMetre = 1 / MKMetersPerMapPointAtLatitude(51.5138)
        return MKMapPoint(x: point.x + east * perMetre, y: point.y - north * perMetre)
    }

    @Test func onTheRouteAtTheStartTheWholeRouteRemains() throws {
        let progress = try #require(RouteGeometry.progress(of: path[0], along: path))
        #expect(progress.offRouteDistance < 0.5)
        #expect(abs(progress.remainingDistance - 300) < 1)
    }

    @Test func besideTheRouteCountsTheSideStepAndTheRestOfTheRoute() throws {
        // 20 m south of the first leg, halfway along it.
        let point = offset(path[0], east: 100, north: -20)
        let progress = try #require(RouteGeometry.progress(of: point, along: path))
        #expect(abs(progress.offRouteDistance - 20) < 0.5)
        #expect(abs(progress.remainingDistance - 200) < 1)
    }

    @Test func onTheSecondLegOnlyItsRestRemains() throws {
        let point = offset(corner, north: 60)
        let progress = try #require(RouteGeometry.progress(of: point, along: path))
        #expect(progress.offRouteDistance < 0.5)
        #expect(abs(progress.remainingDistance - 40) < 1)
    }

    @Test func pastTheEndNothingRemains() throws {
        let point = offset(path[2], north: 25)
        let progress = try #require(RouteGeometry.progress(of: point, along: path))
        #expect(abs(progress.offRouteDistance - 25) < 0.5)
        #expect(progress.remainingDistance < 0.5)
    }

    @Test func emptyAndSinglePointPaths() throws {
        #expect(RouteGeometry.progress(of: corner, along: []) == nil)
        let single = try #require(RouteGeometry.progress(of: offset(corner, east: 10), along: [corner]))
        #expect(abs(single.offRouteDistance - 10) < 0.5)
        #expect(single.remainingDistance == 0)
    }

    @Test func remainingTimeUsesTheRoutesOwnPace() {
        #expect(RouteGeometry.remainingTime(400, routeDistance: 800, routeTime: 600) == 300)
        #expect(RouteGeometry.remainingTime(400, routeDistance: 0, routeTime: 600) == nil)
    }

    @Test func walkingTimeRoundsUpToWholeMinutes() {
        #expect(RouteGeometry.walkingMinutes(1021) == 18)
        #expect(RouteGeometry.formattedWalkingTime(5) == "1 min")
        #expect(RouteGeometry.formattedWalkingTime(61) == "2 min")
        #expect(RouteGeometry.formattedWalkingTime(720) == "12 min")
        #expect(RouteGeometry.formattedWalkingTime(3600) == "1 h")
        #expect(RouteGeometry.formattedWalkingTime(3900) == "1 h 5 min")
    }
}

struct RoutePolicyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func firstRouteNeedsOnlyARoughFixAndATargetFurtherThan75Metres() {
        let policy = RoutePolicy()
        #expect(policy.shouldRequest(distanceToTarget: 500, accuracy: 65, offRoute: nil, now: start))
        #expect(!policy.shouldRequest(distanceToTarget: 500, accuracy: 150, offRoute: nil, now: start))
        #expect(!policy.shouldRequest(distanceToTarget: 500, accuracy: -1, offRoute: nil, now: start))
        #expect(!policy.shouldRequest(distanceToTarget: 60, accuracy: 10, offRoute: nil, now: start))
    }

    @Test func reroutesOnlyWhenMoreThan30MetresOffOnAnAccurateFix() {
        let policy = RoutePolicy()
        let later = start.addingTimeInterval(60)
        #expect(!policy.shouldRequest(distanceToTarget: 500, accuracy: 10, offRoute: 25, now: later))
        #expect(policy.shouldRequest(distanceToTarget: 500, accuracy: 10, offRoute: 35, now: later))
        #expect(!policy.shouldRequest(distanceToTarget: 500, accuracy: 40, offRoute: 35, now: later))
    }

    @Test func requestsAreAtLeast20SecondsApart() {
        var policy = RoutePolicy()
        policy.didRequest(at: start)
        #expect(!policy.shouldRequest(distanceToTarget: 500, accuracy: 10, offRoute: 50, now: start.addingTimeInterval(19)))
        #expect(policy.shouldRequest(distanceToTarget: 500, accuracy: 10, offRoute: 50, now: start.addingTimeInterval(21)))
    }

    @Test func aFailureBacksOffForAMinute() {
        var policy = RoutePolicy()
        policy.didRequest(at: start)
        policy.didFail(at: start)
        #expect(!policy.shouldRequest(distanceToTarget: 500, accuracy: 10, offRoute: nil, now: start.addingTimeInterval(59)))
        #expect(policy.shouldRequest(distanceToTarget: 500, accuracy: 10, offRoute: nil, now: start.addingTimeInterval(61)))
    }

    @Test func stopsAfter15RequestsPerStop() {
        var policy = RoutePolicy()
        for minute in 0..<15 {
            policy.didRequest(at: start.addingTimeInterval(Double(minute) * 60))
        }
        #expect(!policy.shouldRequest(distanceToTarget: 500, accuracy: 10, offRoute: 100, now: start.addingTimeInterval(3600)))
    }
}

struct CheckinModelTests {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func badge(_ name: String, icon: String = "award") -> Badge {
        Badge(id: UUID(), name: name, description: "", iconName: icon,
              requirementType: "checkin_count", requirementValue: 1)
    }

    @Test func decodesCheckinRow() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","place_id":"CURIO-7","place_name":"Crossbones",
         "place_latitude":51.503,"place_longitude":-0.093,"checked_in_at":"2026-10-31T12:00:00Z"}
        """
        let checkin = try decoder.decode(Checkin.self, from: Data(json.utf8))
        #expect(checkin.placeID == "CURIO-7")
        #expect(checkin.latitude == 51.503)
        #expect(checkin.checkedInAt != nil)
    }

    @Test func writeUsesTheAuthUserAndPlaceSnapshot() throws {
        let user = UUID()
        let place = Place(id: "CURIO-7", name: "Crossbones", latitude: 51.503, longitude: -0.093,
                          overview: nil, translatedOverview: nil, language: .english, attributes: nil)
        let data = try JSONEncoder().encode(CheckinWrite(place: place, userID: user))
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["user_id"] as? String == user.uuidString)
        #expect(body["place_id"] as? String == "CURIO-7")
        #expect(body["place_name"] as? String == "Crossbones")
        #expect(body["place_latitude"] as? Double == 51.503)
        #expect(Set(body.keys) == ["user_id", "place_id", "place_name", "place_latitude", "place_longitude"])
    }

    @Test func newBadgesAreTheDifferenceInCatalogOrder() {
        let explorer = badge("The Explorer"), wanderer = badge("The Wanderer"), legend = badge("The Legend")
        let catalog = [explorer, wanderer, legend]
        let new = CheckinOutcome.newBadges(catalog: catalog, before: [explorer.id],
                                           after: [legend.id, explorer.id, wanderer.id])
        #expect(new.map(\.name) == ["The Wanderer", "The Legend"])
        #expect(CheckinOutcome.newBadges(catalog: catalog, before: [explorer.id], after: [explorer.id]).isEmpty)
    }

    @Test func featherIconsMapToSymbolsWithAFallback() {
        #expect(badge("A", icon: "compass").systemImage == "safari")
        #expect(badge("A", icon: "map-pin").systemImage == "mappin.and.ellipse")
        #expect(badge("A", icon: "something-new").systemImage == "rosette")
    }

    @Test func celebrationListsOnlyRealOutcomes() {
        let wanderer = badge("The Wanderer")
        let lines = CheckinCelebration.lines(
            placeName: "Crossbones",
            outcome: CheckinOutcome(isNew: true, totalCheckins: 5, newBadges: [wanderer])
        )
        #expect(lines.map(\.title) == [
            "First discovery of Crossbones! The mystery unfolds.",
            "5 curios discovered — you're on a roll.",
            "Badge unlocked: The Wanderer!",
        ])
        #expect(CheckinCelebration.milestone(1) == "Your very first curio discovered!")
        #expect(CheckinCelebration.milestone(30) == "30 total discoveries — remarkable.")
        #expect(CheckinCelebration.milestone(7) == "7 places visited so far.")
    }
}

struct ListModelTests {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func place(_ id: String) -> Place {
        Place(id: id, name: id, latitude: 51.5, longitude: -0.1,
              overview: nil, translatedOverview: nil, language: .english, attributes: nil)
    }

    private func row(_ placeID: String, order: Int?, created: TimeInterval = 0) -> ListItemRow {
        ListItemRow(id: UUID(), listID: UUID(), placeID: placeID, orderIndex: order,
                    createdAt: Date(timeIntervalSince1970: created))
    }

    @Test func decodesLiveListItemRow() throws {
        let json = """
        {"list_item_uuid":"6F9619FF-8B86-D011-B42D-00C04FC964FF","list_uuid":"11111111-0000-0000-0000-000000000001",
         "place_id":"CURIO-7","order_index":3,"created_at":"2026-10-31T12:00:00Z"}
        """
        let row = try decoder.decode(ListItemRow.self, from: Data(json.utf8))
        #expect(row.placeID == "CURIO-7")
        #expect(row.orderIndex == 3)
        #expect(row.listID?.uuidString == "11111111-0000-0000-0000-000000000001")
    }

    @Test func itemWriteSetsBothListKeysWithLowercaseText() throws {
        let list = try #require(UUID(uuidString: "ABCDEF00-0000-0000-0000-000000000001"))
        let data = try JSONEncoder().encode(ListItemWrite(listID: list, placeID: "CURIO-7", orderIndex: 2))
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // The insert policy in proposed/07 requires list_id = list_uuid::text, which Postgres writes in lowercase.
        #expect(body["list_id"] as? String == "abcdef00-0000-0000-0000-000000000001")
        #expect(body["list_uuid"] as? String == list.uuidString)
        #expect(body["order_index"] as? Int == 2)
    }

    @Test func itemsOrderByIndexThenAgeWithUnindexedLast() {
        let rows = [row("C", order: nil), row("B", order: 2), row("A", order: 1, created: 5), row("A2", order: 1, created: 1)]
        #expect(ListItemRow.ordered(rows).map(\.placeID) == ["A2", "A", "B", "C"])
    }

    @Test func entriesDropHiddenPlacesAndKeepOrder() {
        let rows = [row("CURIO-2", order: 2), row("CURIO-9", order: 1), row("CURIO-1", order: 3)]
        let entries = ListEntry.entries(rows: rows, places: [place("CURIO-1"), place("CURIO-2")])
        #expect(entries.map(\.place.id) == ["CURIO-2", "CURIO-1"])
    }

    @Test func toursGroupByRegionWithOtherLast() throws {
        let json = """
        [{"id":"11111111-0000-0000-0000-000000000001","name":"A","tour_start_region":"Hackney"},
         {"id":"11111111-0000-0000-0000-000000000002","name":"B","tour_start_region":null},
         {"id":"11111111-0000-0000-0000-000000000003","name":"C","tour_start_region":"City of London","promoted_flag":true},
         {"id":"11111111-0000-0000-0000-000000000004","name":"D","tour_start_region":"Hackney"}]
        """
        let tours = try decoder.decode([Tour].self, from: Data(json.utf8))
        let groups = Tour.grouped(tours)
        #expect(groups.map(\.region) == ["City of London", "Hackney", "Other"])
        #expect(groups[1].tours.map(\.name) == ["A", "D"])
        #expect(tours.filter(\.isPromoted).map(\.name) == ["C"])
    }

    @Test func listsFromTheTableExcludeTours() throws {
        let json = """
        [{"id":"11111111-0000-0000-0000-000000000001","name":"Mine","list_type":"list"},
         {"id":"11111111-0000-0000-0000-000000000002","name":"Default","list_type":null},
         {"id":"11111111-0000-0000-0000-000000000003","name":"A tour","list_type":"tour"}]
        """
        let lists = try decoder.decode([PlaceList].self, from: Data(json.utf8))
        #expect(lists.filter { !$0.isTour }.map(\.name) == ["Mine", "Default"])
    }

    @Test func routeStartsAtFirstUnvisitedStopAndAdvances() {
        let stops = [place("CURIO-1"), place("CURIO-2"), place("CURIO-3")]
        #expect(HuntRoute.startIndex(of: stops, checkedIn: ["CURIO-1"]) == 1)
        #expect(HuntRoute.startIndex(of: stops, checkedIn: ["CURIO-1", "CURIO-2", "CURIO-3"]) == 0)

        var route = HuntRoute(id: UUID(), title: "Tour", isTour: true, stops: stops, startingAt: 1)
        #expect(route.current.id == "CURIO-2")
        #expect(route.next?.id == "CURIO-3")
        #expect(route.progress == "Stop 2 of 3")
        route.index = 2
        #expect(route.next == nil)
        #expect(!route.isComplete(checkedIn: ["CURIO-1", "CURIO-3"]))
        #expect(route.isComplete(checkedIn: ["CURIO-1", "CURIO-2", "CURIO-3", "CURIO-9"]))
    }

    @Test func huntStoreRoutesMoveOnAndASinglePlaceClearsThem() {
        let stops = [place("CURIO-1"), place("CURIO-2")]
        let hunt = HuntStore()
        hunt.begin(HuntRoute(id: UUID(), title: "Tour", isTour: true, stops: stops))
        #expect(hunt.isCompassPresented)
        #expect(hunt.target?.id == "CURIO-1")
        hunt.advance()
        #expect(hunt.target?.id == "CURIO-2")
        hunt.advance()
        #expect(hunt.target?.id == "CURIO-2")
        // Hunting the same place on its own leaves the route.
        hunt.begin(stops[1])
        #expect(hunt.route == nil)
        hunt.end()
        #expect(hunt.model == nil)
    }

    @Test func celebrationAddsTheCompletedTour() {
        let lines = CheckinCelebration.lines(
            placeName: "Crossbones",
            outcome: CheckinOutcome(isNew: true, totalCheckins: 7, newBadges: []),
            completedTour: "Hawksmoor's Spires"
        )
        #expect(lines.map(\.title).last == "Tour complete: Hawksmoor's Spires!")
    }

    @Test func coveringRegionPadsAndHasAMinimumSpan() throws {
        #expect(MKCoordinateRegion(covering: []) == nil)
        let one = try #require(MKCoordinateRegion(covering: [CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)]))
        #expect(one.span.latitudeDelta == 0.005)
        let two = try #require(MKCoordinateRegion(covering: [
            CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1),
            CLLocationCoordinate2D(latitude: 51.6, longitude: -0.3),
        ]))
        #expect(abs(two.center.latitude - 51.55) < 1e-9)
        #expect(abs(two.span.longitudeDelta - 0.26) < 1e-9)
    }
}
