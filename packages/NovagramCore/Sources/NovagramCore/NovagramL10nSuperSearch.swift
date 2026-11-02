import Foundation

public extension NovagramL10n {
    var superSearch_title: String { pick(en: "Super search", uz: "Super qidiruv", ru: "Суперпоиск") }
    var superSearch_tab: String { pick(en: "Super search", uz: "Super qidiruv", ru: "Суперпоиск") }
    var superSearch_queryHeader: String { pick(en: "Search", uz: "Qidiruv", ru: "Поиск") }
    var superSearch_queryPlaceholder: String { pick(en: "Words, a name or a #hashtag", uz: "So'zlar, nom yoki #heshteg", ru: "Слова, название или #хештег") }
    var superSearch_queryHint: String { pick(en: "news | sport: any of the words. -ads: without the word. \"exact phrase\": this phrase only. #tag: posts with this hashtag.", uz: "yangilik | sport: so'zlardan biri. -reklama: bu so'zsiz. \"aynan ibora\": faqat shu ibora. #teg: shu heshtegli postlar.", ru: "новости | спорт: любое из слов. -реклама: без слова. \"точная фраза\": только эта фраза. #тег: посты с этим хештегом.") }
    var superSearch_filtersHeader: String { pick(en: "Filters", uz: "Filtrlar", ru: "Фильтры") }
    var superSearch_all: String { pick(en: "All", uz: "Hammasi", ru: "Все") }
    var superSearch_period: String { pick(en: "Period", uz: "Davr", ru: "Период") }
    var superSearch_periodDay: String { pick(en: "Last 24 hours", uz: "Oxirgi 24 soat", ru: "За 24 часа") }
    var superSearch_periodWeek: String { pick(en: "Last week", uz: "Oxirgi hafta", ru: "За неделю") }
    var superSearch_periodMonth: String { pick(en: "Last month", uz: "Oxirgi oy", ru: "За месяц") }
    var superSearch_periodYear: String { pick(en: "Last year", uz: "Oxirgi yil", ru: "За год") }
    var superSearch_periodAny: String { pick(en: "Any time", uz: "Istalgan vaqt", ru: "За всё время") }
    var superSearch_chatKinds: String { pick(en: "Chat type", uz: "Chat turi", ru: "Тип чата") }
    var superSearch_chatPrivate: String { pick(en: "Private chats", uz: "Shaxsiy chatlar", ru: "Личные чаты") }
    var superSearch_chatGroup: String { pick(en: "Groups", uz: "Guruhlar", ru: "Группы") }
    var superSearch_chatChannel: String { pick(en: "Channels", uz: "Kanallar", ru: "Каналы") }
    var superSearch_chatBot: String { pick(en: "Bots", uz: "Botlar", ru: "Боты") }
    var superSearch_mediaKinds: String { pick(en: "Media", uz: "Media", ru: "Медиа") }
    var superSearch_mediaText: String { pick(en: "Text", uz: "Matn", ru: "Текст") }
    var superSearch_mediaPhoto: String { pick(en: "Photos", uz: "Rasmlar", ru: "Фото") }
    var superSearch_mediaVideo: String { pick(en: "Videos", uz: "Videolar", ru: "Видео") }
    var superSearch_mediaFile: String { pick(en: "Files", uz: "Fayllar", ru: "Файлы") }
    var superSearch_mediaLink: String { pick(en: "Links", uz: "Havolalar", ru: "Ссылки") }
    var superSearch_mediaVoice: String { pick(en: "Voice messages", uz: "Ovozli xabarlar", ru: "Голосовые сообщения") }
    var superSearch_mediaMusic: String { pick(en: "Music", uz: "Musiqa", ru: "Музыка") }
    var superSearch_hideSpam: String { pick(en: "Hide spam", uz: "Spamni yashirish", ru: "Скрыть спам") }
    var superSearch_languages: String { pick(en: "Convert languages", uz: "Tillarga o'girish", ru: "Перевод на языки") }
    var superSearch_languagesNone: String { pick(en: "None", uz: "Hech biri", ru: "Нет") }
    var superSearch_languagesNote: String { pick(en: "Translations go through Telegram's translation service; Uzbek Latin and Cyrillic are converted on this device. None: the query is searched as typed.", uz: "Tarjima Telegram tarjima xizmati orqali bajariladi; o'zbek lotin va kirill yozuvi shu qurilmada almashtiriladi. Hech biri: so'rov yozilganidek qidiriladi.", ru: "Перевод выполняет сервис перевода Telegram; узбекская латиница и кириллица меняются на этом устройстве. Нет: запрос ищется как введён.") }
    var superSearch_sourcesHeader: String { pick(en: "Sources", uz: "Manbalar", ru: "Источники") }
    var superSearch_sourceMyChats: String { pick(en: "My chats", uz: "Mening chatlarim", ru: "Мои чаты") }
    var superSearch_sourcePublicChats: String { pick(en: "Public chats and channels", uz: "Ochiq chat va kanallar", ru: "Публичные чаты и каналы") }
    var superSearch_sourceChannelPosts: String { pick(en: "Posts in the found channels", uz: "Topilgan kanallardagi postlar", ru: "Посты в найденных каналах") }
    var superSearch_sourceHashtags: String { pick(en: "Public hashtag posts", uz: "Ochiq heshteg postlari", ru: "Публичные посты по хештегам") }
    var superSearch_sourceGlobal: String { pick(en: "All public posts", uz: "Barcha ochiq postlar", ru: "Все публичные посты") }
    var superSearch_sourceArchive: String { pick(en: "Edited and deleted", uz: "Tahrirlangan va o'chirilgan", ru: "Изменённые и удалённые") }
    var superSearch_globalSearch: String { pick(en: "Search all public posts", uz: "Barcha ochiq postlardan qidirish", ru: "Искать во всех публичных постах") }
    func superSearch_globalQuota(_ remaining: Int, _ total: Int) -> String { String(format: pick(en: "%d of %d free searches left today", uz: "Bugun %d/%d bepul qidiruv qoldi", ru: "Осталось %d из %d бесплатных поисков сегодня"), remaining, total) }
    func superSearch_globalResets(_ time: String) -> String { String(format: pick(en: "Free searches are used up. They reset at %@", uz: "Bepul qidiruvlar tugadi. %@ da yangilanadi", ru: "Бесплатные поиски закончились. Обновятся в %@"), time) }
    var superSearch_globalPremiumOnly: String { pick(en: "Available with Premium", uz: "Premium bilan mavjud", ru: "Доступно с Premium") }
    var superSearch_peersHeader: String { pick(en: "Chats and channels", uz: "Chat va kanallar", ru: "Чаты и каналы") }
    var superSearch_messagesHeader: String { pick(en: "Messages", uz: "Xabarlar", ru: "Сообщения") }
    func superSearch_found(_ count: Int) -> String { String(format: pick(en: "Found: %d", uz: "Topildi: %d", ru: "Найдено: %d"), count) }
    var superSearch_searching: String { pick(en: "Searching…", uz: "Qidirilmoqda…", ru: "Идёт поиск…") }
    func superSearch_sourceFailed(_ source: String) -> String { String(format: pick(en: "Could not search: %@", uz: "Qidirib bo'lmadi: %@", ru: "Не удалось выполнить поиск: %@"), source) }
    func superSearch_loadMore(_ source: String) -> String { String(format: pick(en: "Load more: %@", uz: "Yana yuklash: %@", ru: "Загрузить ещё: %@"), source) }
    var superSearch_empty: String { pick(en: "Nothing found. Try other words, more sources or a longer period.", uz: "Hech narsa topilmadi. Boshqa so'zlar, ko'proq manba yoki uzunroq davrni sinab ko'ring.", ru: "Ничего не найдено. Попробуйте другие слова, больше источников или более долгий период.") }
    var superSearch_emptyQuery: String { pick(en: "Type anything to search your chats, public chats, channels and hashtags at once.", uz: "Chatlaringiz, ochiq chatlar, kanallar va heshteglardan birdaniga qidirish uchun istalgan narsani yozing.", ru: "Введите что угодно, чтобы искать сразу в ваших чатах, публичных чатах, каналах и хештегах.") }
    var superSearch_deleted: String { pick(en: "deleted", uz: "o'chirilgan", ru: "удалено") }
}
