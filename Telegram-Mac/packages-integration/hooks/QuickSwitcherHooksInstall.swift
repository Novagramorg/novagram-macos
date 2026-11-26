import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import QuickSwitcher

extension SearchTopicRowItem: @retroactive QuickSwitcherTopicRowItem {

}
private func mapQuickSwitcherInAppLink(_ link: inAppLink) -> QuickSwitcherInAppLink {
    switch link {
    case let .followResolvedName(link, username, postId, forceProfile, context, action, callback):
        return .followResolvedName(link: link, username: username, postId: postId, forceProfile: forceProfile, context: context, action: action, callback: callback)
    default:
        return .other
    }
}

func installQuickSwitcherHooks() {
    QuickSwitcherHooks.install(QuickSwitcherHooks(navigateToChat: { navigation, context, chatLocation in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation)
    }, navigateToChatWithFocus: { navigation, context, chatLocation, messageId in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation, focusTarget: .init(messageId: messageId))
    }, recentlyPeerUsed: { context in
        return (context as! AccountContext).recentlyPeerUsed
    }, openForumTopic: { threadId, peerId, context, animated in
        return ForumUI.openTopic(threadId, peerId: peerId, context: context as! AccountContext, animated: animated)
    }, inAppLink: { query, context, peerId in
        return mapQuickSwitcherInAppLink(inApp(for: query, context: context as? AccountContext, peerId: peerId, openInfo: { _, _, _, _ in }, hashtag: nil, command: nil, applyProxy: nil, confirm: false))
    }, forumChatListView: { peerId, account in
        return chatListViewForLocation(chatListLocation: .forum(peerId: peerId), location: .Initial(100, nil), filter: nil, account: account) |> map { QuickSwitcherChatListUpdate(list: $0.list) }
    }, makeSearchTopicItem: { initialSize, stableId, item, context in
        return SearchTopicRowItem(initialSize, stableId: stableId, item: item, context: context as! AccountContext)
    }, showAccountsLimit: { context, count in
        showPremiumLimit(context: context, type: .accounts(count))
    }))
}
