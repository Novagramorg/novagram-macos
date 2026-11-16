import Foundation
import Postbox
import TelegramCore
import Localization
import NovagramUzScriptCore

// "Yangi alifbo": Uzbek text goes out in the chat's script or the 2027 Latin, and can be shown in the 2027 Latin.
// The converter, the settings and the texts live in NovagramUzScriptKit (shared with iOS); this file maps Telegram entities.
public enum NovagramUzScript {
    private static let maxMessageLength = 4096

    // One outgoing text piece: the chat's own script first, else the global switch. Unchanged when the text is not Uzbek.
    public static func outgoing(_ text: String, attributes: [MessageAttribute], peerId: PeerId) -> (String, [MessageAttribute]) {
        guard let target = UzScriptSettings().effectiveSendScript(peerKey: peerId.toInt64()) else {
            return (text, attributes)
        }
        guard let converted = convert(text, attributes: attributes, to: target) else {
            return (text, attributes)
        }
        // A longer result than Telegram accepts would fail to send, so the original goes out instead.
        guard converted.0.utf16.count <= maxMessageLength else {
            return (text, attributes)
        }
        return converted
    }

    // The profile menu item while "Lotin ↔ Кирилл" is on: its title, and the action that flips the chat between
    // Cyrillic and the default script and returns the confirmation text.
    public static func chatMenuToggle(peerId: PeerId) -> (title: String, toggle: () -> String)? {
        let settings = UzScriptSettings()
        guard settings.cyrillicLatinEnabled else {
            return nil
        }
        let peerKey = peerId.toInt64()
        let isCyrillic = settings.chatSendScript(peerKey: peerKey) == .cyrillic
        let title = isCyrillic ? UzScriptStrings.menuCyrillicToLatin : UzScriptStrings.menuLatinToCyrillic
        return (title, {
            let texts = UzScriptStrings(languageCode: appCurrentLanguage.languageCode)
            if isCyrillic {
                settings.setChatSendScript(nil, peerKey: peerKey)
                return texts.sendingInLatinNotice
            } else {
                settings.setChatSendScript(.cyrillic, peerKey: peerKey)
                return texts.sendingInCyrillicNotice
            }
        })
    }

    // Screen only: the stored message is never edited.
    public static func displayed(_ text: String, attributes: [MessageAttribute]) -> (String, [MessageAttribute]) {
        guard UzScriptSettings().showChatsInNewAlphabet else {
            return (text, attributes)
        }
        return convert(text, attributes: attributes, to: .latin2027) ?? (text, attributes)
    }

    private static func convert(_ text: String, attributes: [MessageAttribute], to target: UzScript) -> (String, [MessageAttribute])? {
        guard !text.isEmpty else {
            return nil
        }
        let entities = attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first?.entities ?? []
        let protectedRanges = entities.filter { isProtected($0.type) }.map { nsRange($0.range) }
        let converted: UzScriptResult?
        if target == .latin2027 {
            converted = UzScriptConverter.toNewLatinIfUzbek(text, protectedRanges: protectedRanges)
        } else {
            converted = UzScriptConverter.toScriptIfUzbek(text, to: target, protectedRanges: protectedRanges)
        }
        guard let result = converted, result.isChanged else {
            return nil
        }
        let mappedEntities = entities.compactMap { entity -> MessageTextEntity? in
            let range = result.mapRange(nsRange(entity.range))
            guard range.location != NSNotFound, range.length > 0 else {
                return nil
            }
            return MessageTextEntity(range: range.location ..< range.location + range.length, type: entity.type)
        }
        let mappedAttributes = attributes.map { attribute -> MessageAttribute in
            return attribute is TextEntitiesMessageAttribute ? TextEntitiesMessageAttribute(entities: mappedEntities) : attribute
        }
        return (result.text, mappedAttributes)
    }

    private static func nsRange(_ range: Range<Int>) -> NSRange {
        return NSRange(location: range.lowerBound, length: range.count)
    }

    private static func isProtected(_ type: MessageTextEntityType) -> Bool {
        switch type {
        case .Code, .Pre, .Url, .TextUrl, .Mention, .TextMention, .Hashtag, .BotCommand, .Email, .CustomEmoji:
            return true
        default:
            return false
        }
    }
}
