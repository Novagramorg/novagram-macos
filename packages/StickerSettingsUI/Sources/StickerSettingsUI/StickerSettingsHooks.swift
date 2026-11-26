import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import TelegramContext
import GeneralRows

public enum StickerSettingsPackPreviewSource : Hashable {
    case stickers(StickerPackReference)
    case emoji(StickerPackReference)
}

public protocol StickerSettingsStickerView: View {
    func updateStickerSettingsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool)
}

public struct StickerSettingsHooks {
    public let makeStickerView: (NSRect) -> StickerSettingsStickerView
    public let makeStickerPackPreview: (any AccountContextProtocol, PeerId?, [StickerSettingsPackPreviewSource]) -> ModalViewController
    public let makeSetupQuickReaction: (any AccountContextProtocol, @escaping (TelegramMediaFile) -> Void) -> ViewController
    public let openStickersBot: (any AccountContextProtocol) -> Void
    public let featuredViewType: ([FeaturedStickerPackItem], FeaturedStickerPackItem) -> GeneralViewType

    public init(makeStickerView: @escaping (NSRect) -> StickerSettingsStickerView,
                makeStickerPackPreview: @escaping (any AccountContextProtocol, PeerId?, [StickerSettingsPackPreviewSource]) -> ModalViewController,
                makeSetupQuickReaction: @escaping (any AccountContextProtocol, @escaping (TelegramMediaFile) -> Void) -> ViewController,
                openStickersBot: @escaping (any AccountContextProtocol) -> Void,
                featuredViewType: @escaping ([FeaturedStickerPackItem], FeaturedStickerPackItem) -> GeneralViewType) {
        self.makeStickerView = makeStickerView
        self.makeStickerPackPreview = makeStickerPackPreview
        self.makeSetupQuickReaction = makeSetupQuickReaction
        self.openStickersBot = openStickersBot
        self.featuredViewType = featuredViewType
    }

    private static var _shared: StickerSettingsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: StickerSettingsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("StickerSettingsHooks.install must be called before sticker settings screens are used")
        return .placeholder
    }

    public static func install(_ hooks: StickerSettingsHooks) {
        assert(Thread.isMainThread, "StickerSettingsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = StickerSettingsHooks(makeStickerView: { frame in
        StickerSettingsPlaceholderStickerView(frame: frame)
    }, makeStickerPackPreview: { _, _, _ in
        ModalViewController()
    }, makeSetupQuickReaction: { _, _ in
        ViewController()
    }, openStickersBot: { _ in
    }, featuredViewType: { featured, item in
        bestGeneralViewType(featured, for: item)
    })
}

final class StickerSettingsPlaceholderStickerView: View, StickerSettingsStickerView {
    func updateStickerSettingsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {

    }
}
