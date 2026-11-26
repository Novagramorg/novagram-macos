import Foundation
import Postbox
import TelegramCore

extension PeerStoryStats {
    public func subscriptionItem(_ peer: Peer) -> EngineStorySubscriptions.Item {
        return .init(peer: .init(peer), hasUnseen: self.unseenCount > 0, hasUnseenCloseFriends: self.hasUnseenCloseFriends, hasLiveItems: self.hasLiveItems, hasPending: false, storyCount: self.totalCount, unseenCount: self.unseenCount, lastTimestamp: 0)
    }
}
