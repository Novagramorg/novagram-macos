import Foundation

// Strings for the iOS features ported to the Mac in 2026-10 (texts follow the iOS Novagram module).
public extension NovagramL10n {
    var settings_chat_editedHistory_title: String { pick(en: "Edited message history", uz: "Tahrirlangan xabar tarixi", ru: "История правок сообщений") }
    var settings_chat_editedHistory_subtitle: String { pick(en: "Right-click an edited message to see all its previous versions", uz: "Tahrirlangan xabarni o'ng tugma bilan bosib, barcha oldingi versiyalarini ko'ring", ru: "Нажмите правой кнопкой на изменённое сообщение, чтобы увидеть все его прошлые версии") }
    var settings_chat_roundVideo_title: String { pick(en: "Round video from file", uz: "Fayldan dumaloq video", ru: "Круглое видео из файла") }
    var settings_chat_roundVideo_subtitle: String { pick(en: "Adds “Send as Round Video” to the attach menu", uz: "Biriktirish menyusiga «Dumaloq video sifatida yuborish» bandini qo'shadi", ru: "Добавляет «Отправить как кружок» в меню вложений") }
    var settings_chat_forwardHideNames_title: String { pick(en: "Forward Without Name", uz: "Imzosiz forward", ru: "Пересылка без имени") }
    var settings_chat_forwardHideNames_subtitle: String { pick(en: "Adds “Forward without Quotes” to the message menu", uz: "Xabar menyusiga «Imzosiz forward qilish» bandini qo'shadi", ru: "Добавляет «Переслать без автора» в меню сообщения") }

    var settings_autoSticker_title: String { pick(en: "Auto sticker", uz: "Avtomatik sticker", ru: "Авто-стикер") }
    var settings_autoSticker_subtitle: String { pick(en: "Appends the last sent sticker after each text message", uz: "Har matnli xabardan keyin oxirgi yuborilgan stickerni qo'shadi", ru: "После каждого текстового сообщения добавляет последний отправленный стикер") }
    var settings_heartEffect_title: String { pick(en: "Heart effect", uz: "Yurakcha effekti", ru: "Эффект сердечка") }
    var settings_heartEffect_subtitle: String { pick(en: "Adds the ❤️ animated effect to messages you send in private chats", uz: "Shaxsiy chatlarda yuborilgan xabarlarga ❤️ animatsion effektini qo'shadi", ru: "Добавляет анимированный эффект ❤️ к сообщениям в личных чатах") }

    var settings_storyUnlock_title: String { pick(en: "Story saving and quality", uz: "Hikoyalarni saqlash va sifat", ru: "Сохранение и качество историй") }
    var settings_storyUnlock_subtitle: String { pick(en: "Save other people's stories and watch video stories in HD", uz: "Boshqalarning hikoyalarini saqlash, video hikoyalarni HD sifatda ko'rish", ru: "Сохранять чужие истории и смотреть видеоистории в HD") }
    var settings_storyUnlock_warningTitle: String { pick(en: "Turn on story saving and quality?", uz: "Hikoyalarni saqlash va sifat yoqilsinmi?", ru: "Включить сохранение и качество историй?") }
    var settings_storyUnlock_warningText: String { pick(en: "You'll be able to save other people's stories and watch video stories at full quality. Stories the author protected stay unsavable: the option doesn't appear on them. Please respect what people share.", uz: "Boshqalarning hikoyalarini saqlash va video hikoyalarni to'liq sifatda ko'rish mumkin bo'ladi. Muallif himoyalagan hikoyalar saqlanmaydi — ularda bu band chiqmaydi. Boshqalar ulashgan narsani hurmat qiling.", ru: "Вы сможете сохранять чужие истории и смотреть видеоистории в полном качестве. Истории, защищённые автором, сохранить нельзя — для них этот пункт не появляется. Уважайте то, чем делятся другие.") }
    var settings_storyUnlock_warningConfirm: String { pick(en: "Turn On", uz: "Yoqish", ru: "Включить") }
    var settings_translateUnlock_title: String { pick(en: "Translate entire chats", uz: "Butun chatni tarjima qilish", ru: "Переводить чат целиком") }
    var settings_translateUnlock_subtitle: String { pick(en: "Translate a whole chat at once instead of message by message", uz: "Chatni to'liq tarjima qilish, har bir xabarni alohida emas", ru: "Переводить чат целиком, а не каждое сообщение отдельно") }

