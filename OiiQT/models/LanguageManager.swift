//
//  LanguageManager.swift
//  OiiQT
//
//  Created by Codex on 2026/2/18.
//

import SwiftUI
import Combine
import Foundation

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    private static let languageStorageKey = "language"

    enum SupportedLanguage: String, CaseIterable {
        case simplifiedChinese = "zh-Hans"
        case english = "en"
    }

    @AppStorage("language") private var storedLanguageCode: String = ""
    @Published private(set) var selectedLanguage: SupportedLanguage

    private init() {
        let persistedCode = UserDefaults.standard.string(forKey: Self.languageStorageKey)
        let initialLanguage = persistedCode
            .flatMap(SupportedLanguage.init(rawValue:))
            ?? Self.defaultLanguageFromSystem()
        selectedLanguage = initialLanguage
        storedLanguageCode = initialLanguage.rawValue
    }

    var languageCodeBinding: Binding<String> {
        Binding(
            get: { self.selectedLanguage.rawValue },
            set: { self.setLanguage(code: $0) }
        )
    }

    var currentLocale: Locale {
        Locale(identifier: selectedLanguage.rawValue)
    }

    private var languageBundle: Bundle {
        guard
            let path = Bundle.main.path(forResource: selectedLanguage.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return .main
        }
        return bundle
    }

    func localized(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: languageBundle, value: key, comment: "")
    }

    func setLanguage(code: String) {
        let nextLanguage = SupportedLanguage(rawValue: code) ?? .simplifiedChinese
        guard nextLanguage != selectedLanguage else { return }
        selectedLanguage = nextLanguage
        storedLanguageCode = nextLanguage.rawValue
    }

    private static func defaultLanguageFromSystem() -> SupportedLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}
