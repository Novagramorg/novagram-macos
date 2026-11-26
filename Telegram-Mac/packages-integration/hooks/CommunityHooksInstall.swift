import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import CommunityUI

func installCommunityUIHooks() {
    installCommunityHooks(.init(selectChatToAdd: { context, title, excludePeerIds in
        guard let context = context as? AccountContext else {
            return .single([])
        }
        return selectModalPeers(window: context.window, context: context, title: title, settings: [.groups, .channels], excludePeerIds: excludePeerIds, limit: 1, behavior: SelectCommunityChatsBehavior(excludePeerIds: excludePeerIds, limit: 1))
    }, selectAdmin: { context, title, excludePeerIds in
        guard let context = context as? AccountContext else {
            return .single([])
        }
        let behavior = SelectContactsBehavior(settings: [.contacts, .remote, .excludeBots], excludePeerIds: excludePeerIds, limit: 1)
        return selectModalPeers(window: context.window, context: context, title: title, limit: 1, behavior: behavior)
    }, openChat: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId))
    }, openMainApp: { context, peer in
        guard let context = context as? AccountContext else {
            return
        }
        BrowserStateContext.get(context).open(tab: .mainapp(bot: peer, source: .generic))
    }, openCommunityEdit: { context, communityId in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(CommunityEditController(context, communityId: communityId))
    }, cropImage: { context, url, completed, closed in
        guard let context = context as? AccountContext else {
            return
        }
        guard let cropController = EditImageModalController(url, context: context, settings: .disableSizes(dimensions: .square, circle: true)) else {
            return
        }
        showModal(with: cropController, for: context.window, animationType: .scaleCenter)
        _ = cropController.result.start(next: { url, _ in
            completed(url)
        })
        cropController.onClose = closed
    }, openBlacklist: { context, communityId in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(ChannelBlacklistViewController(context, peerId: communityId))
    }))
}
