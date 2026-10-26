import Foundation
import Postbox
import TGUIKit

// Chat lock gate for opening a chat from the chat list. A chat unlocked once stays unlocked until the app quits.
public extension NovagramChatPincode {
    private static var sessionUnlocked = Set<PeerId>()

    // Returns true when the chat is locked: the PIN sheet is shown and `reopen` runs after a correct PIN.
    static func requiresUnlock(peerId: PeerId, window: Window, reopen: @escaping () -> Void) -> Bool {
        let manager = NovagramChatPincodeManager.shared
        guard manager.isLocked(peerId), !sessionUnlocked.contains(peerId) else {
            return false
        }
        let proceed: () -> Void = {
            sessionUnlocked.insert(peerId)
            reopen()
        }
        let onForgot: (() -> Void)? = manager.isMasterEnabled() ? {
            presentMasterRecovery(for: window, onSuccess: {
                manager.removePincode(for: peerId)
                proceed()
            })
        } : nil
        presentVerify(for: window, verify: { manager.verify($0, for: peerId) }, onSuccess: proceed, onForgot: onForgot)
        return true
    }
}
