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
}
