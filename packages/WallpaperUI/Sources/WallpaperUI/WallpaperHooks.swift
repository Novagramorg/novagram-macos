import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import ChatHistoryModel
import GeneralRows
import ColorPalette
import ThemeSettings

public protocol WallpaperChatPreviewContext: AnyObject {

}

public protocol WallpaperStickerView: View {
    var overridePlayValue: Bool? { get set }
    func updateWallpaperSticker(sticker: StickerPackItem, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool)
}

public protocol WallpaperPremiumConfiguration {
    var minChannelCustomWallpaperLevel: Int32 { get }
}

public struct WallpaperHooks {
    public let makeChatPreviewContext: (any AccountContextProtocol, @escaping () -> CGRect) -> WallpaperChatPreviewContext
    public let makeChatPreviewItem: (NSSize, WallpaperChatPreviewContext, ChatHistoryEntry, TelegramPresentationTheme) -> TableRowItem
    public let updateChatPreviewBackground: (NSView, Bool, Bool) -> Void
    public let shareLink: (any AccountContextProtocol, String) -> Void
    public let makeStickerView: (NSRect) -> WallpaperStickerView
    public let premiumConfiguration: (any AccountContextProtocol) -> any WallpaperPremiumConfiguration
    public let boostLevelBadgeImage: (String) -> CGImage
    public let generateTheme: (ColorPalette, TelegramTheme?, Bool, CGFloat, ThemeWallpaper, NSSize) -> TelegramPresentationTheme

    public init(makeChatPreviewContext: @escaping (any AccountContextProtocol, @escaping () -> CGRect) -> WallpaperChatPreviewContext,
                makeChatPreviewItem: @escaping (NSSize, WallpaperChatPreviewContext, ChatHistoryEntry, TelegramPresentationTheme) -> TableRowItem,
                updateChatPreviewBackground: @escaping (NSView, Bool, Bool) -> Void,
                shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                makeStickerView: @escaping (NSRect) -> WallpaperStickerView,
                premiumConfiguration: @escaping (any AccountContextProtocol) -> any WallpaperPremiumConfiguration,
                boostLevelBadgeImage: @escaping (String) -> CGImage,
                generateTheme: @escaping (ColorPalette, TelegramTheme?, Bool, CGFloat, ThemeWallpaper, NSSize) -> TelegramPresentationTheme) {
        self.makeChatPreviewContext = makeChatPreviewContext
        self.makeChatPreviewItem = makeChatPreviewItem
        self.updateChatPreviewBackground = updateChatPreviewBackground
        self.shareLink = shareLink
        self.makeStickerView = makeStickerView
        self.premiumConfiguration = premiumConfiguration
        self.boostLevelBadgeImage = boostLevelBadgeImage
        self.generateTheme = generateTheme
    }

    private static var _shared: WallpaperHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: WallpaperHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("WallpaperHooks.install must be called before wallpaper screens are used")
        return .placeholder
    }

    public static func install(_ hooks: WallpaperHooks) {
        assert(Thread.isMainThread, "WallpaperHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = WallpaperHooks(makeChatPreviewContext: { _, _ in
        PlaceholderChatPreviewContext()
    }, makeChatPreviewItem: { initialSize, _, _, _ in
        GeneralRowItem(initialSize, stableId: arc4random())
    }, updateChatPreviewBackground: { _, _, _ in
    }, shareLink: { _, _ in
    }, makeStickerView: { frame in
        WallpaperPlaceholderStickerView(frame: frame)
    }, premiumConfiguration: { _ in
        WallpaperPlaceholderPremiumConfiguration()
    }, boostLevelBadgeImage: { _ in
        generateImage(NSMakeSize(1, 1), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
        })!
    }, generateTheme: { _, _, _, _, _, _ in
        theme
    })
}

private final class PlaceholderChatPreviewContext: WallpaperChatPreviewContext {

}

final class WallpaperPlaceholderStickerView: View, WallpaperStickerView {
    var overridePlayValue: Bool? = nil
    func updateWallpaperSticker(sticker: StickerPackItem, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {

    }
}

struct WallpaperPlaceholderPremiumConfiguration: WallpaperPremiumConfiguration {
    var minChannelCustomWallpaperLevel: Int32 = 0
}
