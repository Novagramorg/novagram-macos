import Cocoa
import TelegramUtils
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import InputView
import TelegramTheme
import TelegramMedia
import TelegramMediaResources


public extension NSMutableAttributedString {
    func insertEmbedded(_ embedded: NSAttributedString, for symbol:String) {
        let range = self.string.nsstring.range(of: symbol)
        if range.location != NSNotFound {
            self.beginEditing()
            self.replaceCharacters(in: range, with: "")
            self.insert(embedded, at: range.location)
            self.endEditing()
        }
    }

    func replaceChevron(color: NSColor) {
        insertEmbedded(.embedded(name: "Icon_GeneralNext", color: color, resize: false), for: ">")
    }
}

public extension NSAttributedString {
    static func makeAnimated(_ file: TelegramMediaFile, text: String, info: ItemCollectionId? = nil) -> NSAttributedString {
        let attach = NSMutableAttributedString(string: text)
        let value = TextInputTextCustomEmojiAttribute(collectionId: info, fileId: file.fileId.id, file: file, emoji: text)
        attach.addAttribute(TextInputAttributes.customEmoji, value: value, range: attach.range)
        return attach
    }

    static func makeAnimated(_ fileId: Int64, text: String, info: ItemCollectionId? = nil) -> NSAttributedString {
        let attach = NSMutableAttributedString(string: text)
        let value = TextInputTextCustomEmojiAttribute(collectionId: info, fileId: fileId, file: nil, emoji: text)
        attach.addAttribute(TextInputAttributes.customEmoji, value: value, range: attach.range)
        return attach
    }


    static func embedded(name: String, color: NSColor?, resize: Bool) -> NSAttributedString {

        let file = TelegramMediaFile(fileId: .init(namespace: 0, id: arc4random64()), partialReference: nil, resource: LocalBundleResource(name: name, ext: "", color: color, resize: resize), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "bundle/jpeg", size: nil, attributes: [], alternativeRepresentations: [])

        let emoji: String = clown

        let attr = NSMutableAttributedString()
        attr.append(string: emoji)
        attr.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .attribute(.init(fileId: file.fileId.id, file: file, emoji: emoji))), range: NSMakeRange(0, emoji.length))

        return attr

    }

    static func embeddedAnimated(_ file: TelegramMediaFile, color: NSColor? = nil, playPolicy: LottiePlayPolicy? = nil) -> NSAttributedString {
        let attr = NSMutableAttributedString()

        let emoji: String = clown
        attr.append(string: emoji)
        attr.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .attribute(.init(fileId: file.fileId.id, file: file, emoji: emoji, color: color)), playPolicy: playPolicy), range: NSMakeRange(0, emoji.length))
        return attr
    }

    static func embeddedAnimated(_ fileId: Int64, color: NSColor? = nil, playPolicy: LottiePlayPolicy? = nil) -> NSAttributedString {
        let attr = NSMutableAttributedString()

        let emoji: String = clown
        attr.append(string: emoji)
        attr.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .attribute(.init(fileId: fileId, file: nil, emoji: emoji, color: color)), playPolicy: playPolicy), range: NSMakeRange(0, emoji.length))
        return attr
    }

    static func embeddedAvatar(_ peer: EnginePeer, space: Bool = true, link: Any? = nil) -> NSAttributedString {
        let attr = NSMutableAttributedString()

        let emoji: String = clown
        attr.append(string: emoji)
        attr.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .avatar(peer)), range: NSMakeRange(0, emoji.length))
        if space {
            attr.append(string: " ")
        }
        if let link {
            attr.addAttribute(NSAttributedString.Key.link, value: link, range: attr.range)
        }
        return attr
    }
}
