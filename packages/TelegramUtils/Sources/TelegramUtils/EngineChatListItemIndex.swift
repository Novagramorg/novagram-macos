import Foundation
import Postbox
import TelegramCore

public extension EngineChatList.Item {
    var chatListIndex: ChatListIndex {
        switch self.index {
        case let .chatList(index):
            return index
        case let .forum(pinnedIndex, timestamp, threadId, namespace, id):
            let index: UInt16?
            
            if threadId == 1, self.threadData?.isHidden == true {
                index = 0
            } else {
                switch pinnedIndex {
                case .none:
                    index = nil
                case let .index(value):
                    index = UInt16(value + 1)
                }
            }
            
            return ChatListIndex(pinningIndex: index, messageIndex: .init(id: MessageId(peerId: self.renderedPeer.peerId, namespace: namespace, id: id), timestamp: timestamp))
        }
    }
}
