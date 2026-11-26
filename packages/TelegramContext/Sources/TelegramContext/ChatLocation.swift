import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

public protocol ChatLocationContextHolder: AnyObject {
}

extension ChatReplyThreadMessage {
    public var effectiveTopId: MessageId {
        return self.channelMessageId ?? MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: self.threadId))
    }
}

public enum ChatLocation: Equatable {
    case peer(PeerId)
    case thread(ChatReplyThreadMessage)
}

extension ChatLocation {
    
    public static func makeSaved(_ accountPeerId: PeerId, peerId: PeerId, isMonoforum: Bool = false) -> ChatLocation {
        return .makeSaved(accountPeerId, threadId: peerId.toInt64(), isMonoforum: isMonoforum)
    }
    
    public static func makeSaved(_ accountPeerId: PeerId, threadId: Int64, isMonoforum: Bool = false) -> ChatLocation {
        return .thread(.init(peerId: accountPeerId, threadId: threadId, channelMessageId: nil, isChannelPost: false, isForumPost: false, isMonoforumPost: isMonoforum, maxMessage: nil, maxReadIncomingMessageId: nil, maxReadOutgoingMessageId: nil, unreadCount: 0, initialFilledHoles: IndexSet(), initialAnchor: .automatic, isNotAvailable: false))
    }
    
    public var unreadMessageCountsItem: UnreadMessageCountsItem {
        switch self {
        case let .peer(peerId):
            return .peer(id: peerId, handleThreads: false)
        case let .thread(data):
            return .peer(id: data.peerId, handleThreads: false)
        }
    }
    
    public var postboxViewKey: PostboxViewKey {
        switch self {
        case let .peer(peerId):
            return .peer(peerId: peerId, components: [])
        case let .thread(data):
            return .peer(peerId: data.peerId, components: [])
        }
    }
    
    public var pinnedItemId: PinnedItemId {
        switch self {
        case let .peer(peerId):
            return .peer(peerId)
        case let .thread(data):
            return .peer(data.peerId)
        }
    }
    
    public var peerId: PeerId {
        switch self {
        case let .peer(peerId):
            return peerId
        case let .thread(data):
            return data.peerId
        }
    }
    public var threadId: Int64? {
        switch self {
        case .peer:
            return nil
        case let .thread(replyThreadMessage):
            return replyThreadMessage.threadId
        }
    }
    public var threadMsgId: MessageId? {
        switch self {
        case .peer:
            return nil
        case let .thread(replyThreadMessage):
            return replyThreadMessage.effectiveTopId
        }
    }
    public var threadMessage: ChatReplyThreadMessage? {
        switch self {
        case .peer:
            return nil
        case let .thread(replyThreadMessage):
            return replyThreadMessage
        }
    }

}

extension ChatLocation : Hashable {
    public func hash(into hasher: inout Hasher) {
    }
}
