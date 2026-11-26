import Foundation
import Postbox
import TelegramCore

public struct MessagePermissionHooks {
    public let canSendMessage: (Peer, Bool, MessageHistoryThreadData?) -> Bool

    public init(canSendMessage: @escaping (Peer, Bool, MessageHistoryThreadData?) -> Bool) {
        self.canSendMessage = canSendMessage
    }

    public static var shared: MessagePermissionHooks = MessagePermissionHooks(canSendMessage: { _, _, _ in return false })
}

public func installMessagePermissionHooks(_ hooks: MessagePermissionHooks) {
    MessagePermissionHooks.shared = hooks
}
