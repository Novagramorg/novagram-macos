import Foundation

public enum NovagramJobPostParser {
    static let maxTitleLength = 80
    private static let hashtagWeight = 3
    private static let resumeRequestWeight = 2

    public static func parse(_ text: String) -> NovagramJobPostInfo {
        let unified = NovagramJobText.unifiedApostrophes(text)
        let normalized = NovagramJobText.normalized(text)
        var info = NovagramJobPostInfo(
            title: title(unified),
            salary: NovagramJobSalaryParser.salary(unified: unified, normalized: normalized),
            cityIds: cityIds(normalized: normalized),
            formats: formats(normalized: normalized),
            employment: employment(normalized: normalized),
            experienceYears: experienceYears(normalized: normalized),
            contacts: NovagramJobContactParser.contacts(unified)
        )
        info.kind = kind(text: text, normalized: normalized, info: info)
        return info
    }

    private static let vacancyMarkers = [
        "vakansiy", "vakansia", "ваканси", "vacanc", "hiring", "we are hiring", "ishga taklif", "ishga olamiz", "ishga qabul",
        "xodim kerak", "xodimlar kerak", "hodim kerak", "talab qilinadi", "требует", "ищем", "ish bor", "ishbor", "ish_bor",
        "иш бор", "ходим керак", "ходимлар керак", "ишга таклиф", "ишга оламиз", "ишга қабул", "талаб қилинади",
        "job offer", "we are looking for", "мы ищем", "в команду", "jamoamizga", "жамоамизга"
    ]
    private static let resumeMarkers = [
        "rezyume", "rezume", "резюме", "resume", "ish qidiryapman", "ish qidiraman", "ishqidiraman", "ish_qidiraman",
        "ish izlayapman", "ish izlayman", "иш қидиряпман", "иш қидираман", "иш излаяпман", "ищу работу", "ищуработу",
        "ищу вакансию", "в поиске работы", "нужна работа", "нужна подработка", "ish kerak", "иш керак",
        "looking for a position", "looking for a job", "looking for job", "open to work", "opentowork", "hire me"
    ]

    private static let vacancyRegex = NovagramJobRegex.make(NovagramJobRegex.wordStart + "(#?)(?:" + NovagramJobRegex.alternation(vacancyMarkers) + ")")
    private static let resumeRegex = NovagramJobRegex.make(
        NovagramJobRegex.wordStart + "(#?)(?:" + NovagramJobRegex.alternation(resumeMarkers) + "|cv" + NovagramJobRegex.wordEnd + ")"
    )
    private static let resumeRequestRegex = NovagramJobRegex.make(
        NovagramJobRegex.wordStart + "(?:(?:rezyume|rezume|резюме|resume|cv)\\p{L}*[^.!?]{0,40}?"
            + "(?:yubor|jo'nat|юбор|жунат|отправ|присыл|направ|скид|кидай)"
            + "|send\\s+(?:us\\s+|your\\s+|me\\s+)*(?:cv|resume))"
    )

    private static func markerScore(_ regex: NSRegularExpression, _ text: String) -> Int {
        return NovagramJobRegex.matches(regex, in: text).reduce(0) { score, match in
            score + (match.range(at: 1).length > 0 ? hashtagWeight : 1)
        }
    }

