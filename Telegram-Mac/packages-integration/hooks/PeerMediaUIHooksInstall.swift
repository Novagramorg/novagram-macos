import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import PeerMediaUI

func installPeerMediaUIHooks() {
    PeerMediaUIHooks.install(PeerMediaUIHooks(getAudioPlayer: { context in
        return (context as! AccountContext).sharedContext.getAudioPlayer()
    }, showQuickLookPreview: { context, file, stableId, table in
        QuickLookPreview.current.show(context: context as! AccountContext, with: file, stableId: stableId, table)
    }, makeInlineAudioPlayerContextObject: { controller, context, tableView, supportTableView in
        return InlineAudioPlayerView.ContextObject(controller: controller, context: context as! AccountContext, tableView: tableView, supportTableView: supportTableView)
    }, navigateToChat: { navigation, context, chatLocation, focusTarget, initialAction in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation, focusTarget: focusTarget, initialAction: initialAction)
    }, pushPeerInfo: { navigation, context, peerId in
        PeerInfoController.push(navigation: navigation, context: context as! AccountContext, peerId: peerId)
    }, showInlineAudioPlayer: { controller, context, tableView, supportTableView in
        let context = context as! AccountContext
        let object = InlineAudioPlayerView.ContextObject(controller: controller, context: context, tableView: tableView, supportTableView: supportTableView)
        context.sharedContext.showInlinePlayer(object)
    }))
}
