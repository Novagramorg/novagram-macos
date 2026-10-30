import Foundation
import SwiftSignalKit
import TelegramCore
import NovagramSearchKit

public enum NovagramQueryTranslator {
    public static let defaultsKey = NovagramSearchSettings.Keys.searchTranslate
    public static let minQueryLength = NovagramQueryTranslation.minQueryLength
    public static let targetsKey = NovagramSearchSettings.Keys.translateTargets
    public static let targetCodes = NovagramSearchSettings.translateTargetCodes

    private static var settings: NovagramSearchSettings {
        return .shared
    }

    private static var cache: NovagramQueryTranslationCache {
        return .shared
    }

    public static var isEnabled: Bool {
        get {
            return settings.isTranslateEnabled
        }
        set {
            settings.isTranslateEnabled = newValue
        }
    }

    public static var targetLanguage: String {
        return settings.translationLanguage
    }

    public static var targets: [String] {
        return settings.translateTargets
    }

    public static var hasStoredTargets: Bool {
        return UserDefaults(suiteName: NovagramSearchSettings.suiteName)?.object(forKey: targetsKey) != nil
    }

    public static func toggleTarget(_ code: String) {
        var current = targets
        if let index = current.firstIndex(of: code) {
            current.remove(at: index)
        } else {
            current.append(code)
        }
        settings.setTranslateTargets(current)
    }

    public static func clearTargets() {
        settings.setTranslateTargets([])
    }

    public static func serverCode(for target: String) -> String? {
        return NovagramSearchSettings.serverTranslationCodes(for: [target]).first
    }

    public static func serverCodes(for targets: [String]) -> [String] {
        return NovagramSearchSettings.serverTranslationCodes(for: targets)
    }

    public static func targetName(_ code: String) -> String {
        switch NovagramSearchLanguage(rawValue: code) {
        case .uzLatin:
            return "O'zbekcha (lotin)"
        case .uzCyrillic:
            return "Ўзбекча (кирилл)"
        case .russian:
            return "Русский"
        case .english:
            return "English"
        case nil:
            return NovagramL10n.current.autoTranslate_languageName(code)
        }
    }

    public static var targetsLabel: String {
        let l10n = NovagramL10n.current
        guard hasStoredTargets else {
            return l10n.autoTranslate_languageName(settings.translationLanguage)
        }
        let current = targets
        return current.isEmpty ? l10n.search_translateNone : current.map(targetName).joined(separator: ", ")
    }

    public static func translatedQuery(engine: TelegramEngine, query: String) -> Signal<String?, NoError> {
        return translatedQuery(engine: engine, query: query, language: targetLanguage)
    }

    public static func translatedQuery(engine: TelegramEngine, query: String, language lang: String) -> Signal<String?, NoError> {
        let query = NovagramQueryTranslation.trimmed(query)
        guard NovagramSearchFeatures.isEnabled, settings.isTranslateActive, query.count >= minQueryLength else {
            return .single(nil)
        }
        switch cache.lookup(query: query, language: lang) {
        case .noSection:
            return .single(nil)
        case let .translation(text):
            return .single(text)
        case .miss:
            break
        }
        let request: Signal<String?, NoError> = engine.messages.translate(text: query, toLang: lang)
            |> map { result -> String? in
                return cache.store(translation: result?.0, query: query, language: lang)
            }
            |> `catch` { _ -> Signal<String?, NoError> in
                return .single(nil)
            }
        return .single(nil) |> then(request |> delay(NovagramQueryTranslation.debounceSeconds, queue: .concurrentDefaultQueue()))
    }
}