    var settings_foldersPrompt_title: String { pick(en: "Suggest folders after login", uz: "Kirgandan keyin papka taklifi", ru: "Предлагать папки после входа") }
    var settings_foldersPrompt_subtitle: String { pick(en: "Shows the “Add folders?” prompt after you sign in", uz: "Akkauntga kirgandan keyin «Papkalar qo'shilsinmi?» oynasini ko'rsatadi", ru: "Показывает окно «Добавить папки?» после входа в аккаунт") }
    var foldersPrompt_alertTitle: String { pick(en: "Add folders?", uz: "Papkalar qo'shilsinmi?", ru: "Добавить папки?") }
    var foldersPrompt_alertText: String { pick(en: "Suggested folders will be added: Personal, Groups, Channels, Bots and Unread.", uz: "Tavsiya etilgan papkalar qo'shiladi: Shaxsiy, Guruhlar, Kanallar, Botlar va O'qilmagan.", ru: "Будут добавлены рекомендуемые папки: Личные, Группы, Каналы, Боты и Непрочитанные.") }
    var foldersPrompt_alertConfirm: String { pick(en: "Add", uz: "Qo'shish", ru: "Добавить") }

    var settings_translateConfirm_title: String { pick(en: "Ask to translate on send", uz: "Yuborishda tarjima so'rovi", ru: "Запрос перевода при отправке") }
    var settings_translateConfirm_subtitle: String { pick(en: "Before sending, asks whether to translate or send the original. Turning it on turns off dictation translate", uz: "Yuborishdan oldin tarjima yoki original so'raladi. Yoqilsa diktovka tarjimasi o'chadi", ru: "Перед отправкой спрашивает: перевести или отправить оригинал. Включение отключает перевод диктовки") }
    var translateConfirm_alertTitle: String { pick(en: "Send with translation?", uz: "Xabarni tarjima qilib yuborasizmi?", ru: "Отправить сообщение с переводом?") }
    var translateConfirm_translate: String { pick(en: "Translate & Send", uz: "Tarjima qilib yuborish", ru: "Перевести и отправить") }
    var translateConfirm_original: String { pick(en: "Send Original", uz: "Original yuborish", ru: "Отправить оригинал") }
    var settings_voiceTranslate_title: String { pick(en: "Translate dictated text", uz: "Diktovka matnini tarjima qilish", ru: "Переводить надиктованный текст") }
    var reminder_time_title: String { pick(en: "Reminder time", uz: "Eslatma vaqti", ru: "Время напоминания") }
    var reminder_sound_title: String { pick(en: "Reminder sound", uz: "Eslatma ovozi", ru: "Звук напоминания") }
    var reminder_notificationTitle: String { pick(en: "Unread messages", uz: "O'qilmagan xabarlar", ru: "Непрочитанные сообщения") }
    func reminder_minutesLabel(_ minutes: Int) -> String { pick(en: "\(minutes) min", uz: "\(minutes) daqiqa", ru: "\(minutes) мин") }
    func reminder_notificationBody(_ count: Int) -> String { pick(en: "You have \(count) unread messages. Don't forget to check them.", uz: "Sizda \(count) ta o'qilmagan xabar bor. Ularni ko'rishni unutmang.", ru: "У вас \(count) непрочитанных сообщений. Не забудьте их просмотреть.") }
    func reminder_soundName(_ key: String) -> String {
        switch key {
        case "none": return pick(en: "None", uz: "Yo'q", ru: "Нет")
        case "chime": return pick(en: "Chime", uz: "Jarang", ru: "Перезвон")
        case "glass": return pick(en: "Glass", uz: "Shisha", ru: "Стекло")
        case "bell": return pick(en: "Bell", uz: "Qo'ng'iroq", ru: "Колокол")
        case "note": return pick(en: "Note", uz: "Nota", ru: "Нота")
        case "tritone": return pick(en: "Tri-tone", uz: "Uch ohang", ru: "Три-тон")
        case "marimba": return pick(en: "Marimba", uz: "Marimba", ru: "Маримба")
        case "crystal": return pick(en: "Crystal", uz: "Kristall", ru: "Кристалл")
        case "droplet": return pick(en: "Droplet", uz: "Tomchi", ru: "Капля")
        case "ping": return pick(en: "Ping", uz: "Ping", ru: "Пинг")
        case "pulse": return pick(en: "Pulse", uz: "Puls", ru: "Пульс")
        case "harp": return pick(en: "Harp", uz: "Arfa", ru: "Арфа")
        case "signal": return pick(en: "Signal", uz: "Signal", ru: "Сигнал")
        default: return pick(en: "Default notification sound", uz: "Bildirishnoma ovozi", ru: "Звук уведомления по умолчанию")
        }
    }
    var settings_autoDownloadOff_title: String { pick(en: "Disable auto-download", uz: "Avto-yuklashni o'chirish", ru: "Отключить автозагрузку") }
    var settings_autoDownloadOff_subtitle: String { pick(en: "Turns off media auto-download (Settings → Data and Storage)", uz: "Media avtomatik yuklab olinishini o'chiradi (Sozlamalar → Ma'lumotlar va xotira)", ru: "Отключает автозагрузку медиа (Настройки → Данные и память)") }
    var settings_section_appearance: String { pick(en: "APPEARANCE", uz: "KO'RINISH", ru: "ВНЕШНИЙ ВИД") }
    var settings_lightAccent_title: String { pick(en: "Brand accent in light theme", uz: "Yorqin temada brand rangi", ru: "Акцент бренда в светлой теме") }
    var settings_lightAccent_subtitle: String { pick(en: "Applies Novagram blue as the accent color in the light theme", uz: "Yorqin (oq) temada Novagram ko'k rangini accent sifatida qo'llaydi", ru: "Применяет фирменный синий Novagram в качестве акцента в светлой теме") }
    var settings_lightAccent_footer: String { pick(en: "Affects the light theme only. Takes effect without restarting.", uz: "Faqat yorqin (oq) temaga ta'sir qiladi. Qayta ishga tushirmasdan kuchga kiradi.", ru: "Влияет только на светлую тему. Применяется без перезапуска.") }
    var settingsLink_shareTitle: String { pick(en: "Share Novagram Settings link", uz: "Novagram Settings havolasini ulashish", ru: "Поделиться ссылкой Novagram Settings") }
    var settingsLink_copy: String { pick(en: "Copy link", uz: "Havolani nusxalash", ru: "Копировать ссылку") }
    var settingsLink_share: String { pick(en: "Share link", uz: "Havolani ulashish", ru: "Поделиться ссылкой") }
    var settingsLink_copied: String { pick(en: "Link copied", uz: "Havola nusxalandi", ru: "Ссылка скопирована") }
    var settingsLink_hint: String { pick(en: "Right-click any row to get a link straight to that setting.", uz: "Istalgan qatorni o'ng tugma bilan bosing: o'sha sozlamaning havolasini olasiz.", ru: "Нажмите правой кнопкой на любую строку, чтобы получить ссылку именно на эту настройку.") }
    var developer_adEventsOffTitle: String { pick(en: "Don't send ad events", uz: "Reklama hodisalarini yubormaslik", ru: "Не отправлять события рекламы") }
    var developer_adEventsOffTip: String { pick(en: "Views, clicks and actions of Novagram and Telegram ads are not sent, so an ad shown once per user keeps showing while you test. This device only.", uz: "Novagram va Telegram reklamalarining ko'rish, bosish va harakat hodisalari serverga yuborilmaydi, shuning uchun bir marta ko'rsatiladigan reklama test paytida qayta chiqaveradi. Faqat shu qurilmada.", ru: "Просмотры, клики и действия по рекламе Novagram и Telegram не отправляются, поэтому реклама с одним показом на пользователя продолжает показываться во время теста. Только на этом устройстве.") }
    var search_fromDate: String { pick(en: "From date…", uz: "Sanadan…", ru: "С даты…") }
    var search_toDate: String { pick(en: "To date…", uz: "Sanagacha…", ru: "По дату…") }
    func search_fromDateValue(_ date: String) -> String { pick(en: "From \(date)", uz: "\(date) dan", ru: "С \(date)") }
    func search_toDateValue(_ date: String) -> String { pick(en: "To \(date)", uz: "\(date) gacha", ru: "По \(date)") }
    var search_clearDates: String { pick(en: "Clear dates", uz: "Sanalarni tozalash", ru: "Сбросить даты") }
    var search_unreadOnly: String { pick(en: "Unread only", uz: "Faqat o'qilmaganlar", ru: "Только непрочитанные") }
    var search_mentionsOnly: String { pick(en: "Mentions only", uz: "Faqat mention'lar", ru: "Только упоминания") }
    func search_translatedTitle(_ text: String) -> String { pick(en: "Translated: \(text)", uz: "Tarjima: \(text)", ru: "Перевод: \(text)") }
    var search_translateNone: String { pick(en: "None", uz: "Yo'q", ru: "Нет") }
    var settings_searchTranslateLangs_title: String { pick(en: "Translate into", uz: "Tarjima tillari", ru: "Языки перевода") }
    var search_savedTitle: String { pick(en: "Saved searches", uz: "Saqlangan qidiruvlar", ru: "Сохранённые поиски") }
    var search_savedPinned: String { pick(en: "Pinned", uz: "Qadalgan", ru: "Закреплён") }
    var search_savedPin: String { pick(en: "Pin", uz: "Qadash", ru: "Закрепить") }
    var search_savedUnpin: String { pick(en: "Unpin", uz: "Qadashni olish", ru: "Открепить") }
    var search_savedRemove: String { pick(en: "Remove", uz: "O'chirish", ru: "Удалить") }
    var settings_section_search: String { pick(en: "SEARCH", uz: "QIDIRUV", ru: "ПОИСК") }
    var settings_searchFeatures_title: String { pick(en: "Search features", uz: "Qidiruv imkoniyatlari", ru: "Возможности поиска") }
    var settings_searchFeatures_subtitle: String { pick(en: "Dates, Unread only and Mentions only in global search, \"exact phrase\" and re: inside a chat, and saved searches. Hidden chats stay out of search either way.", uz: "Global qidiruvda sanalar, \"Faqat o'qilmaganlar\" va \"Faqat mention'lar\", chat ichida \"aniq ibora\" va re:, hamda saqlangan qidiruvlar. Yashirin chatlar har holda qidiruvda chiqmaydi.", ru: "Даты, «Только непрочитанные» и «Только упоминания» в глобальном поиске, \"точная фраза\" и re: в чате и сохранённые запросы. Скрытые чаты в поиск не попадают в любом случае.") }
    var settings_searchTranslate_title: String { pick(en: "Search the translated query too", uz: "Tarjima qilingan so'rov bo'yicha ham qidirish", ru: "Искать и по переводу запроса") }
    var settings_searchTranslate_subtitle: String { pick(en: "Messages search also looks for the query translated into the languages chosen below. The query is sent to Telegram's translation service.", uz: "Xabarlar qidiruvi so'rovni quyida tanlangan tillarga tarjima qilib ham qidiradi. So'rov Telegram'ning tarjima xizmatiga yuboriladi.", ru: "Поиск по сообщениям также ищет запрос, переведённый на выбранные ниже языки. Запрос отправляется в сервис перевода Telegram.") }
    var editedHistory_file: String { pick(en: "File", uz: "Fayl", ru: "Файл") }
    var editedHistory_media: String { pick(en: "Media", uz: "Media", ru: "Медиа") }
    var settings_unlimitedPins_title: String { pick(en: "Unlimited Pins", uz: "Cheksiz pin", ru: "Безлимитные закрепы") }
    var settings_unlimitedPins_subtitle: String { pick(en: "Pin up to 1000 chats. Only the first few sync to Telegram, the rest live on this Mac only. Turning this off unpins them.", uz: "1000 tagacha chat pin qiling. Faqat dastlabki bir nechtasi Telegram bilan sinxronlanadi, qolganlari faqat shu Mac'da. O'chirsangiz ular pindan olinadi.", ru: "Закрепляйте до 1000 чатов. С Telegram синхронизируются только первые несколько, остальные только на этом Mac. При отключении они открепляются.") }
    var settings_folderStyle_title: String { pick(en: "Folder display style", uz: "Papka ko'rinishi", ru: "Стиль папок") }
    func settings_folderStyle_label(_ style: String) -> String {
        switch style {
        case "icon": return pick(en: "Icons", uz: "Ikonkalar", ru: "Иконки")
        case "text": return pick(en: "Text", uz: "Matn", ru: "Текст")
        default: return pick(en: "Automatic", uz: "Avtomatik", ru: "Авто")
        }
    }
    var settings_channelHistory_title: String { pick(en: "Channel history button", uz: "Kanal tarixi tugmasi", ru: "Кнопка истории канала") }
    var settings_channelHistory_subtitle: String { pick(en: "Adds “Recent Actions” to the chat list menu of channels and groups you admin", uz: "Siz admin bo'lgan kanal va guruhlar menyusiga «So'nggi amallar» bandini qo'shadi", ru: "Добавляет «Недавние действия» в меню каналов и групп, где вы администратор") }
    var settings_voiceTranslate_subtitle: String { pick(en: "When dictation ends, the text is translated into the auto-translate language. Works when “Ask to translate on send” is off", uz: "Diktovka tugagach matn avto-tarjima tiliga tarjima qilinadi. «Yuborishda tarjima so'rovi» o'chiq bo'lsa ishlaydi", ru: "После диктовки текст переводится на язык автоперевода. Работает, когда «Запрос перевода при отправке» выключен") }

