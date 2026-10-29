import Foundation
import Postbox
import TelegramCore

public final class NovagramSearchPrivacyPass {
    private let lockEnabled: Bool
    private var lockedByPeer: [PeerId: Bool] = [:]

    public init() {
        self.lockEnabled = NovagramChatPincodeManager.shared.isMasterEnabled()
    }

    public func isLocked(_ peerId: PeerId) -> Bool {
        guard lockEnabled else {
            return false
        }
        if let cached = lockedByPeer[peerId] {
            return cached
        }
        let locked = NovagramChatPincodeManager.shared.isLocked(peerId)
        lockedByPeer[peerId] = locked
        return locked
    }

    public func hidesMessage(_ message: Message) -> Bool {
        let peerId = message.id.peerId
        if NovagramHiddenChatsManager.shared.isHidden(peerId: peerId) {
            return true
        }
        return isLocked(peerId)
    }
}

public enum NovagramSearchPrivacy {
    public static func kept<T>(_ items: [T], message: (T) -> Message) -> [T] {
        let pass = NovagramSearchPrivacyPass()
        return items.filter { !pass.hidesMessage(message($0)) }
    }

    public static func keptResult(_ result: SearchMessagesResult) -> SearchMessagesResult {
        let messages = kept(result.messages, message: { $0 })
        let removed = result.messages.count - messages.count
        if removed == 0 {
            return result
        }
        return SearchMessagesResult(
            messages: messages,
            readStates: result.readStates,
            threadInfo: result.threadInfo,
            totalCount: max(0, result.totalCount - Int32(removed)),
            completed: result.completed
        )
    }
}
