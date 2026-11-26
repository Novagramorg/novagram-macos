import Cocoa
import TGUIKit
import TelegramCore
import AuthUI

extension UpdateTabController: AuthUpdateTabController {

}

func installAuthUIHooks() {
    AuthUIHooks.install(AuthUIHooks(makeChatController: { context, chatLocation in
        return ChatController(context: context as! AccountContext, chatLocation: chatLocation)
    }, makeAccountMenuItem: { account, context, showBadge, handler in
        return ContextAccountMenuItem(account: account, context: context as! AccountContext, showBadge: showBadge, handler: handler)
    }, executeInApp: { link in
        switch link {
        case let .external(link, confirm):
            execute(inapp: .external(link: link, confirm))
        }
    }, makeUpdateTabController: { sharedContext in
        return UpdateTabController(sharedContext as! SharedAccountContext)
    }))
}
