import Cocoa
import SwiftSignalKit
import TelegramCore
import TGUIKit
import Postbox
import TelegramContext
import TelegramUtils
import ChatModeTypes
import Localization

open class ChatAdditionController<Context: AccountContextProtocol>: ChatController<Context>, ChatAdditionControllerKind {
    open override var defaultBarTitle: String {
        return localizedString("Telegram.ChatAdditionController")
    }
    public override init(context: Context, chatLocation: ChatLocation, mode: ChatMode = .history, focusTarget: ChatFocusTarget? = nil, initialAction: ChatInitialAction? = nil, chatLocationContextHolder: Atomic<ChatLocationContextHolder?>? = nil) {
        super.init(context: context, chatLocation: chatLocation, mode: mode, focusTarget: focusTarget, initialAction: initialAction, chatLocationContextHolder: chatLocationContextHolder)
    }
}
