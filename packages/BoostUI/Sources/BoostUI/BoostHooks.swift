import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import LocalAnimations
import GeneralRows

public protocol BoostPremiumConfiguration {
    var minChannelNameColorLevel: Int32 { get }
    var minChannelNameIconLevel: Int32 { get }
    var minChannelProfileColorLevel: Int32 { get }
    var minChannelProfileIconLevel: Int32 { get }
    var minChannelEmojiStatusLevel: Int32 { get }
    var minChannelWallpaperLevel: Int32 { get }
    var minChannelCustomWallpaperLevel: Int32 { get }
    var minChannelRestrictAdsLevel: Int32 { get }
    var minChannelWearGiftLevel: Int32 { get }
    var minChannelAutotranslationLevel: Int32 { get }
    var minGroupProfileIconLevel: Int32 { get }
    var minGroupEmojiStatusLevel: Int32 { get }
    var minGroupWallpaperLevel: Int32 { get }
    var minGroupCustomWallpaperLevel: Int32 { get }
    var minGroupEmojiPackLevel: Int32 { get }
    var minGroupAudioTranscriptionLevel: Int32 { get }
}

public struct BoostHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize) -> TableRowItem
    public let makeStarSceneRowItem: (NSSize, AnyHashable) -> TableRowItem
    public let premiumConfiguration: (any AccountContextProtocol) -> any BoostPremiumConfiguration
    public let openChat: (any AccountContextProtocol, PeerId) -> Void
    public let shareLink: (any AccountContextProtocol, String, Window) -> Void
    public let generalPrepaidGiveawayIcon: (NSColor, NSAttributedString) -> CGImage
    public let iconBoostLighting: () -> NSImage
    public let iconGiveawayPremium: () -> NSImage
    public let iconGiveawayStars: () -> NSImage
    public let iconGiveawayRandom: () -> NSImage
    public let iconGiveawayRandomResult: () -> NSImage
    public let openPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let makeChatAdditionControllerWithFocus: (any AccountContextProtocol, ChatLocation, ChatFocusTarget?) -> ViewController

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize) -> TableRowItem,
                makeStarSceneRowItem: @escaping (NSSize, AnyHashable) -> TableRowItem,
                premiumConfiguration: @escaping (any AccountContextProtocol) -> any BoostPremiumConfiguration,
                openChat: @escaping (any AccountContextProtocol, PeerId) -> Void,
                shareLink: @escaping (any AccountContextProtocol, String, Window) -> Void,
                generalPrepaidGiveawayIcon: @escaping (NSColor, NSAttributedString) -> CGImage,
                iconBoostLighting: @escaping () -> NSImage,
                iconGiveawayPremium: @escaping () -> NSImage,
                iconGiveawayStars: @escaping () -> NSImage,
                iconGiveawayRandom: @escaping () -> NSImage,
                iconGiveawayRandomResult: @escaping () -> NSImage,
                openPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                makeChatAdditionControllerWithFocus: @escaping (any AccountContextProtocol, ChatLocation, ChatFocusTarget?) -> ViewController) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
        self.makeStarSceneRowItem = makeStarSceneRowItem
        self.premiumConfiguration = premiumConfiguration
        self.openChat = openChat
        self.shareLink = shareLink
        self.generalPrepaidGiveawayIcon = generalPrepaidGiveawayIcon
        self.iconBoostLighting = iconBoostLighting
        self.iconGiveawayPremium = iconGiveawayPremium
        self.iconGiveawayStars = iconGiveawayStars
        self.iconGiveawayRandom = iconGiveawayRandom
        self.iconGiveawayRandomResult = iconGiveawayRandomResult
        self.openPeerInfo = openPeerInfo
        self.makeChatAdditionControllerWithFocus = makeChatAdditionControllerWithFocus
    }

    private static var _shared: BoostHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: BoostHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("BoostHooks.install must be called before the boost screens are used")
        return .placeholder
    }

    public static func install(_ hooks: BoostHooks) {
        assert(Thread.isMainThread, "BoostHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = BoostHooks(
        makeStickerHeaderItem: { initialSize, stableId, _, _, _, _ in
            GeneralRowItem(initialSize, stableId: stableId) },
        makeStarSceneRowItem: { initialSize, stableId in
            GeneralRowItem(initialSize, stableId: stableId) },
        premiumConfiguration: { _ in BoostPlaceholderPremiumConfiguration() },
        openChat: { _, _ in },
        shareLink: { _, _, _ in },
        generalPrepaidGiveawayIcon: { _, _ in generateImage(NSMakeSize(1, 1), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
        })! },
        iconBoostLighting: { NSImage() },
        iconGiveawayPremium: { NSImage() },
        iconGiveawayStars: { NSImage() },
        iconGiveawayRandom: { NSImage() },
        iconGiveawayRandomResult: { NSImage() },
        openPeerInfo: { _, _, _ in },
        makeChatAdditionControllerWithFocus: { _, _, _ in ViewController() }
    )
}

struct BoostPlaceholderPremiumConfiguration: BoostPremiumConfiguration {
    var minChannelNameColorLevel: Int32 { return 1 }
    var minChannelNameIconLevel: Int32 { return 4 }
    var minChannelProfileColorLevel: Int32 { return 5 }
    var minChannelProfileIconLevel: Int32 { return 7 }
    var minChannelEmojiStatusLevel: Int32 { return 8 }
    var minChannelWallpaperLevel: Int32 { return 9 }
    var minChannelCustomWallpaperLevel: Int32 { return 10 }
    var minChannelRestrictAdsLevel: Int32 { return 50 }
    var minChannelWearGiftLevel: Int32 { return 8 }
    var minChannelAutotranslationLevel: Int32 { return 3 }
    var minGroupProfileIconLevel: Int32 { return 7 }
    var minGroupEmojiStatusLevel: Int32 { return 8 }
    var minGroupWallpaperLevel: Int32 { return 9 }
    var minGroupCustomWallpaperLevel: Int32 { return 9 }
    var minGroupEmojiPackLevel: Int32 { return 9 }
    var minGroupAudioTranscriptionLevel: Int32 { return 9 }
}