    private static let vacancyPhraseRegex = NovagramJobRegex.make(
        NovagramJobRegex.wordStart + "(?:нужен|нужна(?!\\s+(?:работ|подработ))|нужны|открыта вакансия|в поиске\\s+(?:\\p{L}+\\s+){0,2}?(?:сотрудник|специалист|кандидат|менеджер|продав|водител|бухгалтер|оператор|разработчик|программист|дизайнер|администратор|повар|мастер|курьер|помощник|ассистент|smm|hr|юрист|маркетолог|человек|людей)|приглашаем"
            + "|на позицию|we're looking for|join our team|position|open role|apply)"
    )
    private static let roleKerakRegex = NovagramJobRegex.make(
        "(?:chi|chilar|chisi|ist|istlar|isti|er|erlar|eri|or|orlar|ori|ir|usta|ustalar|oshpaz|farrosh|hamshira|admin|xodim|xodimlar|hodim|dev"
            + "|чи|чилар|чиси|ист|истлар|исти|ер|ерлар|ери|ор|орлар|ори|ир|уста|усталар|ошпаз|фаррош|ҳамшира|ходим|ходимлар)"
            + "\\s(?:kerak|керак)" + NovagramJobRegex.wordEnd
    )
    private static let bareKerakRegex = NovagramJobRegex.make(NovagramJobRegex.wordStart + "(?<!ish )(?<!иш )(?:kerak|керак)" + NovagramJobRegex.wordEnd)
    private static let jobWordRegex = NovagramJobRegex.wordPrefix(["ish", "lavozim", "tajriba", "maosh", "oylik", "иш", "лавозим", "тажриба", "маош", "ойлик"])
    private static let strongSpamRegex = NovagramJobRegex.wordPrefix([
        "market cap", "trading strategy", "profitable trading", "guaranteed profit", "100% profit", "airdrop", "pump", "presale", "pre-sale",
        "casino", "казино", "betting", "букмекер", "ставки на", "x100"
    ])
    private static let weakSpamRegex = NovagramJobRegex.wordPrefix([
        "token", "coin", "crypto", "kripto", "крипт", "bitcoin", "биткоин", "usdt", "binance", "forex", "форекс", "trading", "трейдинг", "nft"
    ])
    private static let strongSpamWeight = 2
    private static let minSpamScore = 2

    static func kind(text: String, normalized: String, info: NovagramJobPostInfo) -> NovagramJobPostKind {
        let requests = NovagramJobRegex.matches(resumeRequestRegex, in: normalized).count
        let markerVacancy = markerScore(vacancyRegex, normalized)
            + requests * resumeRequestWeight
            + NovagramJobRegex.matches(vacancyPhraseRegex, in: normalized).count
            + NovagramJobRegex.matches(roleKerakRegex, in: normalized).count * resumeRequestWeight
        let resume = markerScore(resumeRegex, normalized) - requests
        var vacancy = markerVacancy
        if NovagramJobRegex.contains(bareKerakRegex, in: normalized) && hasJobSignal(normalized: normalized, info: info) {
            vacancy += 1
        }
        if resume <= 0 && hasStructureSignal(info) {
            vacancy += 1
        }
        let spam = NovagramJobRegex.matches(strongSpamRegex, in: normalized).count * strongSpamWeight
            + NovagramJobRegex.matches(weakSpamRegex, in: normalized).count
        if spam >= minSpamScore && spam >= Swift.max(vacancy, resume) {
            return .unknown
        }
        if markerVacancy <= 0 && resume <= 0 && isMostlyCJK(text) {
            return .unknown
        }
        if vacancy > resume {
            return .vacancy
        }
        if resume > vacancy {
            return .resume
        }
        return .unknown
    }

    private static func hasJobSignal(normalized: String, info: NovagramJobPostInfo) -> Bool {
        return info.salary != nil || !info.formats.isEmpty || !info.employment.isEmpty || NovagramJobRegex.contains(jobWordRegex, in: normalized)
    }

    private static func hasStructureSignal(_ info: NovagramJobPostInfo) -> Bool {
        let hasAmount = info.salary?.min != nil || info.salary?.max != nil
        return hasAmount && !info.contacts.isEmpty && (!info.formats.isEmpty || !info.employment.isEmpty || info.experienceYears != nil)
    }

    private static func isCJK(_ value: UInt32) -> Bool {
        return (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x3040...0x30FF).contains(value) || (0xAC00...0xD7AF).contains(value)
    }

