import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import StickerSettingsUI

extension StickerMediaContentView: @retroactive StickerSettingsStickerView {
    public func updateStickerSettingsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        self.update(with: media, size: size, context: context, parent: parent, table: table, parameters: nil, animated: animated, positionFlags: positionFlags, approximateSynchronousValue: approximateSynchronousValue)
    }
}

private func mapStickerPackPreviewSource(_ source: StickerSettingsPackPreviewSource) -> StickerPackPreviewSource {
    switch source {
    case let .stickers(reference):
        return .stickers(reference)
    case let .emoji(reference):
        return .emoji(reference)
    }
}

func installStickerSettingsUIHooks() {
    StickerSettingsHooks.install(StickerSettingsHooks(makeStickerView: { frame in
        return StickerMediaContentView(frame: frame)
    }, makeStickerPackPreview: { context, peerId, references in
        return StickerPackPreviewModalController(context as! AccountContext, peerId: peerId, references: references.map(mapStickerPackPreviewSource))
    }, makeSetupQuickReaction: { context, callback in
        return SetupQuickReactionController(context as! AccountContext, callback: callback)
    }, openStickersBot: { context in
        guard let context = context as? AccountContext else {
            return
        }
        let link = inApp(for: "@stickers", context: context, openInfo: { peerId, _, _, _ in
            navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId))
        })
        execute(inapp: link)
    }, featuredViewType: { featured, item in
        return bestGeneralViewType(featured, for: item)
    }))
}
