import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramUtils
import ChatUI
import EntertainmentUI
import TelegramTheme
import ChatModeTypes

public protocol ShareSelectCallbackObject: ShareObject {

}

public protocol ShareEmojiesController: ViewController {
    func update(with interactions: EntertainmentInteractions?, chatInteraction: any ChatInteractionProtocol)
}

public struct ShareUIHooks {
    public let chatListFilterId: (ChatListFilter) -> Int32
    public let makeChatController: (any AccountContextProtocol, ChatLocation, ChatInitialAction?) -> ChatInterfaceController
    public let makeChatAdditionController: (any AccountContextProtocol, ChatLocation, ChatInitialAction?) -> ChatInterfaceController
    public let makeEmojies: (any AccountContextProtocol, TelegramPresentationTheme?) -> ShareEmojiesController

    public init(chatListFilterId: @escaping (ChatListFilter) -> Int32,
                makeChatController: @escaping (any AccountContextProtocol, ChatLocation, ChatInitialAction?) -> ChatInterfaceController,
                makeChatAdditionController: @escaping (any AccountContextProtocol, ChatLocation, ChatInitialAction?) -> ChatInterfaceController,
                makeEmojies: @escaping (any AccountContextProtocol, TelegramPresentationTheme?) -> ShareEmojiesController) {
        self.chatListFilterId = chatListFilterId
        self.makeChatController = makeChatController
        self.makeChatAdditionController = makeChatAdditionController
        self.makeEmojies = makeEmojies
    }

    private static var _shared: ShareUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ShareUIHooks {
        if let value = _shared {
            return value
        }
        preconditionFailure("ShareUIHooks.install must be called before share screens are used")
    }

    public static func install(_ hooks: ShareUIHooks) {
        assert(Thread.isMainThread, "ShareUIHooks.install must be called on the main thread")
        _shared = hooks
    }
}
