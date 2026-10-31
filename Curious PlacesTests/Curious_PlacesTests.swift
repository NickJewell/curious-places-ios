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
        (1, "audio_overviews_1_1000", "1-100/curio_detail_1.mp3"),
        (100, "audio_overviews_1_1000", "1-100/curio_detail_100.mp3"),
        (101, "audio_overviews_1_1000", "101-200/curio_detail_101.mp3"),
        (1000, "audio_overviews_1_1000", "901-1000/curio_detail_1000.mp3"),
        (1001, "audio_overviews_1001_2000", "1001-1100/curio_detail_1001.mp3"),
    ])
    func legacyBucketsHold1000AndFoldersHold100(number: Int, bucket: String, path: String) {
        let location = NarrationLocator.legacyLocation(number: number)
        #expect(location.bucket == bucket)
        #expect(location.path == path)
    }

    @Test func parsesTrailingNumberOnly() {
        #expect(NarrationLocator.curioNumber("CURIO-1234") == 1234)
        #expect(NarrationLocator.curioNumber("no-number") == nil)
        #expect(NarrationLocator.candidates(curioID: "bad", language: .english, baseURL: base).isEmpty)
    }
}
