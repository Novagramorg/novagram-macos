import Foundation

public extension NovagramL10n {
    var jobSearch_title: String { pick(en: "Job search", uz: "Ish va xodim qidirish", ru: "Поиск работы и сотрудников") }
    var jobSearch_tab: String { pick(en: "Jobs", uz: "Ish", ru: "Работа") }
    var jobSearch_modeFindJob: String { pick(en: "Find a job", uz: "Ish topish", ru: "Найти работу") }
    var jobSearch_modeFindCandidates: String { pick(en: "Find candidates", uz: "Xodim topish", ru: "Найти сотрудников") }
    var jobSearch_queryHeader: String { pick(en: "Role or skills", uz: "Lavozim yoki ko'nikmalar", ru: "Должность или навыки") }
    var jobSearch_queryPlaceholder: String { pick(en: "iOS developer", uz: "iOS dasturchi", ru: "iOS-разработчик") }
    var jobSearch_queryHint: String { pick(en: "iOS | swift: any of the words. -junior: without the word. \"to'liq stavka\": exact phrase. #python: posts with this hashtag.", uz: "iOS | swift: so'zlardan biri. -junior: bu so'zsiz. \"to'liq stavka\": aynan shu ibora. #python: shu heshtegli postlar.", ru: "iOS | swift: любое из слов. -junior: без слова. \"to'liq stavka\": точная фраза. #python: посты с этим хештегом.") }
    var jobSearch_filtersHeader: String { pick(en: "Filters", uz: "Filtrlar", ru: "Фильтры") }
    var jobSearch_city: String { pick(en: "City", uz: "Shahar", ru: "Город") }
    var jobSearch_any: String { pick(en: "Any", uz: "Istalgan", ru: "Любой") }
    var jobSearch_format: String { pick(en: "Format", uz: "Format", ru: "Формат") }
    var jobSearch_formatOffice: String { pick(en: "Office", uz: "Ofis", ru: "Офис") }
    var jobSearch_formatRemote: String { pick(en: "Remote", uz: "Masofaviy", ru: "Удалённо") }
    var jobSearch_formatHybrid: String { pick(en: "Hybrid", uz: "Gibrid", ru: "Гибрид") }
    var jobSearch_period: String { pick(en: "Period", uz: "Davr", ru: "Период") }
    var jobSearch_periodDay: String { pick(en: "Last 24 hours", uz: "Oxirgi 24 soat", ru: "За 24 часа") }
    var jobSearch_periodWeek: String { pick(en: "Last week", uz: "Oxirgi hafta", ru: "За неделю") }
    var jobSearch_periodMonth: String { pick(en: "Last month", uz: "Oxirgi oy", ru: "За месяц") }
    var jobSearch_periodAny: String { pick(en: "Any time", uz: "Istalgan vaqt", ru: "За всё время") }
    var jobSearch_onlySalary: String { pick(en: "Only with salary", uz: "Faqat maosh ko'rsatilganlar", ru: "Только с зарплатой") }
    var jobSearch_languages: String { pick(en: "Convert languages", uz: "Tillarga o'girish", ru: "Перевод на языки") }
    var jobSearch_languagesNone: String { pick(en: "None", uz: "Hech biri", ru: "Нет") }
    var jobSearch_languagesNote: String { pick(en: "Translations go through Telegram's translation service; Uzbek Latin and Cyrillic are converted on this Mac. None: the query is searched as typed.", uz: "Tarjima Telegram tarjima xizmati orqali bajariladi; o'zbek lotin va kirill yozuvi shu Mac'da almashtiriladi. Hech biri: so'rov yozilganidek qidiriladi.", ru: "Перевод выполняет сервис перевода Telegram; узбекская латиница и кириллица меняются на этом Mac. Нет: запрос ищется как введён.") }
    var jobSearch_sourcesHeader: String { pick(en: "Sources", uz: "Manbalar", ru: "Источники") }
    var jobSearch_sourceHashtags: String { pick(en: "Public hashtag posts", uz: "Ochiq heshteg postlari", ru: "Публичные посты по хештегам") }
    var jobSearch_hashtagAddTitle: String { pick(en: "Add a hashtag", uz: "Heshteg qo'shish", ru: "Добавить хештег") }
    var jobSearch_hashtagAddInfo: String { pick(en: "Letters, digits and _ only, up to 32 characters.", uz: "Faqat harf, raqam va _, ko'pi bilan 32 belgi.", ru: "Только буквы, цифры и _, не больше 32 символов.") }
    var jobSearch_hashtagAdd: String { pick(en: "Add", uz: "Qo'shish", ru: "Добавить") }
    var jobSearch_hashtagInvalid: String { pick(en: "Use letters, digits and _ only, up to 32 characters", uz: "Faqat harf, raqam va _ ishlating, ko'pi bilan 32 belgi", ru: "Используйте только буквы, цифры и _, не больше 32 символов") }
    var jobSearch_hashtagsReset: String { pick(en: "Reset", uz: "Tiklash", ru: "Сбросить") }
    var jobSearch_sourceMyChats: String { pick(en: "My chats", uz: "Mening chatlarim", ru: "Мои чаты") }
    var jobSearch_sourceWatched: String { pick(en: "Watched channels", uz: "Kuzatilayotgan kanallar", ru: "Отслеживаемые каналы") }
    var jobSearch_sourceGlobal: String { pick(en: "All public posts", uz: "Barcha ochiq postlar", ru: "Все публичные посты") }
    var jobSearch_globalSearch: String { pick(en: "Search all public posts", uz: "Barcha ochiq postlardan qidirish", ru: "Искать во всех публичных постах") }
    func jobSearch_globalQuota(_ remaining: Int, _ total: Int) -> String { String(format: pick(en: "%d of %d free searches left today", uz: "Bugun %d/%d bepul qidiruv qoldi", ru: "Осталось %d из %d бесплатных поисков сегодня"), remaining, total) }
    func jobSearch_globalResets(_ time: String) -> String { String(format: pick(en: "Free searches are used up. They reset at %@", uz: "Bepul qidiruvlar tugadi. %@ da yangilanadi", ru: "Бесплатные поиски закончились. Обновятся в %@"), time) }
    var jobSearch_globalPremiumOnly: String { pick(en: "Available with Premium", uz: "Premium bilan mavjud", ru: "Доступно с Premium") }
    var jobSearch_resultsHeader: String { pick(en: "Results", uz: "Natijalar", ru: "Результаты") }
    var jobSearch_empty: String { pick(en: "Nothing found. Try other words or a longer period.", uz: "Hech narsa topilmadi. Boshqa so'zlar yoki uzunroq davrni sinab ko'ring.", ru: "Ничего не найдено. Попробуйте другие слова или более долгий период.") }
    var jobSearch_emptyQuery: String { pick(en: "Type a role or pick filters to start.", uz: "Boshlash uchun lavozimni yozing yoki filtrlarni tanlang.", ru: "Введите должность или выберите фильтры.") }
    func jobSearch_sourceFailed(_ source: String) -> String { String(format: pick(en: "Could not search: %@", uz: "Qidirib bo'lmadi: %@", ru: "Не удалось выполнить поиск: %@"), source) }
    var jobSearch_loadMore: String { pick(en: "Load more", uz: "Yana yuklash", ru: "Загрузить ещё") }
    var jobSearch_openPost: String { pick(en: "Open post", uz: "Postni ochish", ru: "Открыть пост") }
    var jobSearch_write: String { pick(en: "Write", uz: "Yozish", ru: "Написать") }
    func jobSearch_writeTo(_ target: String) -> String { String(format: pick(en: "Write %@", uz: "%@ ga yozish", ru: "Написать %@"), target) }
    var jobSearch_latestVacancies: String { pick(en: "Latest vacancies", uz: "Oxirgi vakansiyalar", ru: "Последние вакансии") }
    var jobSearch_latestResumes: String { pick(en: "Latest resumes", uz: "Oxirgi rezyumelar", ru: "Последние резюме") }
    var jobSearch_roles: [String] { pick(en: "Sales, Developer, Driver, Accountant, Operator, Cook", uz: "Sotuvchi, Dasturchi, Haydovchi, Buxgalter, Operator, Oshpaz", ru: "Продавец, Разработчик, Водитель, Бухгалтер, Оператор, Повар").components(separatedBy: ", ") }
    var jobSearch_copyContact: String { pick(en: "Copy contact", uz: "Kontaktni nusxalash", ru: "Скопировать контакт") }
    var jobSearch_copied: String { pick(en: "Copied", uz: "Nusxalandi", ru: "Скопировано") }
    func jobSearch_experience(_ years: Int) -> String { String(format: pick(en: "%d+ yrs", uz: "%d+ yil", ru: "%d+ лет"), years) }
    var jobSearch_negotiable: String { pick(en: "Negotiable", uz: "Kelishiladi", ru: "Договорная") }
    var jobSearch_channelsHeader: String { pick(en: "Job channels", uz: "Ish kanallari", ru: "Каналы с вакансиями") }
    var jobSearch_channelsEmpty: String { pick(en: "Watched channels are searched with your query. Add some with Find channels.", uz: "Kuzatilayotgan kanallar so'rovingiz bo'yicha qidiriladi. Kanallarni topish orqali qo'shing.", ru: "В отслеживаемых каналах ищется ваш запрос. Добавьте их через «Найти каналы».") }
    var jobSearch_findChannels: String { pick(en: "Find channels", uz: "Kanallarni topish", ru: "Найти каналы") }
    var jobSearch_watch: String { pick(en: "Watch", uz: "Kuzatish", ru: "Отслеживать") }
    var jobSearch_watching: String { pick(en: "Watching", uz: "Kuzatilmoqda", ru: "Отслеживается") }
    var jobSearch_join: String { pick(en: "Join", uz: "A'zo bo'lish", ru: "Вступить") }
    var jobSearch_remove: String { pick(en: "Remove", uz: "O'chirish", ru: "Удалить") }
    var jobSearch_savedHeader: String { pick(en: "Saved job searches", uz: "Saqlangan ish qidiruvlari", ru: "Сохранённые поиски работы") }
    var jobSearch_saveCurrent: String { pick(en: "Save this search", uz: "Bu qidiruvni saqlash", ru: "Сохранить этот поиск") }
    func jobSearch_savedLimit(_ limit: Int) -> String { String(format: pick(en: "Limit reached: up to %d saved searches. Remove one first.", uz: "Limit tugadi: ko'pi bilan %d ta saqlangan qidiruv. Avval bittasini o'chiring.", ru: "Достигнут лимит: не больше %d сохранённых поисков. Сначала удалите один."), limit) }
    var jobSearch_alertsOn: String { pick(en: "Alerts on", uz: "Bildirishnoma yoqilgan", ru: "Уведомления включены") }
    var jobSearch_alertsOff: String { pick(en: "Alerts off", uz: "Bildirishnoma o'chirilgan", ru: "Уведомления выключены") }
    var jobSearch_turnAlertsOn: String { pick(en: "Turn alerts on", uz: "Bildirishnomani yoqish", ru: "Включить уведомления") }
    var jobSearch_turnAlertsOff: String { pick(en: "Turn alerts off", uz: "Bildirishnomani o'chirish", ru: "Выключить уведомления") }
    func jobSearch_alertBody(_ count: Int, _ title: String) -> String { String(format: pick(en: "%d new: %@", uz: "%d ta yangi: %@", ru: "%d новых: %@"), count, title) }
}
