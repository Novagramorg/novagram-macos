import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import WallpaperUI
import ChatHistoryModel
import ColorPalette
import ThemeSettings

extension ChatInteraction: @retroactive WallpaperChatPreviewContext {

}

extension MediaAnimatedStickerView: @retroactive WallpaperStickerView {
    public func updateWallpaperSticker(sticker: StickerPackItem, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        let params = ChatAnimatedStickerMediaLayoutParameters(playPolicy: nil, hidePlayer: true, media: sticker.file._parse())
        self.update(with: sticker.file._parse(), size: size, context: context, table: table, parameters: params, animated: animated)
    }
}

extension PremiumConfiguration: WallpaperPremiumConfiguration {

}

func installWallpaperUIHooks() {
    WallpaperHooks.install(WallpaperHooks(makeChatPreviewContext: { context, getGradientOffsetRect in
        let chatInteraction = ChatInteraction(chatLocation: .peer(PeerId(0)), context: context as! AccountContext, disableSelectAbility: true)
        chatInteraction.getGradientOffsetRect = getGradientOffsetRect
        return chatInteraction
    }, makeChatPreviewItem: { initialSize, previewContext, entry, theme in
        return ChatRowItem.item(initialSize, from: entry, interaction: previewContext as! ChatInteraction, theme: theme)
    }, updateChatPreviewBackground: { view, animated, rotated in
        if let view = view as? ChatRowView {
            view.updateBackground(animated: animated, item: view.item, rotated: rotated)
        }
    }, shareLink: { context, link in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }, makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, premiumConfiguration: { context in
        return PremiumConfiguration.with(appConfiguration: context.appConfiguration)
    }, boostLevelBadgeImage: { text in
        return generateDisclosureActionBoostLevelBadgeImage(text: text)
    }, generateTheme: { palette, cloudTheme, bubbled, fontSize, wallpaper, backgroundSize in
        return generateTheme(palette: palette, cloudTheme: cloudTheme, bubbled: bubbled, fontSize: fontSize, wallpaper: wallpaper, backgroundSize: backgroundSize)
    }))
}
