import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import WidgetUI

extension MediaAnimatedStickerView: @retroactive WidgetCardsStickerView {
    public func updateWidgetCardsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        self.update(with: media, size: size, context: context, parent: parent, table: table, parameters: nil, animated: animated, positionFlags: positionFlags, approximateSynchronousValue: approximateSynchronousValue)
    }
}

func installWidgetCardsUIHooks() {
    installWidgetCardsHooks(WidgetCardsHooks(makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, downloadAndApplyCloudTheme: { context, cloudTheme, palette, install in
        return downloadAndApplyCloudTheme(context: context as! AccountContext, theme: cloudTheme, palette: palette, install: install)
    }, showStickerPackPreview: { context, shortName, onAdd in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: StickerPackPreviewModalController(context, peerId: nil, references: [.stickers(.name(shortName))], onAdd: onAdd), for: context.window)
    }, navigateToChat: { navigation, context, chatLocation in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation)
    }))
}
