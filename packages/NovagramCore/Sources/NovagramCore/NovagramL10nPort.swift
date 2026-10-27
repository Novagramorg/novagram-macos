import Foundation

// Strings added while porting to Telegram macOS 13.1 (the old fork hard-coded them).
public extension NovagramL10n {
    var peerInfo_idLabel: String {
        pick(en: "ID", uz: "ID", ru: "ID")
    }

    var peerInfo_copyId: String {
        pick(en: "Copy ID", uz: "ID'ni nusxalash", ru: "Скопировать ID")
    }

    var peerInfo_idCopied: String {
        pick(en: "ID copied", uz: "ID nusxalandi", ru: "ID скопирован")
    }
}

public extension NovagramL10n {
    var info_title: String { "Novagram Info" }
    var info_type: String { pick(en: "Type", uz: "Turi", ru: "Тип") }
    var info_dataCenter: String { pick(en: "Data Center", uz: "Data markaz", ru: "Дата-центр") }
    var info_username: String { pick(en: "Username", uz: "Username", ru: "Имя пользователя") }
    var info_status: String { pick(en: "Status", uz: "Holati", ru: "Статус") }
    var info_premium: String { "Telegram Premium" }
    var info_none: String { pick(en: "None", uz: "Yo'q", ru: "Нет") }
    var info_unknown: String { pick(en: "Unknown", uz: "Noma'lum", ru: "Неизвестно") }
    var info_yes: String { pick(en: "Yes", uz: "Ha", ru: "Да") }
    var info_no: String { pick(en: "No", uz: "Yo'q", ru: "Нет") }
    var info_clean: String { pick(en: "Clean", uz: "Toza", ru: "Чистый") }
    var info_scam: String { "Scam" }
    var info_fake: String { "Fake" }
    var info_typeUser: String { pick(en: "User", uz: "Foydalanuvchi", ru: "Пользователь") }
    var info_typeBot: String { pick(en: "Bot", uz: "Bot", ru: "Бот") }
    var info_typeGroup: String { pick(en: "Group", uz: "Guruh", ru: "Группа") }
    var info_typeSupergroup: String { pick(en: "Supergroup", uz: "Superguruh", ru: "Супергруппа") }
    var info_typeChannel: String { pick(en: "Channel", uz: "Kanal", ru: "Канал") }
    var info_typeSecretChat: String { pick(en: "Secret Chat", uz: "Maxfiy chat", ru: "Секретный чат") }
}

public extension NovagramL10n {
    var phone_retry: String { pick(en: "Retry", uz: "Qayta urinish", ru: "Повторить") }
}

// Keys of the shared `pro_messager` settings suite (same names as iOS).
public enum NovagramSettingsKey {
    public static let suite = "pro_messager"
    public static func bool(_ key: String, default value: Bool = false) -> Bool {
        return UserDefaults(suiteName: suite)?.object(forKey: key) as? Bool ?? value
    }
}

public extension NovagramL10n {
    var askSend_sticker: String { pick(en: "Send this sticker?", uz: "Ushbu stickerni yuborishni tasdiqlaysizmi?", ru: "Отправить этот стикер?") }
    var askSend_voice: String { pick(en: "Send this voice message?", uz: "Ovozli xabarni yuborishni tasdiqlaysizmi?", ru: "Отправить голосовое сообщение?") }
    var askSend_send: String { pick(en: "Send", uz: "Yuborish", ru: "Отправить") }
    var askSend_cancel: String { pick(en: "Cancel", uz: "Bekor qilish", ru: "Отмена") }
}

public extension NovagramL10n {
    var attach_roundVideo: String { pick(en: "Send as Round Video", uz: "Dumaloq video sifatida yuborish", ru: "Отправить как кружок") }
}

public extension NovagramL10n {
    var hiddenChats_hide: String { pick(en: "Hide Chat", uz: "Chatni yashirish", ru: "Скрыть чат") }
    var hiddenChats_unhide: String { pick(en: "Unhide Chat", uz: "Yashirin chatlardan chiqarish", ru: "Показать чат") }
}

public extension NovagramL10n {
    var stt_buttonTip: String { pick(en: "Speech to Text", uz: "Ovozni matnga", ru: "Голос в текст") }
    var stt_recordingTip: String { pick(en: "Listening… click to stop", uz: "Tinglanmoqda… to'xtatish uchun bosing", ru: "Слушаю… нажмите, чтобы остановить") }
}

