import Foundation
import TelegramCore
import Postbox

public func messageForForwarding(_ message: Message) -> Message {
    return message.activeEphemeralReplacementMessage ?? message
}

public extension Message {
    func isCopyProtected(cachedData: CachedPeerData?) -> Bool {
        if self.isCopyProtected() {
            return true
        }
        if let _ = self.peers[self.id.peerId] as? TelegramUser, let cachedData = cachedData as? CachedUserData {
            return cachedData.flags.contains(.copyProtectionEnabled) || cachedData.flags.contains(.myCopyProtectionEnabled)
        }
        return false
    }
}
