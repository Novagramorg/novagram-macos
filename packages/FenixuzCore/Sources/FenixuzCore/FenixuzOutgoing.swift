import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

// Transforms applied to every outgoing message (Settings → Novagram → Messages):
// auto text suffix, auto translate, one text style, heart effect, a sticker after each text message.
public enum FenixuzOutgoing {
    // Telegram's built-in heart message effect.
    public static let heartEffectId: Int64 = 5159385139981059251

    private static let lastSentSticker = Atomic<TelegramMediaFile?>(value: nil)

    private static var defaults: UserDefaults? {
        return UserDefaults(suiteName: "pro_messager")
    }

    // The text with the user's suffix appended, or nil when auto text is off or the text is empty.
    public static func withAutoText(_ text: String) -> String? {
        guard defaults?.bool(forKey: "auto_text_enabled") == true, let suffix = defaults?.string(forKey: "auto_text_content"), !suffix.isEmpty else {
            return nil
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text + "\n" + suffix
    }

    public static var autoTranslateLanguage: String? {
        guard defaults?.bool(forKey: "auto_translate_enabled") == true, let lang = defaults?.string(forKey: "auto_translate_lang"), !lang.isEmpty else {
            return nil
        }
        return lang
    }

    // The entity covering the whole text for the selected style, `length` in UTF-16 units.
    public static func styleEntities(length: Int) -> [MessageTextEntity] {
        guard length > 0 else {
            return []
        }
        let type: MessageTextEntityType
        switch FenixuzTextStyle.current {
        case .none:
            return []
        case .bold:
            type = .Bold
        case .italic:
            type = .Italic
        case .monospace:
            type = .Code
        case .strikethrough:
            type = .Strikethrough
        case .underline:
            type = .Underline
        case .spoiler:
            type = .Spoiler
        }
        return [MessageTextEntity(range: 0 ..< length, type: type)]
    }

    public static func effectId(_ selected: Int64?) -> Int64? {
        if let selected {
            return selected
        }
        return defaults?.bool(forKey: "heart_effect_enabled") == true ? heartEffectId : nil
    }

    public static func recordSent(_ media: [Media]) {
        for item in media {
            if let file = item as? TelegramMediaFile, file.isSticker {
                _ = lastSentSticker.swap(file)
            }
        }
    }

    // Sends the last sticker the user sent after a text message, when auto sticker is on.
    public static func sendAutoSticker<T>(after value: T, account: Account, peerId: PeerId, threadId: Int64?, replyId: EngineMessageReplySubject?, replyStoryId: StoryId?) -> Signal<T, NoError> {
        guard defaults?.bool(forKey: "auto_sticker_enabled") == true, let sticker = lastSentSticker.with({ $0 }) else {
            return .single(value)
        }
        let message = EnqueueMessage.message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: sticker), threadId: threadId, replyToMessageId: replyId, replyToStoryId: replyStoryId, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        return enqueueMessages(account: account, peerId: peerId, messages: [message]) |> map { _ in
            return value
        }
    }
}
