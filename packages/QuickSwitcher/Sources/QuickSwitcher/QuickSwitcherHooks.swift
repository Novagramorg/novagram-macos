import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import GeneralRows
import ChatModeTypes

public protocol QuickSwitcherTopicRowItem: TableRowItem {
    var threadId: Int64? { get }
}

public struct QuickSwitcherChatListUpdate {
    public let list: EngineChatList
    public init(list: EngineChatList) {
        self.list = list
    }
}

public enum QuickSwitcherInAppLink {
    case followResolvedName(link: String, username: String, postId: Int32?, forceProfile: Bool, context: any AccountContextProtocol, action: ChatInitialAction?, callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)
    case other
}

public struct QuickSwitcherHooks {
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void
    public let navigateToChatWithFocus: (NavigationViewController?, any AccountContextProtocol, ChatLocation, MessageId?) -> Void
    public let recentlyPeerUsed: (any AccountContextProtocol) -> [PeerId]
    public let openForumTopic: (Int64, PeerId, any AccountContextProtocol, Bool) -> Signal<Bool, NoError>
    public let inAppLink: (NSString, any AccountContextProtocol, PeerId) -> QuickSwitcherInAppLink
    public let forumChatListView: (PeerId, Account) -> Signal<QuickSwitcherChatListUpdate, NoError>
    public let makeSearchTopicItem: (NSSize, AnyHashable, EngineChatList.Item, any AccountContextProtocol) -> TableRowItem
    public let showAccountsLimit: (any AccountContextProtocol, Int) -> Void

    public init(navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void,
                navigateToChatWithFocus: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation, MessageId?) -> Void,
                recentlyPeerUsed: @escaping (any AccountContextProtocol) -> [PeerId],
                openForumTopic: @escaping (Int64, PeerId, any AccountContextProtocol, Bool) -> Signal<Bool, NoError>,
                inAppLink: @escaping (NSString, any AccountContextProtocol, PeerId) -> QuickSwitcherInAppLink,
                forumChatListView: @escaping (PeerId, Account) -> Signal<QuickSwitcherChatListUpdate, NoError>,
                makeSearchTopicItem: @escaping (NSSize, AnyHashable, EngineChatList.Item, any AccountContextProtocol) -> TableRowItem,
                showAccountsLimit: @escaping (any AccountContextProtocol, Int) -> Void) {
        self.navigateToChat = navigateToChat
        self.navigateToChatWithFocus = navigateToChatWithFocus
        self.recentlyPeerUsed = recentlyPeerUsed
        self.openForumTopic = openForumTopic
        self.inAppLink = inAppLink
        self.forumChatListView = forumChatListView
        self.makeSearchTopicItem = makeSearchTopicItem
        self.showAccountsLimit = showAccountsLimit
    }

    private static var _shared: QuickSwitcherHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: QuickSwitcherHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("QuickSwitcherHooks.install must be called before the switcher is used")
        return .placeholder
    }

    public static func install(_ hooks: QuickSwitcherHooks) {
        assert(Thread.isMainThread, "QuickSwitcherHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = QuickSwitcherHooks(navigateToChat: { _, _, _ in
    }, navigateToChatWithFocus: { _, _, _, _ in
    }, recentlyPeerUsed: { _ in
        []
    }, openForumTopic: { _, _, _, _ in
        .single(false)
    }, inAppLink: { _, _, _ in
        .other
    }, forumChatListView: { _, _ in
        .never()
    }, makeSearchTopicItem: { initialSize, stableId, _, _ in
        GeneralRowItem(initialSize, stableId: stableId)
    }, showAccountsLimit: { _, _ in
    })
}
