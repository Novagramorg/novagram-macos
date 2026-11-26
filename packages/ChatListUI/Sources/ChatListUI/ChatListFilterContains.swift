import Cocoa
import TelegramCore
import Postbox
import TelegramUtils

extension ChatListFilter {
    public func contains(_ peer: Peer, groupId: PeerGroupId, isRemovedFromTotalUnreadCount: Bool, isUnread: Bool, isContact: Bool, communityCategories: [PeerId: ChatListFilterPeerCategories]) -> Bool {
        if let predicate = chatListFilterPredicate(for: self, communityCategories: communityCategories) {
            return predicate.includes(peer: peer, groupId: groupId, isRemovedFromTotalUnreadCount: isRemovedFromTotalUnreadCount, isUnread: isUnread, isContact: isContact, messageTagSummaryResult: nil)
        }
        return false
    }
}
