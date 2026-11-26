import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramMedia
import LocalAnimations
import MonetizationUI
import ChatUI
import ChatModeTypes

extension MediaAnimatedStickerView: @retroactive MonetizationStickerView {
    public func updateMonetizationSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, table: TableView?, colors: [LottieColor], animated: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        let parameters = animation.parameters
        parameters.colors = colors
        self.update(with: animation.file, size: size, context: context, table: table, parameters: parameters, animated: animated)
    }
}

func installMonetizationUIHooks() {
    MonetizationHooks.install(MonetizationHooks(makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, formatPhoneNumber: { context, number in
        guard let context = context as? AccountContext else {
            return number
        }
        return formatPhoneNumber(context: context, number: number)
    }, boostLevelBadgeImage: { text in
        return generateDisclosureActionBoostLevelBadgeImage(text: text)
    }, iconFragmentLock: {
        return NSImage(resource: .iconFragmentLock)
    }, iconFragmentAds: {
        return NSImage(resource: .iconFragmentAds)
    }, iconFragmentSplitRevenue: {
        return NSImage(resource: .iconFragmentSplitRevenue)
    }, iconFragmentTonPayment: {
        return NSImage(resource: .iconFragmentTonPayment)
    }, iconFragmentMonetization: {
        return NSImage(resource: .iconFragmentMonetization)
    }, adMenuItems: { message, interactions in
        return chatMenuItems(for: message, entry: nil, textLayout: nil, chatInteraction: interactions as! ChatInteraction, fromAdPromo: true)
    }))
}
