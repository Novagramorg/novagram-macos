import Foundation
import SwiftSignalKit
import TelegramCore

enum NovagramJobTranslations {
    private static let maxCachedQueries = 200
    private static let timeoutSeconds: Double = 8
    private static let cache = Atomic<[String: String]>(value: [:])

    static func fetch(engine: TelegramEngine, query: String, needed: [NovagramSearchLanguage]) -> Signal<[NovagramSearchLanguage: String], NoError> {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var languageByCode: [String: NovagramSearchLanguage] = [:]
        for language in needed where languageByCode[language.translationCode] == nil {
            languageByCode[language.translationCode] = language
        }
        guard !text.isEmpty, !languageByCode.isEmpty else {
            return .single([:])
        }
        let signals = languageByCode.map { code, language -> Signal<(NovagramSearchLanguage, String?), NoError> in
            let key = code + "\n" + text
            if let cached = cache.with({ $0[key] }) {
                return .single((language, cached.isEmpty ? nil : cached))
            }
            let request: Signal<String?, NoError> = engine.messages.translate(text: text, toLang: code)
                |> map { result -> String? in
                    let translated = result?.0.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !translated.isEmpty {
                        store(translated, for: key)
                    }
                    return translated.isEmpty ? nil : translated
                }
                |> `catch` { _ -> Signal<String?, NoError> in
                    return .single(nil)
                }
            let limited = NovagramJobRequestLimiter.shared.limited(request |> take(1))
            return (limited |> map { (language, $0) } |> then(.single((language, nil)))) |> take(1) |> timeout(timeoutSeconds, queue: Queue.concurrentDefaultQueue(), alternate: .single((language, nil)))
        }
        return combineLatest(signals) |> map { pairs in
            var result: [NovagramSearchLanguage: String] = [:]
            for (language, translated) in pairs {
                if let translated {
                    result[language] = translated
                }
            }
            return result
        }
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
