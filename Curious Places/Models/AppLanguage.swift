//
//  AppLanguage.swift
//  Curious Places
//

import Foundation

/// Languages that place descriptions are translated into. English is the
/// base `detail_overview` column; the others have a `{code}_detail_overview` column.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case italian = "it"
    case chinese = "zh"
    case hindi = "hi"
    case arabic = "ar"
    case japanese = "ja"
    case portuguese = "pt"
    case korean = "ko"

    var id: String { rawValue }

    /// The `places` column holding this language's description, or nil for English.
    var overviewColumn: String? {
        self == .english ? nil : "\(rawValue)_detail_overview"
    }

    var displayName: String {
        switch self {
        case .english: "English"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .chinese: "中文"
        case .hindi: "हिन्दी"
        case .arabic: "العربية"
        case .japanese: "日本語"
        case .portuguese: "Português"
        case .korean: "한국어"
        }
    }

    var isRightToLeft: Bool { self == .arabic }

    /// The first of the user's preferred languages that we have translations for.
    static func deviceDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
            if let code, let language = AppLanguage(rawValue: code) {
                return language
            }
        }
        return .english
    }
}