    var callRecording_section: String { pick(en: "Calls", uz: "Qo'ng'iroqlar", ru: "Звонки") }
    var callRecording_title: String { pick(en: "Call recording", uz: "Qo'ng'iroqni yozib olish", ru: "Запись звонков") }
    var callRecording_subtitle: String { pick(en: "Adds a Record button to voice and video calls", uz: "Ovozli va video qo'ng'iroqlarga «Yozish» tugmasini qo'shadi", ru: "Добавляет кнопку «Запись» в аудио- и видеозвонки") }
    var callRecording_saveTo: String { pick(en: "Save to", uz: "Saqlash joyi", ru: "Сохранять в") }
    var callRecording_askEveryTime: String { pick(en: "Ask every time", uz: "Har safar so'rash", ru: "Спрашивать каждый раз") }
    var callRecording_footer: String { pick(en: "Recordings are made and kept only on this Mac. Only you see the REC mark; the other person is not notified. Recording calls without the other person's consent is illegal in some countries.", uz: "Yozuvlar faqat shu Mac'da yaratiladi va saqlanadi. REC belgisini faqat siz ko'rasiz, suhbatdoshingizga xabar berilmaydi. Ba'zi mamlakatlarda suhbatdoshning roziligisiz qo'ng'iroqni yozib olish qonunga zid.", ru: "Записи создаются и хранятся только на этом Mac. Значок REC видите только вы, собеседник не получает уведомления. В некоторых странах запись звонков без согласия собеседника запрещена законом.") }
    var callRecording_chooseMessage: String { pick(en: "Choose a folder for call recordings", uz: "Qo'ng'iroq yozuvlari uchun papkani tanlang", ru: "Выберите папку для записей звонков") }
    var callRecording_choose: String { pick(en: "Choose", uz: "Tanlash", ru: "Выбрать") }
    var callRecording_chooseFolder: String { pick(en: "Choose Folder…", uz: "Papka tanlash…", ru: "Выбрать папку…") }
    var callRecording_cancel: String { pick(en: "Cancel", uz: "Bekor qilish", ru: "Отмена") }
    func callRecording_action(_ isRecording: Bool) -> String { isRecording ? pick(en: "Stop", uz: "To'xtatish", ru: "Стоп") : pick(en: "Record", uz: "Yozish", ru: "Запись") }
    var callRecording_warningTitle: String { pick(en: "Record this call?", uz: "Qo'ng'iroq yozib olinsinmi?", ru: "Записать звонок?") }
    var callRecording_warningText: String { pick(en: "In some countries it is illegal to record a call without the other person's consent. Make sure you are allowed to record it. The recording stays on this Mac.", uz: "Ba'zi mamlakatlarda suhbatdoshning roziligisiz qo'ng'iroqni yozib olish qonunga zid. Yozib olishga ruxsatingiz borligiga ishonch hosil qiling. Yozuv faqat shu Mac'da qoladi.", ru: "В некоторых странах запись звонка без согласия собеседника запрещена законом. Убедитесь, что вам можно его записывать. Запись остаётся только на этом Mac.") }
    var callRecording_continue: String { pick(en: "Continue", uz: "Davom etish", ru: "Продолжить") }
    var callRecording_permissionText: String { pick(en: "Novagram needs permission to record the call window. Open System Settings → Privacy & Security → Screen & System Audio Recording, turn on Novagram, then reopen the app.", uz: "Qo'ng'iroq oynasini yozib olish uchun Novagram'ga ruxsat kerak. System Settings → Privacy & Security → Screen & System Audio Recording bo'limida Novagram'ni yoqing, so'ng ilovani qayta oching.", ru: "Novagram нужно разрешение на запись окна звонка. Откройте Системные настройки → Конфиденциальность и безопасность → Запись экрана и системного аудио, включите Novagram и перезапустите приложение.") }
    var callRecording_openSettings: String { pick(en: "Open Settings", uz: "Sozlamalarni ochish", ru: "Открыть настройки") }
    var callRecording_saved: String { pick(en: "Call recording saved", uz: "Qo'ng'iroq yozuvi saqlandi", ru: "Запись звонка сохранена") }
    var callRecording_showInFinder: String { pick(en: "Show in Finder", uz: "Finder'da ko'rsatish", ru: "Показать в Finder") }
    var callRecording_failed: String { pick(en: "Call recording failed", uz: "Qo'ng'iroqni yozib bo'lmadi", ru: "Не удалось записать звонок") }
    var callRecording_audioOnly: String { pick(en: "Video was turned on: this recording stays audio only", uz: "Video yoqildi: bu yozuv faqat ovozli bo'lib qoladi", ru: "Включено видео: эта запись останется только аудио") }
    var callRecording_saveFailed: String { pick(en: "Couldn't save the call recording", uz: "Qo'ng'iroq yozuvini saqlab bo'lmadi", ru: "Не удалось сохранить запись звонка") }
    var callRecording_auto_title: String { pick(en: "Record every call automatically", uz: "Har bir qo'ng'iroqni avtomatik yozib olish", ru: "Записывать каждый звонок автоматически") }
    var callRecording_auto_subtitle: String { pick(en: "Recording starts as soon as the call screen opens", uz: "Qo'ng'iroq oynasi ochilishi bilan yozish boshlanadi", ru: "Запись начинается сразу при открытии окна звонка") }
    var callDataSaving_title: String { pick(en: "Use less data for calls", uz: "Qo'ng'iroqlarda kamroq trafik", ru: "Экономия трафика в звонках") }
    var callDataSaving_subtitle: String { pick(en: "Lower audio and video quality; applies to new calls", uz: "Ovoz va video sifati pasayadi; yangi qo'ng'iroqlarga ta'sir qiladi", ru: "Ниже качество звука и видео; действует для новых звонков") }
    var callDevices_microphone: String { pick(en: "Microphone", uz: "Mikrofon", ru: "Микрофон") }
    var callDevices_speaker: String { pick(en: "Speaker", uz: "Karnay", ru: "Динамик") }
    var callDevices_default: String { pick(en: "System Default", uz: "Tizim bo'yicha", ru: "Системное по умолчанию") }
    var callWeakNetwork_text: String { pick(en: "Weak connection", uz: "Aloqa sust", ru: "Слабое соединение") }
    var callWeakNetwork_turnOffVideo: String { pick(en: "Turn off my video", uz: "Videomni o'chirish", ru: "Выключить моё видео") }
}
