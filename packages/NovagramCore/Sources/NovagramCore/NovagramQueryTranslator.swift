import Foundation
import SwiftSignalKit
import TelegramCore

public enum NovagramQueryTranslator {
    public static let defaultsKey = "novagram_search_translate"
    public static let minQueryLength = 3

    private static let suiteName = "pro_messager"
    private static let languageKey = "auto_translate_lang"
    private static let fallbackLanguage = "en"
    private static let debounceSeconds: Double = 0.6
    private static let maxCachedQueries = 200
    private static let cache = Atomic<[String: String]>(value: [:])

    public static var isEnabled: Bool {
        get {
            return UserDefaults(suiteName: suiteName)?.object(forKey: defaultsKey) as? Bool ?? false
        }
        set {
            UserDefaults(suiteName: suiteName)?.set(newValue, forKey: defaultsKey)
        }
    }

    public static var targetLanguage: String {
        guard let lang = UserDefaults(suiteName: suiteName)?.string(forKey: languageKey), !lang.isEmpty else {
            return fallbackLanguage
        }
        return lang
    }

    public static func translatedQuery(engine: TelegramEngine, query: String) -> Signal<String?, NoError> {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NovagramSearchFeatures.isEnabled, isEnabled, query.count >= minQueryLength else {
            return .single(nil)
        }
        let lang = targetLanguage
        let key = lang + "\n" + query
        if let cached = cache.with({ $0[key] }) {
            return .single(cached.isEmpty ? nil : cached)
        }
        let request: Signal<String?, NoError> = engine.messages.translate(text: query, toLang: lang)
            |> map { result -> String? in
                let text = result?.0.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                store(isSame(text, query) ? "" : text, for: key)
                return isSame(text, query) ? nil : text
            }
            |> `catch` { _ -> Signal<String?, NoError> in
                return .single(nil)
            }
        return .single(nil) |> then(request |> delay(debounceSeconds, queue: .concurrentDefaultQueue()))
    }

    private static func isSame(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.isEmpty {
            return true
        }
        return normalized(lhs) == normalized(rhs)
    }

    private static func normalized(_ text: String) -> String {
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func store(_ value: String, for key: String) {
        _ = cache.modify { current in
            var current = current
            if current.count >= maxCachedQueries {
                current.removeAll()
            }
            current[key] = value
            return current
        }
    }
}
