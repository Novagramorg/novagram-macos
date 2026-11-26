import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LocalAnimations
import ChannelSettingsUI

func installChannelSettingsUIHooks() {
    ChannelSettingsUIHooks.install(ChannelSettingsUIHooks(makeStickerHeaderItem: { initialSize, stableId, context, sticker, text in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text)
    }, resolveUsername: { username, context in
        return resolveUsername(username: username, context: context as! AccountContext)
    }, inputSource: { context in
        return (context as! AccountContext).sharedContext.inputSource
    }, enableBetaFeatures: {
        return enableBetaFeatures
    }))
}
