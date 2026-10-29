import Foundation

public enum NovagramSearchLanguage: String, Codable, CaseIterable {
    case uzLatin = "uz-Latn"
    case uzCyrillic = "uz-Cyrl"
    case russian = "ru"
    case english = "en"

    public static let all: Set<NovagramSearchLanguage> = Set(NovagramSearchLanguage.allCases)

    public var translationCode: String {
        switch self {
        case .uzLatin, .uzCyrillic:
            return "uz"
        case .russian:
            return "ru"
        case .english:
            return "en"
        }
    }

    public static func detect(_ text: String) -> NovagramSearchLanguage? {
        return detect(text, census: NovagramScriptCensus(text))
    }

    static func detect(_ text: String, census: NovagramScriptCensus) -> NovagramSearchLanguage? {
        guard census.letters > 0, (census.latin + census.cyrillic) * 2 > census.letters else { return nil }
        if census.cyrillic > census.latin {
            let uzbek = census.uzbekCyrillic + count(uzCyrillicWordRegex, text) * 2
            return uzbek > count(russianWordRegex, text) ? .uzCyrillic : .russian
        }
        let uzbek = count(uzLatinWordRegex, text) + count(uzLatinApostropheRegex, text)
        return uzbek > count(englishWordRegex, text) ? .uzLatin : .english
    }

    private static func count(_ regex: NSRegularExpression, _ text: String) -> Int {
        return regex.numberOfMatches(in: text, options: [], range: NovagramJobRegex.fullRange(text))
    }

    private static func wholeWords(_ words: [String]) -> NSRegularExpression {
        return NovagramJobRegex.make("(?<![\\p{L}'])(?:" + words.joined(separator: "|") + ")(?![\\p{L}'])", caseInsensitive: true)
    }

    private static let uzLatinApostropheRegex = NovagramJobRegex.make("(?<=\\p{L}|^|\\s)[og][\\u02BB\\u02BC\\u2018\\u2019`\\u00B4\\u2032'](?=\\p{L})", caseInsensitive: true)
    private static let uzLatinWordRegex = NovagramJobRegex.make(
        "(?<![\\p{L}'])(?:(?:va|uchun|kerak|ish|bilan|yoki|bor|ham|emas|bizga|sizni|bizning|haqida|yaxshi|manzil|talab)(?![\\p{L}'])"
            + "|(?:ishga|ishla|maosh|oylik|tajriba|xodim|qilinadi|kompaniyamiz|vakansiya|rezyume|dasturchi|shahri|tuman|yosh|soat|qidir|izlay)"
            + "|\\p{L}+(?:chi|chilar|chisi|ning|lik)(?![\\p{L}'])|\\p{L}*q(?!u)\\p{L}*)",
        caseInsensitive: true
    )
    private static let englishWordRegex = wholeWords(["the", "and", "for", "with", "to", "we", "are", "you", "of", "in", "is", "our", "will", "your", "this", "that", "be", "have", "an", "or", "looking", "join", "team"])
    private static let uzCyrillicWordRegex = wholeWords(["ва", "учун", "керак", "иш", "ишга", "билан", "ёки", "маош", "ойлик", "бор", "ҳам", "тажриба", "ходим", "талаб", "бизга", "сизни", "ҳақида", "яхши", "манзил", "\\p{L}+(?<![аяю])чи(?:лар|си)?"])
    private static let russianWordRegex = wholeWords(["и", "в", "на", "для", "с", "по", "от", "мы", "вы", "не", "что", "как", "или", "до", "работа", "работу", "требуется", "опыт", "зарплата", "компания", "ищем", "нужен", "нужна"])
}

struct NovagramScriptCensus {
    private(set) var letters = 0
    private(set) var latin = 0
    private(set) var cyrillic = 0
    private(set) var uzbekCyrillic = 0
    private(set) var cjk = 0

    private static let uzbekCyrillicScalars: Set<UInt32> = [0x040E, 0x045E, 0x049A, 0x049B, 0x0492, 0x0493, 0x04B2, 0x04B3]

    init(_ text: String) {
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            let value = scalar.value
            if value < 0x0250 || (0x02B0...0x02FF).contains(value) || (0x1E00...0x1EFF).contains(value) {
                latin += 1
            } else if (0x0400...0x04FF).contains(value) {
                cyrillic += 1
                if NovagramScriptCensus.uzbekCyrillicScalars.contains(value) {
                    uzbekCyrillic += 1
                }
            } else if (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x3040...0x30FF).contains(value) || (0xAC00...0xD7AF).contains(value) {
                cjk += 1
            }
        }
    }

    var isMostlyCJK: Bool {
        return letters > 0 && cjk * 2 > letters
    }
}
