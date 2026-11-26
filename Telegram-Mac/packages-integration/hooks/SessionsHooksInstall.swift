import Cocoa
import TGUIKit
import SessionsUI
import LocalAnimations

func installSessionsUIHooks() {
    SessionsHooks.install(SessionsHooks(makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, stickerSize, bgColor, modify in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, stickerSize: stickerSize, bgColor: bgColor, modify: modify)
    }))
}
