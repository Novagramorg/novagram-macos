import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import ChatUI

func installChatPanelsUIHooks() {
    ChatPanelsHooks.install(ChatPanelsHooks(stringForGroupPermission: { right, channel in
        return stringForGroupPermission(right: right, channel: channel)
    }, groupPermissionDependencies: { right in
        return groupPermissionDependencies(right)
    }, makeTextAndLabelItem: { initialSize, stableId, label, copyMenuText, text, context, viewType, canCopy, _copyToClipboard in
        return TextAndLabelItem(initialSize, stableId: stableId, label: label, copyMenuText: copyMenuText, text: text, context: context as! AccountContext, viewType: viewType, canCopy: canCopy, _copyToClipboard: _copyToClipboard)
    }, meUrlHost: { context in
        return (context as! AccountContext).meUrlHost
    }))
}
