import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramMedia
import LocalAnimations
import ChatModeTypes

public protocol MonetizationStickerView: View {
    func updateMonetizationSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, table: TableView?, colors: [LottieColor], animated: Bool)
}

public struct MonetizationHooks {
    public let makeStickerView: (NSRect) -> MonetizationStickerView
    public let formatPhoneNumber: (any AccountContextProtocol, String) -> String
    public let boostLevelBadgeImage: (String) -> CGImage
    public let iconFragmentLock: () -> NSImage
    public let iconFragmentAds: () -> NSImage
    public let iconFragmentSplitRevenue: () -> NSImage
    public let iconFragmentTonPayment: () -> NSImage
    public let iconFragmentMonetization: () -> NSImage
    public let adMenuItems: (Message, any ChatInteractionProtocol) -> Signal<[ContextMenuItem], NoError>

    public init(makeStickerView: @escaping (NSRect) -> MonetizationStickerView,
                formatPhoneNumber: @escaping (any AccountContextProtocol, String) -> String,
                boostLevelBadgeImage: @escaping (String) -> CGImage,
                iconFragmentLock: @escaping () -> NSImage,
                iconFragmentAds: @escaping () -> NSImage,
                iconFragmentSplitRevenue: @escaping () -> NSImage,
                iconFragmentTonPayment: @escaping () -> NSImage,
                iconFragmentMonetization: @escaping () -> NSImage,
                adMenuItems: @escaping (Message, any ChatInteractionProtocol) -> Signal<[ContextMenuItem], NoError>) {
        self.makeStickerView = makeStickerView
        self.formatPhoneNumber = formatPhoneNumber
        self.boostLevelBadgeImage = boostLevelBadgeImage
        self.iconFragmentLock = iconFragmentLock
        self.iconFragmentAds = iconFragmentAds
        self.iconFragmentSplitRevenue = iconFragmentSplitRevenue
        self.iconFragmentTonPayment = iconFragmentTonPayment
        self.iconFragmentMonetization = iconFragmentMonetization
        self.adMenuItems = adMenuItems
    }

    private static var _shared: MonetizationHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: MonetizationHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("MonetizationHooks.install must be called before the monetization screens are used")
        return .placeholder
    }

    public static func install(_ hooks: MonetizationHooks) {
        assert(Thread.isMainThread, "MonetizationHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = MonetizationHooks(
        makeStickerView: { frame in MonetizationPlaceholderStickerView(frame: frame) },
        formatPhoneNumber: { _, number in number },
        boostLevelBadgeImage: { _ in generateImage(NSMakeSize(1, 1), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
        })! },
        iconFragmentLock: { NSImage() },
        iconFragmentAds: { NSImage() },
        iconFragmentSplitRevenue: { NSImage() },
        iconFragmentTonPayment: { NSImage() },
        iconFragmentMonetization: { NSImage() },
        adMenuItems: { _, _ in .single([]) }
    )
}

final class MonetizationPlaceholderStickerView: View, MonetizationStickerView {
    func updateMonetizationSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, table: TableView?, colors: [LottieColor], animated: Bool) {

    }
}
