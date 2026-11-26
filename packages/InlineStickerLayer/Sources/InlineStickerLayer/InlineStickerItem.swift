import Cocoa
import TelegramUtils
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import InputView
import TelegramTheme
import TelegramMedia

public final class InlineStickerItem : Hashable {

    public enum Source : Equatable {
        case attribute(ChatTextCustomEmojiAttribute)
        case reference(StickerPackItem)
        case avatar(EnginePeer)
        case rendered(CGImage)

        public static func == (lhs: Source, rhs: Source) -> Bool {
            switch (lhs, rhs) {
            case let (.attribute(l), .attribute(r)):
                return l == r
            case let (.reference(l), .reference(r)):
                return l.file.fileId == r.file.fileId
            case let (.avatar(l), .avatar(r)):
                return l.id == r.id
            case let (.rendered(l), .rendered(r)):
                return l === r
            default:
                return false
            }
        }
    }

    public let source: Source
    public let playPolicy: LottiePlayPolicy?
    public init(source: Source, playPolicy: LottiePlayPolicy? = nil) {
        self.source = source
        self.playPolicy = playPolicy
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }


    public static func ==(lhs: InlineStickerItem, rhs: InlineStickerItem) -> Bool {
        return lhs === rhs
    }

    public static func apply(to attr: NSMutableAttributedString, associatedMedia: [MediaId : Media], entities: [MessageTextEntity], isPremium: Bool, ignoreSpoiler: Bool = false, offset: Int = 0, playPolicy: LottiePlayPolicy? = nil) {
        var spoilerRanges: [NSRange] = []
        if ignoreSpoiler {
            for entity in entities {
                guard case .Spoiler = entity.type else {
                    continue
                }
                spoilerRanges.append(NSRange(location: entity.range.lowerBound, length: entity.range.upperBound - entity.range.lowerBound))
            }
        }
        for entity in entities.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            guard case let .CustomEmoji(_, fileId) = entity.type else {
                continue
            }
            let range = NSRange(location: entity.range.lowerBound + offset, length: entity.range.upperBound - entity.range.lowerBound)
            if spoilerRanges.contains(where: { $0.intersection(range) != nil }) {
                continue
            }
            embed(fileId: fileId, at: range, in: attr, associatedMedia: associatedMedia, playPolicy: playPolicy)
        }
    }

    public static func apply(to attr: NSMutableAttributedString, associatedMedia: [MediaId : Media], playPolicy: LottiePlayPolicy? = nil) {
        var found: [(range: NSRange, fileId: Int64)] = []
        attr.enumerateAttribute(TextInputAttributes.customEmoji, in: attr.range, options: []) { value, range, _ in
            if let value = value as? TextInputTextCustomEmojiAttribute {
                found.append((range, value.fileId))
            }
        }
        for item in found.reversed() {
            embed(fileId: item.fileId, at: item.range, in: attr, associatedMedia: associatedMedia, playPolicy: playPolicy)
        }
    }

    private static func embed(fileId: Int64, at range: NSRange, in attr: NSMutableAttributedString, associatedMedia: [MediaId : Media], playPolicy: LottiePlayPolicy?) {
        guard let range = attr.range.intersection(range), range.length > 0 else {
            return
        }
        var attributes = attr.attributes(at: range.lowerBound, effectiveRange: nil)
        let emoji = attr.string.nsstring.substring(with: range)
        let file = associatedMedia[MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)] as? TelegramMediaFile
        attributes[TextInputAttributes.embedded] = InlineStickerItem(source: .attribute(.init(fileId: fileId, file: file, emoji: emoji)), playPolicy: playPolicy)
        attr.replaceCharacters(in: range, with: NSAttributedString(string: clown, attributes: attributes))
    }
}

extension InlineStickerItem: EmbeddedCustomEmojiAttributeValue {
    public var customEmojiAttribute: ChatTextCustomEmojiAttribute? {
        if case let .attribute(attribute) = source {
            return attribute
        }
        return nil
    }
}
