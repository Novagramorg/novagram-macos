import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ShareUI

extension SelectCallbackObject: @retroactive ShareSelectCallbackObject {

}

extension EmojiesController: @retroactive ShareEmojiesController {

}

func installShareUIHooks() {
    ShareUIHooks.install(ShareUIHooks(chatListFilterId: { filter in
        return filter.id
    }, makeChatController: { context, chatLocation, initialAction in
        return ChatController(context: context.concrete, chatLocation: chatLocation, initialAction: initialAction)
    }, makeChatAdditionController: { context, chatLocation, initialAction in
        return ChatAdditionController(context: context.concrete, chatLocation: chatLocation, initialAction: initialAction)
    }, makeEmojies: { context, presentation in
        let emojis = EmojiesController(context.concrete, presentation: presentation)
        return emojis
    }))
}
