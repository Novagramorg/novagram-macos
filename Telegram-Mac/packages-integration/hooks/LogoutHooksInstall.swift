import Cocoa
import TGUIKit
import Postbox
import SettingsUI

func installLogoutUIHooks() {
    LogoutHooks.install(LogoutHooks(
        makeStorageUsageController: { context in
        StorageUsageController(context as! AccountContext) },
        makeChatController: { context, peerId in
        ChatController(context: context as! AccountContext, chatLocation: .peer(peerId)) },
        openFaq: { context in
        openFaq(context: context as! AccountContext) },
        logoutConfirmationText: { context in
        walletLogoutConfirmationText(context: context as! AccountContext) }
    ))
}
