import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import AvatarEditorUI

extension StickerMediaContentView: @retroactive AvatarStickerPreviewView {
    public func updateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol) {
        self.update(with: file, size: size, context: context as! AccountContext, parent: nil, table: nil)
    }
}

private func makeAvatarPickerInteractions(_ context: AccountContext, selectForeground: @escaping(TelegramMediaFile)->Void, showPremium: @escaping(TelegramMediaFile, NSView)->Void) -> EntertainmentInteractions {
    let interactions = EntertainmentInteractions(.stickers, peerId: context.peerId)
    interactions.sendSticker = { file, _, _, _ in
        selectForeground(file)
    }
    interactions.sendGIF = { file, _, _ in
        selectForeground(file)
    }
    interactions.sendAnimatedEmoji = { item, _, _, _, _ in
        selectForeground(item.file._parse())
    }
    interactions.showStickerPremium = { file, view in
        showPremium(file, view)
    }
    return interactions
}

func installAvatarEditorUIHooks() {
    AvatarEditorHooks.install(AvatarEditorHooks(makeStickerPreviewView: { frame in
        return StickerMediaContentView(frame: frame)
    }, makeStickerPicker: { context, selectForeground, showPremium in
        let context = context as! AccountContext
        let controller = NStickersViewController(context)
        controller.mode = .selectAvatar
        let interactions = makeAvatarPickerInteractions(context, selectForeground: selectForeground, showPremium: showPremium)
        controller.update(with: interactions, chatInteraction: ChatInteraction(chatLocation: .peer(context.peerId), context: context))
        return controller
    }, makeEmojiPicker: { context, selectForeground, showPremium in
        let context = context as! AccountContext
        let controller = EmojiesController(context, mode: .selectAvatar, selectedItems: [])
        let interactions = makeAvatarPickerInteractions(context, selectForeground: selectForeground, showPremium: showPremium)
        controller.update(with: interactions, chatInteraction: ChatInteraction(chatLocation: .peer(context.peerId), context: context))
        return controller
    }, pasteboardUrls: { pasteboard, context in
        return InputPasteboardParser.getPasteboardUrls(pasteboard, context: context as! AccountContext)
    }))
}
