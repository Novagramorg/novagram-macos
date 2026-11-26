import Foundation
import Postbox
import TelegramCore
import TelegramUtils

public enum ChatHistoryEntryId : Hashable {
    case message(Message)
    case groupedPhotos(groupInfo: MessageGroupInfo)
    case unread
    case date(MessageIndex)
    case undefined
    case empty(MessageIndex)
    case maybeId(AnyHashable)
    case mediaId(AnyHashable, Message)
    case commentsHeader
    case repliesHeader
    case topThreadInset
    case userInfo
    case topicSeparator(MessageIndex)
    case newThread(MessageIndex)
    case bottom
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .message(let message):
            hasher.combine(0)
            hasher.combine(message.stableId)
        case .groupedPhotos(let groupInfo):
            hasher.combine(1)
            hasher.combine(groupInfo.stableId)
        case .unread:
            hasher.combine(2)
        case .date(let index):
            hasher.combine(3)
            hasher.combine(index)
        case .undefined:
            hasher.combine(4)
        case .empty(let index):
            hasher.combine(5)
            hasher.combine(index)
        case .maybeId(let id):
            hasher.combine(6)
            hasher.combine(id)
        case .mediaId(let id, let message):
            hasher.combine(7)
            hasher.combine(id)
            hasher.combine(message.stableId)
        case .commentsHeader:
            hasher.combine(8)
        case .repliesHeader:
            hasher.combine(9)
        case .topThreadInset:
            hasher.combine(10)
        case .userInfo:
            hasher.combine(11)
        case .topicSeparator(let index):
            hasher.combine(12)
            hasher.combine(index)
        case .newThread(let index):
            hasher.combine(13)
            hasher.combine(index)
        case .bottom:
            hasher.combine(14)
        }
    }
    
    public static func ==(lhs:ChatHistoryEntryId, rhs: ChatHistoryEntryId) -> Bool {
        switch lhs {
        case .message(let lhsMessage):
            if case .message(let rhsMessage) = rhs {
                return lhsMessage.stableId == rhsMessage.stableId
            } else {
                return false
            }
        case let .groupedPhotos(groupingKey):
            if case .groupedPhotos(groupingKey) = rhs {
                return true
            } else {
                return false
            }
        case let .mediaId(id, entryId):
            if case .mediaId(id, entryId) = rhs {
                return true
            } else {
                return false
            }
        case .unread:
            if case .unread = rhs {
                return true
            } else {
                return false
            }
        case .date(let index):
            if case .date(index) = rhs {
                return true
            } else {
                return false
            }
        case .maybeId(let id):
            if case .maybeId(id) = rhs {
                return true
            } else {
                return false
            }
        case .undefined:
            if case .undefined = rhs {
                return true
            } else {
                return false
            }
        case let .empty(index):
            if case .empty(index) = rhs {
                return true
            } else {
                return false
            }
        case .commentsHeader:
            if case .commentsHeader = rhs {
                return true
            } else {
                return false
            }
        case .repliesHeader:
            if case .repliesHeader = rhs {
                return true
            } else {
                return false
            }
        case .topThreadInset:
            if case .topThreadInset = rhs {
                return true
            } else {
                return false
            }
        case .userInfo:
            if case .userInfo = rhs {
                return true
            } else {
                return false
            }
        case let .topicSeparator(index):
            if case .topicSeparator(index) = rhs {
                return true
            } else {
                return false
            }
        case let .newThread(index):
            if case .newThread(index) = rhs {
                return true
            } else {
                return false
            }
        case .bottom:
            if case .bottom = rhs {
                return true
            } else {
                return false
            }
        }
    }
    
    public var stableIndex: UInt64 {
        switch self {
        case .message:
            return UInt64(1) << 40
        case .groupedPhotos:
            return UInt64(2) << 40
        case .unread:
             return UInt64(3) << 40
        case .date:
            return UInt64(4) << 40
        case .undefined:
            return UInt64(5) << 40
        case .maybeId:
            return UInt64(6) << 40
        case .commentsHeader:
            return UInt64(7) << 40
        case .repliesHeader:
            return UInt64(8) << 40
        case .topThreadInset:
            return UInt64(9) << 40
        case .empty:
            return UInt64(10) << 40
        case .mediaId:
            return UInt64(11) << 40
        case .userInfo:
            return UInt64(12) << 40
        case .topicSeparator:
            return UInt64(13) << 40
        case .newThread:
            return UInt64(14) << 40
        case .bottom:
            return UInt64(15) << 40
        }
    }

}

public extension Message {
    var chatStableId: ChatHistoryEntryId {
        return ChatHistoryEntryId.message(self)
    }
}
