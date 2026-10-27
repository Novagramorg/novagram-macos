import Cocoa
import TGUIKit
import Postbox
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
    }
    NovagramHooks.install(hooks)
    installNovagramSettingsHooks()
    installNovagramAdsHooks()
}
