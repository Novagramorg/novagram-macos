import Foundation

public struct NovagramSearchConversionPlan: Equatable {
    public let sourceLanguage: NovagramSearchLanguage?
    public let transliterations: [NovagramSearchLanguage: String]
    public let translationsNeeded: [NovagramSearchLanguage]

    public static let empty = NovagramSearchConversionPlan(sourceLanguage: nil, transliterations: [:], translationsNeeded: [])

    public var isEmpty: Bool {
        return transliterations.isEmpty && translationsNeeded.isEmpty
    }

    public init(sourceLanguage: NovagramSearchLanguage?, transliterations: [NovagramSearchLanguage: String], translationsNeeded: [NovagramSearchLanguage]) {
        self.sourceLanguage = sourceLanguage
        self.transliterations = transliterations
        self.translationsNeeded = translationsNeeded
    }
}

public enum NovagramSearchConversion {
    public static func plan(query: String, languages: Set<NovagramSearchLanguage>) -> NovagramSearchConversionPlan {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !languages.isEmpty else { return .empty }
        let source = NovagramSearchLanguage.detect(trimmed)
        var transliterations: [NovagramSearchLanguage: String] = [:]
        if source == .uzLatin, languages.contains(.uzCyrillic), let converted = transliterate(trimmed, to: .uzCyrillic) {
            transliterations[.uzCyrillic] = converted
        }
        if source == .uzCyrillic, languages.contains(.uzLatin), let converted = transliterate(trimmed, to: .uzLatin) {
            transliterations[.uzLatin] = converted
        }
        let sourceIsUzbek = source == .uzLatin || source == .uzCyrillic
        let translationsNeeded = NovagramSearchLanguage.allCases.filter { language in
            guard languages.contains(language), language != source else { return false }
            let isUzbek = language == .uzLatin || language == .uzCyrillic
            return !(isUzbek && sourceIsUzbek)
        }
        return NovagramSearchConversionPlan(sourceLanguage: source, transliterations: transliterations, translationsNeeded: translationsNeeded)
    }

    public static func transliterate(_ text: String, to language: NovagramSearchLanguage) -> String? {
        guard language == .uzLatin || language == .uzCyrillic else { return nil }
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let value = String(word)
            if language == .uzCyrillic {
                return value.contains(where: NovagramJobText.isLatinLetter) && !looksEnglish(value) ? NovagramJobText.uzbekLatinToCyrillic(value) : value
            }
            return value.contains(where: NovagramJobText.isCyrillicLetter) ? NovagramJobText.uzbekCyrillicToLatin(value) : value
        }
        let result = words.joined(separator: " ")
        return result == text ? nil : result
    }

    private static let englishWords: Set<String> = [
        "ios", "android", "java", "javascript", "typescript", "golang", "go", "react", "node", "flutter", "kotlin", "swift", "php",
        "sql", "qa", "hr", "smm", "seo", "ui", "ux", "devops", "backend", "frontend", "fullstack", "developer", "designer",
        "manager", "senior", "junior", "middle", "lead", "remote", "office", "data", "web", "mobile", "product", "project",
        "sales", "support", "marketing", "analyst", "intern", "it", "net", "ruby", "rust", "vue", "angular", "django", "laravel"
    ]
    private static let englishPattern = NovagramJobRegex.make("w|c(?!h)|th|ph|ee|oo|ck|ing$|tion$|[0-9+#]", caseInsensitive: true)

    static func looksEnglish(_ word: String) -> Bool {
        let letters = word.trimmingCharacters(in: CharacterSet.letters.inverted)
        guard !letters.isEmpty else { return true }
        if englishWords.contains(letters.lowercased()) {
            return true
        }
        if letters.dropFirst().contains(where: { $0.isUppercase }) {
            return true
        }
        return NovagramJobRegex.contains(englishPattern, in: word)
    }
}
