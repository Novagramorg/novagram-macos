import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import ComposeUI

extension ChannelVisibilityController: @retroactive ComposeChannelVisibilityController {

}

func installComposeUIHooks() {
    ComposeUIHooks.install(ComposeUIHooks(navigateToChat: { navigation, context, chatLocation in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation)
    }, makeChannelVisibilityController: { context, peerId, isChannel, isNew in
        return ChannelVisibilityController(context as! AccountContext, peerId: peerId, isChannel: isChannel, isNew: isNew)
    }, openInAppLink: { link in
        execute(inapp: inApp(for: link.nsstring))
    }, makeChatController: { context, peerId in
        return ChatController(context: context as! AccountContext, chatLocation: .peer(peerId))
    }))
}
