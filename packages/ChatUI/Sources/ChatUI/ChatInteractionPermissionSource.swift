import Foundation
import TelegramCore
import Postbox
import TelegramContext
import ChatModeTypes
import MessageUtils

extension ChatInteraction: MessagePermissionSource {
    public var permissionMode: ChatMode {
        return self.mode
    }
    public var permissionCachedData: CachedPeerData? {
        return self.presentation.cachedData
    }
    public var permissionContext: any AccountContextProtocol {
        return self.context
    }
}
