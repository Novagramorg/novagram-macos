import Cocoa
import TelegramCore
import Postbox
import ColorPalette
import TGUIKit

public extension Message {
    func isIncoming(_ account: Account, _ isBubbled: Bool) -> Bool {
        if isBubbled, let peer = coreMessageMainPeer(self) {
            if peer.isSupergroup, self.author?.id == account.peerId {
                return false
            }
        }
        
        return effectivelyIncoming(account.peerId)
    }
}

public extension TelegramMediaFile {
    var stickerReference:StickerPackReference? {
        for attr in attributes {
            if case let .Sticker(_, reference, _) = attr {
                return reference
            }
        }
        return nil
    }
    var stickerText:String? {
        for attr in attributes {
            if case let .Sticker(displayText, _, _) = attr {
                return displayText
            }
        }
        return nil
    }
    var isEmojiAnimatedSticker: Bool {
        if let fileName = fileName {
            return fileName.hasPrefix("telegram-animoji") && fileName.hasSuffix("tgs") && isSticker
        }
        return false
    }

    var animatedEmojiFitzModifier: EmojiFitzModifier? {
        if isEmojiAnimatedSticker, let fitz = self.stickerText?.basicEmoji.1 {
            return EmojiFitzModifier(emoji: fitz)
        } else {
            return nil
        }
    }
}

public extension TelegramThemeSettings {
    var desc: String {
        let wString: String
        if let wallpaper = self.wallpaper {
            wString = "\(wallpaper)"
        } else {
            wString = ""
        }
        let colors = messageColors.map { "\($0)" }.split(separator: "-").joined()
        return "\(self.accentColor)-\(self.baseTheme)-\(colors)-\(wString)"
    }
}

public func coreMessageMainPeer(_ message: Message) -> Peer? {
    return messageMainPeer(.init(message))?._asPeer()
}
