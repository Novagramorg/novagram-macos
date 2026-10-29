import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import NovagramCore

func installNovagramHooks() {
    var hooks = NovagramHooks()
    hooks.presentEditedHistory = { context, peerId, messageId, currentText in
        guard let context = context as? AccountContext else {
            return
        }
        let controller = NovagramEditedHistoryController(context: context, peerId: peerId, messageId: messageId, currentText: currentText)
        context.bindings.rootNavigation().push(controller)
    }
    hooks.accountWillLogOut = { accountId in
        NovagramAnalyticsManager.shared.accountWillLogOut(accountId: accountId)
        NovagramSavedSearches.clear(accountRecordId: accountId)
    }
    hooks.openRecentActions = { context, peer in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(ChannelEventLogController(context, peer: EnginePeer(peer)))
    }
    NovagramHooks.install(hooks)
    installNovagramSettingsHooks()
    installNovagramAdsHooks()
}
