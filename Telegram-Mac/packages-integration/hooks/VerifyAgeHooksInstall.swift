import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LocalAnimations
import VerifyAgeUI

func installVerifyAgeUIHooks() {
    VerifyAgeHooks.install(VerifyAgeHooks(
        makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, stickerSize, bgColor, image in
        AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, stickerSize: stickerSize, bgColor: bgColor, image: image) }
    ))
}
