import Foundation

public enum NovagramJobPresets {
    public static func hashtags(for mode: NovagramJobMode) -> [String] {
        switch mode {
        case .findJob:
            return ["vakansiya", "вакансия", "ish", "работа", "vacancy", "job", "hiring", "ishbor"]
        case .findCandidates:
            return ["rezyume", "резюме", "resume", "ishqidiraman", "cv", "ищуработу", "ish_qidiraman", "opentowork"]
        }
    }

    public static func keywords(for mode: NovagramJobMode) -> [String] {
        switch mode {
        case .findJob:
            return ["vakansiya", "вакансия", "vacancy", "ish bor", "xodim kerak", "требуется", "ishga taklif", "иш бор", "ходим керак", "hiring"]
        case .findCandidates:
            return ["rezyume", "резюме", "resume", "ish qidiryapman", "ищу работу", "ish izlayapman", "иш қидиряпман", "looking for a job", "open to work", "cv"]
        }
    }

    private static func makeCity(_ id: String, en: String, uz: String, ru: String, _ variants: [String]) -> NovagramJobCity {
        var seen = Set<String>()
        let normalized = variants.map(NovagramJobText.normalized).filter { seen.insert($0).inserted }
        return NovagramJobCity(id: id, en: en, uz: uz, ru: ru, variants: normalized)
    }

    public static let cities: [NovagramJobCity] = [
        makeCity("tashkent", en: "Tashkent", uz: "Toshkent", ru: "Ташкент", ["toshkent", "tashkent", "ташкент", "тошкент"]),
        makeCity("samarkand", en: "Samarkand", uz: "Samarqand", ru: "Самарканд", ["samarqand", "samarkand", "самарканд", "самарқанд"]),
        makeCity("bukhara", en: "Bukhara", uz: "Buxoro", ru: "Бухара", ["buxoro", "bukhar", "buhar", "бухар", "бухоро"]),
        makeCity("andijan", en: "Andijan", uz: "Andijon", ru: "Андижан", ["andijon", "andijan", "андижан", "андижон"]),
        makeCity("fergana", en: "Fergana", uz: "Farg'ona", ru: "Фергана", ["farg'ona", "fargona", "fergan", "ферган", "фарғона"]),
        makeCity("namangan", en: "Namangan", uz: "Namangan", ru: "Наманган", ["namangan", "наманган"]),
        makeCity("nukus", en: "Nukus", uz: "Nukus", ru: "Нукус", ["nukus", "нукус"]),
        makeCity("karshi", en: "Karshi", uz: "Qarshi", ru: "Карши", ["qarshi", "karshi", "карши", "қарши"]),
        makeCity("termez", en: "Termez", uz: "Termiz", ru: "Термез", ["termiz", "termez", "термез", "термиз"]),
        makeCity("jizzakh", en: "Jizzakh", uz: "Jizzax", ru: "Джизак", ["jizzax", "jizzakh", "jizzak", "джизак", "жиззах"]),
        makeCity("gulistan", en: "Gulistan", uz: "Guliston", ru: "Гулистан", ["guliston", "gulistan", "гулистан", "гулистон"]),
        makeCity("navoi", en: "Navoi", uz: "Navoiy", ru: "Навои", ["navoiy", "navoi", "навои", "навоий"]),
        makeCity("urgench", en: "Urgench", uz: "Urganch", ru: "Ургенч", ["urganch", "urgench", "ургенч", "урганч"]),
        makeCity("chirchiq", en: "Chirchiq", uz: "Chirchiq", ru: "Чирчик", ["chirchiq", "chirchik", "чирчик", "чирчиқ"]),
        makeCity("kokand", en: "Kokand", uz: "Qo'qon", ru: "Коканд", ["qo'qon", "qoqon", "kokand", "коканд", "қўқон"]),
        makeCity("margilan", en: "Margilan", uz: "Marg'ilon", ru: "Маргилан", ["marg'ilon", "margilon", "margilan", "маргилан", "марғилон"]),
        makeCity("almalyk", en: "Almalyk", uz: "Olmaliq", ru: "Алмалык", ["olmaliq", "almalyk", "almalik", "алмалык", "олмалиқ"]),
        makeCity("angren", en: "Angren", uz: "Angren", ru: "Ангрен", ["angren", "ангрен"]),
        makeCity("moscow", en: "Moscow", uz: "Moskva", ru: "Москва", ["moskv", "moscow", "москв"]),
        makeCity("almaty", en: "Almaty", uz: "Olmaota", ru: "Алматы", ["almaty", "almati", "olmaota", "алматы", "алма-ат", "олмаота"])
    ]

    public static func city(id: String) -> NovagramJobCity? {
        return cities.first(where: { $0.id == id })
    }

    public static let channelDiscoveryQueries: [String] = [
        "vakansiya", "ish bor", "ish e'lonlari", "вакансии ташкент", "работа ташкент", "it jobs uz", "toshkent ish", "rezyume"
    ]
}
