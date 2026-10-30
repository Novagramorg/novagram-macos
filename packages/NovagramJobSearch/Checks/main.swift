import Foundation

var passedCount = 0
var failures: [String] = []

func check(_ condition: Bool, _ name: String) {
    if condition {
        passedCount += 1
    } else {
        failures.append(name)
        print("FAIL: \(name)")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual == expected {
        passedCount += 1
    } else {
        failures.append(name)
        print("FAIL: \(name)\n  expected: \(expected)\n  actual:   \(actual)")
    }
}


checkEqual(NovagramJobText.normalized("  Toshkentʻda   ISH\n bor "), "toshkent'da ish bor", "normalized folds case, apostrophes, whitespace")
checkEqual(NovagramJobText.normalized("Résumé O’QITUVCHI"), "resume o'qituvchi", "normalized folds diacritics")
checkEqual(NovagramJobText.uzbekLatinToCyrillic("Toshkent"), "Тошкент", "latin to cyrillic Toshkent")
checkEqual(NovagramJobText.uzbekLatinToCyrillic("o'qituvchi"), "ўқитувчи", "latin to cyrillic o'")
checkEqual(NovagramJobText.uzbekLatinToCyrillic("shahar"), "шаҳар", "latin to cyrillic sh and h")
checkEqual(NovagramJobText.uzbekLatinToCyrillic("g‘alaba"), "ғалаба", "latin to cyrillic g' with curly apostrophe")
checkEqual(NovagramJobText.uzbekLatinToCyrillic("ekspert yangi choy"), "эксперт янги чой", "latin to cyrillic word-initial e, ya, ch")
checkEqual(NovagramJobText.uzbekLatinToCyrillic("ta'lim"), "таълим", "latin to cyrillic tutuq belgisi")
checkEqual(NovagramJobText.uzbekCyrillicToLatin("Тошкент"), "Toshkent", "cyrillic to latin Toshkent")
checkEqual(NovagramJobText.uzbekCyrillicToLatin("ўқитувчи ғалаба"), "o'qituvchi g'alaba", "cyrillic to latin ў and ғ")
checkEqual(NovagramJobText.uzbekCyrillicToLatin("Ер юзи"), "Yer yuzi", "cyrillic to latin word-initial е")
checkEqual(NovagramJobText.uzbekCyrillicToLatin("ҳисобчи керак"), "hisobchi kerak", "cyrillic to latin ҳ and е")


let orQuery = NovagramJobQuery.parse("python yoki golang", expandScripts: false)
checkEqual(orQuery.serverQueries, ["python", "golang"], "OR word splits branches")
let pipeQuery = NovagramJobQuery.parse("ios|android или flutter", expandScripts: false)
checkEqual(pipeQuery.serverQueries, ["ios", "android", "flutter"], "pipe and или split branches")
let expanded = NovagramJobQuery.parse("dasturchi | менеджер")
checkEqual(expanded.serverQueries, ["dasturchi", "менеджер", "дастурчи", "menedjer"], "script variants follow originals")
let manyBranches = NovagramJobQuery.parse("a1 | b2 | c3 | d4 | e5 | f6 | g7")
checkEqual(manyBranches.serverQueries.count, NovagramJobQuery.maxServerQueries, "server queries capped")
let notQuery = NovagramJobQuery.parse("iOS -junior")
check(notQuery.matches("Senior iOS developer kerak"), "NOT query keeps text without excluded word")
check(!notQuery.matches("Junior iOS developer kerak"), "NOT query rejects excluded word")
checkEqual(NovagramJobQuery.parse("-stajyor").serverQueries, [], "NOT-only query has no server query")
check(NovagramJobQuery.parse("-stajyor").isEmpty, "NOT-only query is empty for the server")
let phraseQuery = NovagramJobQuery.parse("“ish haqi” toshkent")
check(phraseQuery.matches("Ish haqi yuqori, Toshkentda ofis"), "phrase plus word-prefix term matches")
check(!phraseQuery.matches("Toshkentda ish bor, haqi yaxshi"), "phrase must be contiguous")
check(NovagramJobQuery.parse("«ish bor»").matches("Bugun ISH   BOR!"), "guillemet phrase matches normalized text")
check(NovagramJobQuery.parse("toshkent").matches("Тошкентда офисга ҳисобчи керак"), "latin term matches cyrillic text")
check(NovagramJobQuery.parse("ҳисобчи").matches("Toshkentda hisobchi kerak"), "cyrillic term matches latin text")
check(NovagramJobQuery.parse("dasturchi").matches("Dasturchilar kerak"), "word prefix matches longer word")
check(!NovagramJobQuery.parse("dasturchi").matches("Yangidasturchilar"), "term must start at a word")
check(NovagramJobQuery.parse("").matches("anything"), "empty query matches everything")
checkEqual(NovagramJobQuery.parse("#ios developer").hashtagTerms, ["ios", "developer"], "explicit hashtag first")
checkEqual(NovagramJobQuery.parse("c# или java | 1c | python").hashtagTerms, ["c#", "java", "1c"], "role keyword hashtags capped at 3")
checkEqual(NovagramJobQuery.parse("\"o'qituvchi kerak\"").hashtagTerms, [], "phrases are not hashtags")
checkEqual(NovagramJobQuery.parse("swift"), NovagramJobQuery.parse("swift"), "query is equatable")
check(NovagramJobQuery(raw: "swift -junior", serverQueries: ["swift"], hashtagTerms: []).matches("Senior Swift"), "public init compiles the matcher")
check(!NovagramJobQuery(raw: "swift -junior", serverQueries: ["swift"], hashtagTerms: []).matches("Junior Swift"), "public init compiles NOT terms")


let uzLatinVacancy = """
📢 #vakansiya
🏢 Python dasturchi kerak
📍 Manzil: Toshkent shahri, Chilonzor tumani
💰 Maosh: 800$ dan 1200$ gacha
🕘 Ish vaqti: 9:00-18:00, to'liq stavka, ofisda
📌 Tajriba: kamida 2 yil
📞 +998 90 123-45-67
✉️ @hr_example_uz
"""
let info1 = NovagramJobPostParser.parse(uzLatinVacancy)
checkEqual(info1.kind, .vacancy, "uz latin vacancy kind")
checkEqual(info1.title, "Python dasturchi kerak", "uz latin vacancy title skips hashtag line")
checkEqual(info1.salary?.min, 800, "uz latin salary min")
checkEqual(info1.salary?.max, 1200, "uz latin salary max")
checkEqual(info1.salary?.currency, .usd, "uz latin salary currency")
checkEqual(info1.salary?.text, "800$ dan 1200$", "uz latin salary fragment")
checkEqual(info1.cityIds, ["tashkent"], "uz latin city")
checkEqual(info1.formats, [.office], "uz latin office format")
checkEqual(info1.employment, [.fullTime], "uz latin full time")
checkEqual(info1.experienceYears, 2, "uz latin experience")
checkEqual(info1.contacts, [.phone("+998901234567"), .username("hr_example_uz")], "uz latin contacts")

let ruVacancy = """
#вакансия
Требуется менеджер по продажам
г. Ташкент, офис
Зарплата: от 5 000 000 до 8 000 000 сум
Опыт работы от 1 года
Тел: +998 (93) 555 44 33
hr@example.uz
"""
let info2 = NovagramJobPostParser.parse(ruVacancy)
checkEqual(info2.kind, .vacancy, "ru vacancy kind")
checkEqual(info2.title, "Требуется менеджер по продажам", "ru vacancy title")
checkEqual(info2.salary, NovagramJobSalary(text: "от 5 000 000 до 8 000 000 сум", min: 5_000_000, max: 8_000_000, currency: .uzs), "ru salary range with от/до")
checkEqual(info2.cityIds, ["tashkent"], "ru city with г.")
checkEqual(info2.experienceYears, 1, "ru experience")
checkEqual(info2.contacts, [.phone("+998935554433"), .email("hr@example.uz")], "ru contacts")

let uzCyrillicVacancy = """
#вакансия
Ҳисобчи керак
Самарқандда, тўлиқ кун
Ойлик: 5-7 млн сўм
Телефон: 91 234 56 78
"""
let info3 = NovagramJobPostParser.parse(uzCyrillicVacancy)
checkEqual(info3.kind, .vacancy, "uz cyrillic vacancy kind")
checkEqual(info3.title, "Ҳисобчи керак", "uz cyrillic title")
checkEqual(info3.cityIds, ["samarkand"], "uz cyrillic city declension")
checkEqual(info3.employment, [.fullTime], "uz cyrillic full time")
checkEqual(info3.salary?.min, 5_000_000, "multiplier propagates to range start")
checkEqual(info3.salary?.max, 7_000_000, "multiplier on range end")
checkEqual(info3.salary?.currency, .uzs, "сўм is uzs")
checkEqual(info3.contacts, [.phone("+998912345678")], "local phone normalized")

let enResume = """
#resume #cv
Looking for a job: iOS developer
3 years of experience with Swift
Remote or hybrid
Expected salary: $1500+
Contact: @dev_example, https://github.com/alidev.
"""
let info4 = NovagramJobPostParser.parse(enResume)
checkEqual(info4.kind, .resume, "en resume kind")
checkEqual(info4.title, "Looking for a job: iOS developer", "en resume title")
checkEqual(info4.experienceYears, 3, "en experience")
checkEqual(info4.formats, [.remote, .hybrid], "en formats")
checkEqual(info4.salary?.min, 1500, "$1500+ min")
checkEqual(info4.salary?.max, nil, "$1500+ has no max")
checkEqual(info4.contacts, [.username("dev_example"), .link("https://github.com/alidev")], "en contacts trim punctuation")

let uzResume = """
#rezyume
Ism: Aziz, 24 yosh
Ish qidiryapman, Buxoroda yoki masofadan
Tajriba: 2 yillik
Oylik: kelishilgan
Tel: 998971112233
"""
let info5 = NovagramJobPostParser.parse(uzResume)
checkEqual(info5.kind, .resume, "uz resume kind")
checkEqual(info5.cityIds, ["bukhara"], "Buxoroda is bukhara")
checkEqual(info5.formats, [.remote], "masofadan is remote")
checkEqual(info5.experienceYears, 2, "uz resume experience")
checkEqual(info5.salary?.isNegotiable, true, "kelishilgan is negotiable")
checkEqual(info5.salary?.min, nil, "negotiable salary has no amount")
checkEqual(info5.contacts, [.phone("+998971112233")], "998 phone without plus")

let ruResume = """
Резюме
Ищу работу бухгалтером в Москве
Опыт 5 лет, полная занятость
Желаемая зарплата 80 000 руб.
+7 (999) 123-45-67
"""
let info6 = NovagramJobPostParser.parse(ruResume)
checkEqual(info6.kind, .resume, "ru resume kind")
checkEqual(info6.cityIds, ["moscow"], "в Москве is moscow")
checkEqual(info6.experienceYears, 5, "опыт 5 лет")
checkEqual(info6.employment, [.fullTime], "полная занятость")
checkEqual(info6.salary?.min, 80_000, "rub salary")
checkEqual(info6.salary?.currency, .rub, "руб is rub")
checkEqual(info6.contacts, [.phone("+79991234567")], "+7 phone")

checkEqual(NovagramJobPostParser.parse("Sotuv menejeri kerak. Rezyumeni @example_hr_team ga yuboring").kind, .vacancy, "send-resume request counts as vacancy")
checkEqual(NovagramJobPostParser.parse("Salom hammaga, yaxshi kun").kind, .unknown, "no markers is unknown")
checkEqual(NovagramJobPostParser.parse("Maosh yaxshi.\nTel: +998 90 123 45 67").salary, nil, "phone is not a salary")
checkEqual(NovagramJobPostParser.parse("Ish haqi 2026-yil 1-yanvardan oshadi").salary, nil, "year and date are not a salary")
checkEqual(NovagramJobPostParser.parse("Maosh 15.11.2026 dan beriladi, tel 90 123 45 67").salary, nil, "date and local phone are not a salary")
checkEqual(NovagramJobPostParser.parse("Kompaniya 2015 yildan beri ishlaydi. Oylik maosh 3 000 000 so'm").salary?.min, 3_000_000, "year skipped, so'm salary found")
checkEqual(NovagramJobPostParser.parse("Oylik: 1 000 000 – 2 000 000 so‘m").salary, NovagramJobSalary(text: "1 000 000 – 2 000 000 so'm", min: 1_000_000, max: 2_000_000, currency: .uzs), "grouped range with dash")
checkEqual(NovagramJobPostParser.parse("Зарплата 1500 у.е.").salary?.currency, .usd, "у.е. is usd")
checkEqual(NovagramJobPostParser.parse("Salary: 2,500 EUR").salary?.min, 2500, "comma thousands")
checkEqual(NovagramJobPostParser.parse("ЗП 150 тыс руб").salary?.min, 150_000, "тыс multiplier")
checkEqual(NovagramJobPostParser.parse("oylik 1.5 mln").salary?.min, 1_500_000, "decimal mln without currency")
checkEqual(NovagramJobPostParser.parse("maosh 1500").salary?.min, 1500, "bare number with salary word")
checkEqual(NovagramJobPostParser.parse("до 2000$ в месяц").salary?.max, 2000, "до gives max only")
checkEqual(NovagramJobPostParser.parse("Зарплата по договоренности").salary?.isNegotiable, true, "ru negotiable")
checkEqual(NovagramJobPostParser.parse("Офис в Ташкенте и Самарканде, в г. Фергане").cityIds, ["tashkent", "samarkand", "fergana"], "ru city declensions in order")
checkEqual(NovagramJobPostParser.parse("Qo‘qon va Farg'onada filiallar, Toshkentda ham").cityIds, ["kokand", "fergana", "tashkent"], "uz latin cities with apostrophes")
checkEqual(NovagramJobPostParser.parse("Email: info@example.com, @example_user_ok, t.me/novagram_jobs").contacts, [.email("info@example.com"), .username("example_user_ok"), .link("t.me/novagram_jobs")], "email, username, t.me link")
checkEqual(NovagramJobPostParser.parse("2+ years iOS, 18 years old").experienceYears, 2, "2+ years")
let longTitle = NovagramJobPostParser.parse("🔥🔥 " + String(repeating: "Juda uzun sarlavha ", count: 10)).title ?? ""
check(longTitle.count <= NovagramJobPostParser.maxTitleLength && longTitle.hasPrefix("Juda"), "title stripped and clipped")


let now: Int32 = 1_800_000_000
let vacancyInfo = NovagramJobPostInfo(kind: .vacancy, salary: NovagramJobSalary(text: "800$", min: 800, max: 800, currency: .usd), cityIds: ["tashkent"], formats: [.office])
let resumeInfo = NovagramJobPostInfo(kind: .resume)
let emptyQuery = NovagramJobQuery.parse("")
check(NovagramJobFilter(mode: .findJob).accepts(text: "x", info: vacancyInfo, date: now, now: now, query: emptyQuery), "findJob accepts vacancy")
check(!NovagramJobFilter(mode: .findJob).accepts(text: "x", info: resumeInfo, date: now, now: now, query: emptyQuery), "findJob rejects resume")
check(!NovagramJobFilter(mode: .findCandidates).accepts(text: "x", info: vacancyInfo, date: now, now: now, query: emptyQuery), "findCandidates rejects vacancy")
check(!NovagramJobFilter(mode: .findCandidates).accepts(text: "x", info: NovagramJobPostInfo(), date: now, now: now, query: emptyQuery), "findCandidates rejects unknown")
check(!NovagramJobFilter(mode: .findJob).accepts(text: "x", info: NovagramJobPostInfo(), date: now, now: now, query: emptyQuery), "findJob rejects unknown")
check(NovagramJobFilter(mode: .findCandidates).accepts(text: "x", info: resumeInfo, date: now, now: now, query: emptyQuery), "findCandidates accepts resume")
check(!NovagramJobFilter(period: .day).accepts(text: "x", info: vacancyInfo, date: now - 2 * 86_400, now: now, query: emptyQuery), "period rejects old post")
check(!NovagramJobFilter(cityIds: ["samarkand"]).accepts(text: "x", info: vacancyInfo, date: now, now: now, query: emptyQuery), "city filter rejects other city")
check(NovagramJobFilter(cityIds: ["samarkand"]).accepts(text: "x", info: NovagramJobPostInfo(kind: .vacancy), date: now, now: now, query: emptyQuery), "city filter keeps post without city")
check(!NovagramJobFilter(formats: [.remote]).accepts(text: "x", info: vacancyInfo, date: now, now: now, query: emptyQuery), "format filter rejects office")
check(!NovagramJobFilter(mode: .findCandidates, onlyWithSalary: true).accepts(text: "x", info: info5, date: now, now: now, query: emptyQuery), "onlyWithSalary rejects negotiable")
check(NovagramJobFilter(onlyWithSalary: true).accepts(text: "x", info: vacancyInfo, date: now, now: now, query: emptyQuery), "onlyWithSalary keeps amount")
check(!NovagramJobFilter().accepts(text: "Junior python", info: vacancyInfo, date: now, now: now, query: NovagramJobQuery.parse("python -junior")), "filter applies query")


check(NovagramJobPresets.hashtags(for: .findJob).count <= 8 && NovagramJobPresets.hashtags(for: .findJob).first == "vakansiya", "job hashtags")
check(NovagramJobPresets.hashtags(for: .findCandidates).allSatisfy { !$0.hasPrefix("#") }, "hashtags without #")
checkEqual(NovagramJobPresets.cities.count, 20, "20 cities")
check(NovagramJobPresets.city(id: "bukhara")?.variants.contains("бухар") == true, "bukhara cyrillic stem")
check((6...8).contains(NovagramJobPresets.channelDiscoveryQueries.count), "6-8 discovery queries")


let jobFilter = NovagramJobFilter(mode: .findJob, query: "iOS | swift -junior", period: .month)
let jobQuery = NovagramJobQuery.parse(jobFilter.query)
func acceptedForJob(_ text: String, query: NovagramJobQuery = jobQuery) -> Bool {
    return jobFilter.accepts(text: text, info: NovagramJobPostParser.parse(text), date: now, now: now, query: query)
}
let cryptoSpam = """
🚀 MegaCoin MEC $0.000763
Market cap: $2,000 - $200,000
We provide a 100% profitable trading strategy. Join now: t.me/megacoin_signals
#ios #swift #iphone
"""
let chineseSpam = "限时优惠！苹果 iOS 手机 低价出售，正品保证，联系微信 abc123 #ios #swift 全国包邮 欢迎咨询"
let casinoSpam = "Казино онлайн! Ставки на спорт, бонус 100%. Нужен только телефон, вывод на карту от 500 000 сум. @example_casino_bot"
let airdropSpam = "Free airdrop! Claim your token now, pump x100 guaranteed. Apply here: https://example.com/claim #swift"
let bettingSpam = "Betting tips for iOS app users: earn $500 daily, write @example_tipster"
checkEqual(NovagramJobPostParser.parse(cryptoSpam).kind, .unknown, "crypto spam is not a job post")
check(!acceptedForJob(cryptoSpam), "crypto spam rejected for findJob query")
check(!acceptedForJob(cryptoSpam, query: emptyQuery), "crypto spam rejected for empty query")
checkEqual(NovagramJobPostParser.parse(chineseSpam).kind, .unknown, "CJK ad spam is not a job post")
check(!acceptedForJob(chineseSpam), "CJK ad spam rejected")
checkEqual(NovagramJobPostParser.parse(casinoSpam).kind, .unknown, "casino spam with нужен is not a vacancy")
checkEqual(NovagramJobPostParser.parse(airdropSpam).kind, .unknown, "airdrop spam with apply is not a vacancy")
checkEqual(NovagramJobPostParser.parse(bettingSpam).kind, .unknown, "betting spam is not a job post")
checkEqual(NovagramJobPostParser.parse("Crypto birjaga backend dasturchi kerak, #vakansiya, oylik 2000$").kind, .vacancy, "crypto company vacancy survives the spam guard")
checkEqual(NovagramJobPostParser.parse("Bizning do'konga sotuvchi kerak. Maosh 4 mln so'm, Chilonzor. Tel 90 123 45 67").kind, .vacancy, "uz latin role kerak")
check(acceptedForJob("iOS developer kerak, remote, tajriba 2 yil, @example_hr_company"), "uz latin iOS developer kerak accepted")
checkEqual(NovagramJobPostParser.parse("Ofisga kerak: 2 nafar, ish vaqti 9-18").kind, .vacancy, "bare kerak with job word and office")
checkEqual(NovagramJobPostParser.parse("Bugun havo yaxshi, soyabon kerak").kind, .unknown, "bare kerak without job signal stays unknown")
checkEqual(NovagramJobPostParser.parse("Дастурчи керак, ойлик 10 млн сўм").kind, .vacancy, "uz cyrillic role керак")
checkEqual(NovagramJobPostParser.parse("Нужен водитель на доставку, оплата ежедневно, +998 93 555 44 33").kind, .vacancy, "ru нужен")
checkEqual(NovagramJobPostParser.parse("Приглашаем Android-разработчика, удалённо").kind, .vacancy, "ru приглашаем")
checkEqual(NovagramJobPostParser.parse("Мы в поиске SMM-специалиста на позицию в Ташкенте").kind, .vacancy, "ru в поиске and на позицию")
check(acceptedForJob("We’re looking for a Swift engineer to join our team. Apply via @example_talent_hr"), "en we're looking for accepted")
checkEqual(NovagramJobPostParser.parse("Open role: Product designer (hybrid, Tashkent)").kind, .vacancy, "en open role")
checkEqual(NovagramJobPostParser.parse("Python backend\nOylik: 1500$\nRemote\n@example_hr_python").kind, .vacancy, "salary, contact and format make a weak vacancy")
checkEqual(NovagramJobPostParser.parse("Ish kerak, 22 yosh, kompyuterni yaxshi bilaman").kind, .resume, "ish kerak is a resume")
checkEqual(NovagramJobPostParser.parse("Нужна работа, опыт 3 года, удалённо").kind, .resume, "нужна работа is a resume")
checkEqual(NovagramJobPostParser.parse("В поиске работы: frontend developer, 2 years").kind, .resume, "в поиске работы is a resume")
checkEqual(NovagramJobPostParser.parse("Вы работаете на фрилансе и сейчас в поиске клиентов? Тогда стоит обратить внимание на этого бота").kind, .unknown, "в поиске клиентов is not a vacancy")
checkEqual(NovagramJobPostParser.parse("Мы в поиске опытного продавца-консультанта, Ташкент").kind, .vacancy, "в поиске опытного продавца is a vacancy")
check(NovagramJobFilter(mode: .findCandidates).accepts(text: enResume, info: info4, date: now, now: now, query: emptyQuery), "en resume accepted for findCandidates")

checkEqual(NovagramSearchLanguage.detect("dasturchi kerak toshkentda"), .uzLatin, "detect uz latin words")
checkEqual(NovagramSearchLanguage.detect("o‘qituvchi"), .uzLatin, "detect uz latin apostrophe")
checkEqual(NovagramSearchLanguage.detect("hisobchi"), .uzLatin, "detect uz latin suffix")
checkEqual(NovagramSearchLanguage.detect("ҳисобчи"), .uzCyrillic, "detect uz cyrillic letters")
checkEqual(NovagramSearchLanguage.detect("дастурчи"), .uzCyrillic, "detect uz cyrillic suffix")
checkEqual(NovagramSearchLanguage.detect("менеджер по продажам"), .russian, "detect russian")
checkEqual(NovagramSearchLanguage.detect("врачи"), .russian, "russian plural in -ачи stays russian")
checkEqual(NovagramSearchLanguage.detect("python developer"), .english, "detect english")
checkEqual(NovagramSearchLanguage.detect("限时优惠 苹果手机"), nil, "detect CJK as other")
checkEqual(NovagramSearchLanguage.detect(""), nil, "detect empty as other")
checkEqual(NovagramSearchLanguage.uzCyrillic.translationCode, "uz", "uz cyrillic translation code")
checkEqual(NovagramSearchConversion.plan(query: "dasturchi", languages: NovagramSearchLanguage.all), NovagramSearchConversionPlan(sourceLanguage: .uzLatin, transliterations: [.uzCyrillic: "дастурчи"], translationsNeeded: [.russian, .english]), "plan uz latin all languages")
checkEqual(NovagramSearchConversion.plan(query: "dasturchi", languages: []), .empty, "plan None is empty")
check(NovagramSearchConversion.plan(query: "dasturchi", languages: [.uzLatin]).isEmpty, "plan own language only is empty")
checkEqual(NovagramSearchConversion.plan(query: "dasturchi", languages: [.russian]).translationsNeeded, [.russian], "plan uz latin to russian")
checkEqual(NovagramSearchConversion.plan(query: "ҳисобчи", languages: NovagramSearchLanguage.all), NovagramSearchConversionPlan(sourceLanguage: .uzCyrillic, transliterations: [.uzLatin: "hisobchi"], translationsNeeded: [.russian, .english]), "plan uz cyrillic all languages")
checkEqual(NovagramSearchConversion.plan(query: "менеджер", languages: NovagramSearchLanguage.all), NovagramSearchConversionPlan(sourceLanguage: .russian, transliterations: [:], translationsNeeded: [.uzLatin, .uzCyrillic, .english]), "plan russian all languages")
checkEqual(NovagramSearchConversion.plan(query: "python", languages: NovagramSearchLanguage.all), NovagramSearchConversionPlan(sourceLanguage: .english, transliterations: [:], translationsNeeded: [.uzLatin, .uzCyrillic, .russian]), "plan never transliterates python")
checkEqual(NovagramSearchConversion.plan(query: "python dasturchi", languages: [.uzCyrillic]).transliterations, [.uzCyrillic: "python дастурчи"], "mixed query keeps english word")
checkEqual(NovagramSearchConversion.plan(query: "python", languages: [.uzCyrillic]).translationsNeeded, [.uzCyrillic], "english to uz cyrillic needs translation")
check(NovagramSearchConversion.plan(query: "developer", languages: [.english]).isEmpty, "english to english is empty")
checkEqual(NovagramJobQuery.parse("python").serverQueries, ["python"], "expandScripts never adds python transliteration")
checkEqual(NovagramJobQuery.parse("python | dasturchi").serverQueries, ["python", "dasturchi", "дастурчи"], "expandScripts is uz scripts only")
let convertedQuery = NovagramJobQuery.parse("dasturchi -junior", languages: NovagramSearchLanguage.all, translations: [.russian: "программист", .english: "developer", .uzLatin: "dasturchi"])
checkEqual(convertedQuery.serverQueries, ["dasturchi", "дастурчи", "программист", "developer"], "original, transliteration, translations order")
check(convertedQuery.matches("Требуется программист в Ташкенте"), "translation is an OR alternative for matching")
check(convertedQuery.matches("Senior developer kerak"), "english translation matches")
check(!convertedQuery.matches("Junior developer kerak"), "raw NOT term applies to translations")
checkEqual(NovagramJobQuery.parse("python", languages: [], translations: [.russian: "питон"]).serverQueries, ["python"], "None searches the query as typed")
let uzFromLatin = NovagramJobQuery.parse("менеджер", languages: [.uzCyrillic], translations: [.uzLatin: "menejer"])
checkEqual(uzFromLatin.serverQueries, ["менеджер", "менежер"], "uz cyrillic reached by translating to uz then transliterating")
check(uzFromLatin.matches("Menejer kerak"), "converted variant matches across scripts")
let cappedQuery = NovagramJobQuery.parse("a1 | b2 | c3 | d4", languages: NovagramSearchLanguage.all, translations: [.russian: "р1 | р2", .uzLatin: "u1"])
checkEqual(cappedQuery.serverQueries.count, NovagramJobQuery.maxServerQueries, "converted server queries capped")
checkEqual(cappedQuery.serverQueries.first, "a1", "original query first")
checkEqual(NovagramJobFilter().languages, NovagramSearchLanguage.all, "filter languages default all")
let legacyFilterJSON = #"{"mode":"findCandidates","query":"swift","cityIds":["tashkent"],"formats":["remote"],"period":"month","onlyWithSalary":true}"#
let legacyFilter = try? JSONDecoder().decode(NovagramJobFilter.self, from: Data(legacyFilterJSON.utf8))
checkEqual(legacyFilter?.languages, NovagramSearchLanguage.all, "stored filter without languages decodes all four")
checkEqual(legacyFilter?.mode, .findCandidates, "stored filter keeps other fields")
let noneFilter = NovagramJobFilter(languages: [])
let noneData = try? JSONEncoder().encode(noneFilter)
checkEqual(noneData.flatMap { try? JSONDecoder().decode(NovagramJobFilter.self, from: $0) }, noneFilter, "empty languages round trip")

let suiteName = "novagram_job_checks_\(UUID().uuidString)"
if let suite = UserDefaults(suiteName: suiteName) {
    NovagramJobStore.defaults = suite
    var notifications = 0
    let observer = NotificationCenter.default.addObserver(forName: NovagramJobStore.didChangeNotification, object: nil, queue: nil) { _ in
        notifications += 1
    }
    let account = NovagramJobAccount(peerId: 111, recordId: 7)
    let otherAccount = NovagramJobAccount(peerId: 222, recordId: 8)
    let first = NovagramJobSavedSearch(id: "a", title: "iOS", filter: NovagramJobFilter(query: "ios"))
    let second = NovagramJobSavedSearch(id: "b", title: "Python", filter: NovagramJobFilter(query: "python"))
    NovagramJobStore.save(first, account: account)
    NovagramJobStore.save(second, account: account)
    checkEqual(NovagramJobStore.savedSearches(account: account).map { $0.id }, ["b", "a"], "saved searches newest first")
    var edited = first
    edited.alertsEnabled = true
    NovagramJobStore.save(edited, account: account)
    checkEqual(NovagramJobStore.savedSearches(account: account), [second, edited], "save replaces by id")
    for index in 0..<25 {
        NovagramJobStore.save(NovagramJobSavedSearch(id: "n\(index)", title: "n", filter: NovagramJobFilter()), account: account)
    }
    checkEqual(NovagramJobStore.savedSearches(account: account).count, 20, "saved searches capped")
    NovagramJobStore.remove(id: "n24", account: account)
    check(!NovagramJobStore.savedSearches(account: account).contains { $0.id == "n24" }, "remove saved search")
    NovagramJobStore.setWatched(5, watched: true, account: account)
    NovagramJobStore.setWatched(6, watched: true, account: account)
    NovagramJobStore.setWatched(5, watched: false, account: account)
    checkEqual(NovagramJobStore.watchedChannels(account: account), [6], "watched channels")
    let filter = NovagramJobFilter(mode: .findCandidates, query: "swift", cityIds: ["tashkent"], formats: [.remote], period: .month, onlyWithSalary: true)
    NovagramJobStore.setLastFilter(filter, account: account)
    checkEqual(NovagramJobStore.lastFilter(account: account), filter, "last filter round trip")
    NovagramJobStore.setLastFilter(NovagramJobFilter(), account: otherAccount)
    check(notifications >= 33, "notification after every write")
    NovagramJobStore.clear(accountRecordId: 7)
    checkEqual(NovagramJobStore.savedSearches(account: account), [], "clear removes account data")
    checkEqual(NovagramJobStore.lastFilter(account: otherAccount), NovagramJobFilter(), "clear keeps other accounts")
    NotificationCenter.default.removeObserver(observer)
    suite.removePersistentDomain(forName: suiteName)
} else {
    check(false, "throwaway defaults suite")
}


let samples = [uzLatinVacancy, ruVacancy, uzCyrillicVacancy, enResume, uzResume, ruResume]
var hashtagFilter = NovagramJobFilter()
checkEqual(hashtagFilter.hashtags(for: .findJob), NovagramJobPresets.hashtags(for: .findJob), "job hashtags default to presets")
checkEqual(hashtagFilter.hashtags(for: .findCandidates), NovagramJobPresets.hashtags(for: .findCandidates), "candidate hashtags default to presets")
check(!hashtagFilter.hasCustomHashtags(for: .findJob), "presets are not custom")
let hashtagLegacyJSON = "{\"mode\":\"findJob\",\"query\":\"ios\"}".data(using: .utf8) ?? Data()
let hashtagLegacy = try? JSONDecoder().decode(NovagramJobFilter.self, from: hashtagLegacyJSON)
check(hashtagLegacy != nil && hashtagLegacy?.jobHashtags == nil && hashtagLegacy?.candidateHashtags == nil, "decoding without hashtag keys gives nil")
hashtagFilter.setHashtags(["#python", " swift ", "PYTHON", "bad-tag", String(repeating: "a", count: 33)], for: .findJob)
checkEqual(hashtagFilter.hashtags(for: .findJob), ["python", "swift"], "custom job hashtags are cleaned and deduplicated")
checkEqual(hashtagFilter.hashtags(for: .findCandidates), NovagramJobPresets.hashtags(for: .findCandidates), "custom job hashtags leave candidate presets")
check(hashtagFilter.hasCustomHashtags(for: .findJob), "changed list is custom")
hashtagFilter.setHashtags((0..<20).map { "tag\($0)" }, for: .findCandidates)
checkEqual(hashtagFilter.hashtags(for: .findCandidates).count, NovagramJobFilter.maxHashtags, "hashtag list is capped at 12")
hashtagFilter.setHashtags([], for: .findJob)
check(hashtagFilter.hashtags(for: .findJob).isEmpty, "empty custom list stays empty")
let encodedHashtags = (try? JSONEncoder().encode(hashtagFilter)).flatMap { try? JSONDecoder().decode(NovagramJobFilter.self, from: $0) }
checkEqual(encodedHashtags, hashtagFilter, "custom hashtags survive encoding")
hashtagFilter.setHashtags(nil, for: .findJob)
checkEqual(hashtagFilter.hashtags(for: .findJob), NovagramJobPresets.hashtags(for: .findJob), "nil resets to presets")

let speedQuery = NovagramJobQuery.parse("python | менеджер -junior")
let start = Date()
for index in 0..<600 {
    let text = samples[index % samples.count]
    _ = NovagramJobPostParser.parse(text)
    _ = speedQuery.matches(text)
}
let elapsed = Date().timeIntervalSince(start) * 1000
print(String(format: "Parsed 600 posts in %.0f ms", elapsed))

check(NovagramJobSpamGuard.isSpamText("#школьники #vacancy #предзаказ #канада"), "hashtag-only post is spam")
check(NovagramJobSpamGuard.isSpamText("#ishbor #karnataka #замечательный"), "three hashtags without text is spam")
check(NovagramJobSpamGuard.isSpamSource(title: "💵 latest | $500-$6676......", username: nil), "price range title is spam")
check(NovagramJobSpamGuard.isSpamText("SwagBucks BUCKS $0.006152"), "token price post is spam")
check(!NovagramJobSpamGuard.isSpamText("iOS developer kerak, maosh $1500-$2500, tel +998901234567"), "salary range is not a token price")
check(!NovagramJobSpamGuard.isSpamText("Sotuvchi kerak. Tel: +998901234567 #ish #vakansiya #toshkent #sotuvchi"), "short vacancy with hashtags is not spam")
print("NovagramJobSearch checks: \(passedCount) passed, \(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
