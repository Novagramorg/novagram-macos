import Foundation

// Strings added while porting to Telegram macOS 13.1 (the old fork hard-coded them).
public extension FenixuzL10n {
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

public extension FenixuzL10n {
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

public extension FenixuzL10n {
    var phone_retry: String { pick(en: "Retry", uz: "Qayta urinish", ru: "Повторить") }
}

// Keys of the shared `pro_messager` settings suite (same names as iOS).
public enum FenixuzSettingsKey {
    public static let suite = "pro_messager"
    public static func bool(_ key: String, default value: Bool = false) -> Bool {
        return UserDefaults(suiteName: suite)?.object(forKey: key) as? Bool ?? value
    }
}

public extension FenixuzL10n {
    var askSend_sticker: String { pick(en: "Send this sticker?", uz: "Ushbu stickerni yuborishni tasdiqlaysizmi?", ru: "Отправить этот стикер?") }
    var askSend_voice: String { pick(en: "Send this voice message?", uz: "Ovozli xabarni yuborishni tasdiqlaysizmi?", ru: "Отправить голосовое сообщение?") }
    var askSend_send: String { pick(en: "Send", uz: "Yuborish", ru: "Отправить") }
    var askSend_cancel: String { pick(en: "Cancel", uz: "Bekor qilish", ru: "Отмена") }
}

public extension FenixuzL10n {
    var attach_roundVideo: String { pick(en: "Send as Round Video", uz: "Dumaloq video sifatida yuborish", ru: "Отправить как кружок") }
}
