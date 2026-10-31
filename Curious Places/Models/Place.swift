//
//  Place.swift
//  Curious Places
//

import CoreLocation

/// A curio from the `places` table. Identified by `curio_id` ("CURIO-<n>").
nonisolated struct Place: Identifiable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// English description (`detail_overview`).
    let overview: String?
    /// Description in the language the place was fetched for, if a translation exists.
    let translatedOverview: String?
    let language: AppLanguage
    let attributes: PlaceAttributes?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The translated description when there is one, otherwise English.
    var overviewText: String {
        if let translatedOverview, !translatedOverview.isEmpty { return translatedOverview }
        return overview ?? ""
    }

    /// Whether `overviewText` is actually in `language` (and so may need right-to-left layout).
    var isShowingTranslation: Bool {
        !(translatedOverview ?? "").isEmpty
    }

    var category: PlaceCategory {
        PlaceCategory(setting: attributes?.physical?.setting)
    }
}

extension Place: Equatable, Hashable {
    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id && lhs.language == rhs.language }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The subset of the `places.attributes` JSONB that the app uses. Unknown keys are ignored.
nonisolated struct PlaceAttributes: Decodable, Sendable {
    struct Physical: Decodable, Sendable {
        let setting: String?
    }

    let physical: Physical?
}

/// Map filter groups, based on `attributes.physical.setting` (MapScreen.tsx:63-65 in the Expo app).
nonisolated enum PlaceCategory: String, CaseIterable, Sendable {
    case open
    case landmark
    case built
    case other

    init(setting: String?) {
        switch setting {
        case "public_space":
            self = .open
        case "monument_or_memorial", "church_or_religious", "civic_or_institutional",
             "ruins_or_remnants", "cultural_venue":
            self = .landmark
        case "residential", "street_or_passage", "infrastructure", "commercial":
            self = .built
        default:
            self = .other
        }
    }
}

/// One row of `places` as PostgREST returns it. Only `curio_id` is guaranteed.
nonisolated struct PlaceRow: Decodable, Sendable {
    let curioID: String
    let name: String?
    let lat: Double?
    let lon: Double?
    let overview: String?
    let translations: [AppLanguage: String]
    let attributes: PlaceAttributes?

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        curioID = try container.decode(String.self, forKey: Key("curio_id"))
        name = try container.decodeIfPresent(String.self, forKey: Key("name"))
        lat = Self.decodeNumber(container, Key("lat"))
        lon = Self.decodeNumber(container, Key("lon"))
        overview = try container.decodeIfPresent(String.self, forKey: Key("detail_overview"))

        var translations: [AppLanguage: String] = [:]
        for language in AppLanguage.allCases {
            guard let column = language.overviewColumn,
                  let text = try container.decodeIfPresent(String.self, forKey: Key(column)),
                  !text.isEmpty else { continue }
            translations[language] = text
        }
        self.translations = translations

        // A malformed attributes blob shouldn't drop the whole place.
        attributes = try? container.decodeIfPresent(PlaceAttributes.self, forKey: Key("attributes"))
    }

    /// `lat`/`lon` are numeric columns; PostgREST may send numeric values as strings.
    private static func decodeNumber(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    /// Nil when the row has no usable coordinates.
    func place(in language: AppLanguage) -> Place? {
        guard let lat, let lon else { return nil }
        return Place(
            id: curioID,
            name: name ?? "Unknown",
            latitude: lat,
            longitude: lon,
            overview: overview,
            translatedOverview: translations[language],
            language: language,
            attributes: attributes
        )
    }
}