public extension NovagramL10n {
    var settings_askVoice_title: String { pick(en: "Confirm voice messages", uz: "Ovozli xabarni tasdiqlash", ru: "Подтверждать голосовые") }
    var settings_askVoice_subtitle: String { pick(en: "Ask before sending", uz: "Yuborishdan oldin tasdiq so'rash", ru: "Спрашивать перед отправкой") }
    var settings_askSticker_title: String { pick(en: "Confirm stickers", uz: "Stickerni tasdiqlash", ru: "Подтверждать стикеры") }
    var settings_askSticker_subtitle: String { pick(en: "Ask before sending a sticker", uz: "Sticker yuborishdan oldin tasdiq so'rash", ru: "Спрашивать перед отправкой стикера") }
    var settings_section_automation: String { pick(en: "AUTOMATION & FOLDERS", uz: "AVTOMATLASHTIRISH VA JILDLAR", ru: "АВТОМАТИЗАЦИЯ И ПАПКИ") }
    var settings_unreadReminder_title: String { pick(en: "Unread message reminder", uz: "O'qilmagan xabarlar eslatmasi", ru: "Напоминание о непрочитанных") }
    var settings_unreadReminder_subtitle: String { pick(en: "Get a reminder when messages stay unread", uz: "O'qilmagan xabarlar mavjud bo'lsa bildirishnoma yuborish", ru: "Напоминать, если сообщения остаются непрочитанными") }
    var settings_autoApprove_title: String { pick(en: "Auto-approve join requests", uz: "So'rovlarni avto-qabul qilish", ru: "Автопринятие заявок") }
    var settings_autoApprove_subtitle: String { pick(en: "Approve join requests in the groups and channels you admin", uz: "Admin kanallarda qo'shilish so'rovlarini avtomatik tasdiqlash", ru: "Одобрять заявки в группах и каналах, где вы админ") }
    var settings_unlimitedFolders_title: String { pick(en: "Unlimited folders", uz: "Cheksiz papkalar", ru: "Безлимитные папки") }
    var settings_unlimitedFolders_subtitle: String { pick(en: "Lift the 10-folder limit (30 with Premium)", uz: "10 ta papka limitini olib tashlaydi (Premium'da 30)", ru: "Снимает лимит в 10 папок (30 с Premium)") }
    var quickMenu_ghostEnable: String { pick(en: "Enable Ghost Mode", uz: "Ghost rejimini yoqish", ru: "Включить режим призрака") }
    var quickMenu_ghostDisable: String { pick(en: "Disable Ghost Mode", uz: "Ghost rejimini o'chirish", ru: "Выключить режим призрака") }
    var quickMenu_hiddenShow: String { pick(en: "Show Hidden Chats", uz: "Yashirin chatlarni ko'rsatish", ru: "Показать скрытые чаты") }
    var quickMenu_hiddenHide: String { pick(en: "Hide Hidden Chats", uz: "Yashirin chatlarni yashirish", ru: "Скрыть скрытые чаты") }
    var quickMenu_novagramSettings: String { pick(en: "Novagram Settings", uz: "Novagram sozlamalari", ru: "Настройки Novagram") }
    var settings_suggestedFolders_title: String { pick(en: "Create suggested folders", uz: "Tavsiya etilgan jildlarni yaratish", ru: "Создать рекомендуемые папки") }
    var settings_suggestedFolders_subtitle: String { pick(en: "Personal, Groups, Channels, Bots, Unread", uz: "Shaxsiy, Guruhlar, Kanallar, Botlar, O'qilmagan", ru: "Личные, Группы, Каналы, Боты, Непрочитанные") }
    var settings_suggestedFolders_done: String { pick(en: "Suggested folders created", uz: "Tavsiya etilgan jildlar muvaffaqiyatli yaratildi!", ru: "Рекомендуемые папки созданы") }
    var settings_automationFooter: String { pick(en: "Automation for folders and channel subscribers.", uz: "Jildlar va kanal obunachilarini avtomatlashtirish imkoniyatlari.", ru: "Автоматизация папок и подписчиков каналов.") }
}
