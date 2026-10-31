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
