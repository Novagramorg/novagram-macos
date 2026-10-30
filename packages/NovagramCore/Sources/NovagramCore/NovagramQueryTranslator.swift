import Foundation
import SwiftSignalKit
import TelegramCore
import NovagramSearchKit

public enum NovagramQueryTranslator {
    public static let defaultsKey = NovagramSearchSettings.Keys.searchTranslate
    public static let minQueryLength = NovagramQueryTranslation.minQueryLength

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

    public static func translatedQuery(engine: TelegramEngine, query: String) -> Signal<String?, NoError> {
        let query = NovagramQueryTranslation.trimmed(query)
        guard settings.isTranslateActive, query.count >= minQueryLength else {
            return .single(nil)
        }
        let lang = targetLanguage
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