    static func isMostlyCJK(_ text: String) -> Bool {
        var letters = 0
        var cjk = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            if isCJK(scalar.value) {
                cjk += 1
            }
        }
        return letters > 0 && cjk * 2 > letters
    }

    private static let titleTrimCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":;,-–—|•·*_~"))

    static func title(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = strippedLeadingDecorations(rawLine).trimmingCharacters(in: titleTrimCharacters)
            guard line.filter({ $0.isLetter }).count >= 2 else { continue }
            guard line.count > maxTitleLength else { return line }
            return String(line.prefix(maxTitleLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return nil
    }

    private static func strippedLeadingDecorations(_ line: Substring) -> String {
        var rest = line
        while let first = rest.first {
            if first == "#" {
                rest = rest.drop(while: { !$0.isWhitespace })
            } else if first.isLetter || (first.isNumber && first.unicodeScalars.count == 1) {
                break
            } else {
                rest = rest.dropFirst()
            }
        }
        return String(rest)
    }

    private static let cityByVariant: [String: String] = {
        var result: [String: String] = [:]
        for city in NovagramJobPresets.cities {
            for variant in city.variants where result[variant] == nil {
                result[variant] = city.id
            }
        }
        return result
    }()
    private static let cityRegex = NovagramJobRegex.make(NovagramJobRegex.wordStart + "(?:" + NovagramJobRegex.alternation(Array(cityByVariant.keys)) + ")")

    static func cityIds(normalized: String) -> [String] {
        var result: [String] = []
        for match in NovagramJobRegex.matches(cityRegex, in: normalized) {
            guard let variant = NovagramJobRegex.substring(normalized, match.range), let id = cityByVariant[variant], !result.contains(id) else { continue }
            result.append(id)
        }
        return result
    }

    private static let formatRegexes: [(NovagramJobWorkFormat, NSRegularExpression)] = [
        (.remote, NovagramJobRegex.wordPrefix(["masofaviy", "masofadan", "masofaviy ish", "uydan", "udalyonka", "udalenka", "удален", "удалён", "дистанцион", "remote", "масофавий", "масофадан", "уйдан", "work from home"])),
        (.office, NovagramJobRegex.wordPrefix(["ofis", "офис", "office", "on-site", "onsite"])),
        (.hybrid, NovagramJobRegex.wordPrefix(["gibrid", "гибрид", "hybrid"]))
    ]
    private static let employmentRegexes: [(NovagramJobEmployment, NSRegularExpression)] = [
        (.fullTime, NovagramJobRegex.wordPrefix(["to'liq stavka", "to'liq kun", "toliq stavka", "toliq kun", "to'liq ish kuni", "тўлиқ ставка", "тўлиқ кун", "полный день", "полная занятость", "полный рабочий", "full-time", "full time", "fulltime"])),
        (.partTime, NovagramJobRegex.wordPrefix(["yarim stavka", "yarim kun", "ярим ставка", "ярим кун", "частичн", "неполн", "part-time", "part time", "parttime"]))
    ]

    static func formats(normalized: String) -> Set<NovagramJobWorkFormat> {
        return Set(formatRegexes.filter { NovagramJobRegex.contains($0.1, in: normalized) }.map { $0.0 })
    }

    static func employment(normalized: String) -> Set<NovagramJobEmployment> {
        return Set(employmentRegexes.filter { NovagramJobRegex.contains($0.1, in: normalized) }.map { $0.0 })
    }

    private static let experienceRegexes: [NSRegularExpression] = [
        "(?:tajriba|тажриба)[^\\d]{0,25}?(\\d{1,2})\\s*\\+?\\s*(?:-\\s*\\d{1,2}\\s*)?(?:yil|йил|year|год|лет)",
        "(?<!\\d)(\\d{1,2})\\s*\\+?\\s*-?\\s*(?:yil|йил)\\p{L}*(?:\\s+\\p{L}+)?\\s+(?:ish\\s+|иш\\s+)?(?:tajriba|тажриба)",
        "опыт[^\\d]{0,25}?(\\d{1,2})\\s*\\+?\\s*(?:-\\s*\\d{1,2}\\s*)?(?:год|лет|г\\.)",
        "(?<!\\d)(\\d{1,2})\\s*\\+?\\s*(?:years?|yrs?)(?!\\s+old)"
    ].map { NovagramJobRegex.make($0) }

    static func experienceYears(normalized: String) -> Int? {
        var best: (location: Int, years: Int)?
        for regex in experienceRegexes {
            guard let match = NovagramJobRegex.firstMatch(regex, in: normalized),
                  let text = NovagramJobRegex.substring(normalized, match.range(at: 1)),
                  let years = Int(text), years <= 50 else { continue }
            if best == nil || match.range.location < best?.location ?? Int.max {
                best = (match.range.location, years)
            }
        }
        return best?.years
    }
}
