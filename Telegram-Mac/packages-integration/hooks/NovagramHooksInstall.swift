import Cocoa
import TGUIKit
import Postbox
import FenixuzCore

func installNovagramHooks() {
    var hooks = NovagramHooks()
    hooks.presentEditedHistory = { context, peerId, messageId, currentText in
        guard let context = context as? AccountContext else {
            return
        }
        let controller = FenixuzEditedHistoryController(context: context, peerId: peerId, messageId: messageId, currentText: currentText)
        context.bindings.rootNavigation().push(controller)
    }
    NovagramHooks.install(hooks)
    installNovagramSettingsHooks()
    installNovagramAdsHooks()
}
