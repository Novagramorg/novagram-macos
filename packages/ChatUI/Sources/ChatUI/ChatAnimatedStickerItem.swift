import Cocoa
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import TelegramMedia
import ChatHistoryModel
import TelegramContext
import TelegramMediaUtils
import TelegramTheme

public class ChatAnimatedStickerItem: ChatMediaItem {
    public override init(_ initialSize: NSSize, _ chatInteraction: ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        super.init(initialSize, chatInteraction, context, object, theme: theme)
        
        let file = (object.message!.anyMedia as! TelegramMediaFile)
        
        let isPremiumSticker = file.isPremiumSticker
        
        let mirror = ((renderType == .bubble && isIncoming) || renderType == .list)
        parameters?.runEmojiScreenEffect = { [weak chatInteraction] emoji in
            chatInteraction?.runEmojiScreenEffect(emoji, object.message!, mirror, false)
        }
        parameters?.runPremiumScreenEffect = { [weak chatInteraction] message in
            chatInteraction?.runPremiumScreenEffect(message, mirror, false)
        }
        parameters?.mirror = mirror && isPremiumSticker

        if file.isCustomTemplateEmoji {
            parameters?.colors = [.init(keyPath: "", color: theme.colors.text)]
        }
    }
}
