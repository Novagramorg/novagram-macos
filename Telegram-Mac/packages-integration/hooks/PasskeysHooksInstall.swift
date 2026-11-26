import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LocalAnimations
import PasskeysUI

extension MediaAnimatedStickerView: @retroactive PasskeysStickerView {
    public func updateSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        self.update(with: animation.file, size: size, context: context, table: table, parameters: animation.parameters, animated: animated)
    }
}

func installPasskeysUIHooks() {
    PasskeysHooks.install(PasskeysHooks(
        makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, stickerSize, bgColor, image in
        AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, stickerSize: stickerSize, bgColor: bgColor, image: image) },
        makeStickerView: { MediaAnimatedStickerView(frame: NSMakeRect(0, 0, 100, 100)) },
        callbackLink: { text, handler in
        inAppLink.callback(text, handler) },
        openAppealLink: { context, url in
        guard let context = context as? AccountContext else {
            return
        }
        let link = inApp(for: url.nsstring, context: context, openInfo: { peerId, _, _, action in
            context.bindings.rootNavigation().push(ChatController(context: context, chatLocation: .peer(peerId), initialAction: action))
        })
        execute(inapp: link) }
    ))
}
