import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LocalAnimations
import GeneralRows
import BoostUI

extension PremiumConfiguration: BoostPremiumConfiguration {

}

extension BoostSubject {
    func requiredLevel(context: AccountContext, group: Bool, configuration: PremiumConfiguration) -> Int32 {
        return requiredBoostSubjectLevel(subject: self, group: group, context: context, configuration: configuration)
    }
}

func installBoostUIHooks() {
    BoostHooks.install(BoostHooks(makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, stickerSize in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, stickerSize: stickerSize)
    }, makeStarSceneRowItem: { initialSize, stableId in
        return StarSceneRowItem(initialSize, stableId: stableId)
    }, premiumConfiguration: { context in
        return PremiumConfiguration.with(appConfiguration: context.appConfiguration)
    }, openChat: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId)))
    }, shareLink: { context, link, window in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: window)
    }, generalPrepaidGiveawayIcon: { bgColor, count in
        return generalPrepaidGiveawayIcon(bgColor, count: count)
    }, iconBoostLighting: {
        return NSImage(resource: .iconBoostLighting)
    }, iconGiveawayPremium: {
        return NSImage(resource: .iconGiveawayPremium)
    }, iconGiveawayStars: {
        return NSImage(resource: .iconGiveawayStars)
    }, iconGiveawayRandom: {
        return NSImage(resource: .iconGiveawayRandom)
    }, iconGiveawayRandomResult: {
        return NSImage(resource: .iconGiveawayRandomResult)
    }, openPeerInfo: { navigation, context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        PeerInfoController.push(navigation: navigation, context: context, peerId: peerId)
    }, makeChatAdditionControllerWithFocus: { context, chatLocation, focusTarget in
        return ChatAdditionController(context: context as! AccountContext, chatLocation: chatLocation, focusTarget: focusTarget)
    }))
}
