import Cocoa
import TGUIKit
import Postbox
import LocalAnimations
import TelegramCore
import Localization
import TelegramContext
import NovagramCore

// Chat list row menu items added by Novagram: recent actions (iOS channel history button), chat lock
// (only once a master PIN exists) and hidden chats.
func novagramChatListMenuItems(peerId: PeerId?, peer: Peer?, accountPeerId: PeerId, savedMessages: Bool, context: any AccountContextProtocol) -> [ContextMenuItem] {
    guard let peerId, peerId != accountPeerId, !savedMessages else {
        return []
    }
    let window = context.window
    let l10n = NovagramL10n.current
    var items: [ContextMenuItem] = []

    if NovagramSettingsKey.bool("fenix_channel_history_button"), let channel = peer as? TelegramChannel, channel.adminRights != nil || channel.flags.contains(.isCreator) {
        items.append(ContextMenuItem(strings().peerInfoRecentActions, handler: { [weak context] in
            if let context {
                NovagramHooks.shared.openRecentActions(context, channel)
            }
        }, itemImage: MenuAnimation.menu_list.value))
    }

    let pincode = NovagramChatPincodeManager.shared
    if pincode.isMasterEnabled() {
        if pincode.isLocked(peerId) {
            items.append(ContextMenuItem(l10n.chatLock_menuRemove, handler: {
                NovagramChatPincode.presentRemove(for: window, verify: { pincode.verify($0, for: peerId) }, onSuccess: {
                    pincode.removePincode(for: peerId)
                })
            }, itemImage: MenuAnimation.menu_unlock.value))
        } else {
            items.append(ContextMenuItem(l10n.chatLock_menuSet, handler: {
                NovagramChatPincode.presentSet(for: window) { code in
                    pincode.setPincode(code, for: peerId)
                }
            }, itemImage: MenuAnimation.menu_lock.value))
        }
    }

    let hidden = NovagramHiddenChatsManager.shared
    if hidden.isPeerHiddenInStorage(peerId) {
        items.append(ContextMenuItem(l10n.hiddenChats_unhide, handler: {
            hidden.setHidden(false, for: peerId)
        }, itemImage: MenuAnimation.menu_show_in_finder.value))
    } else {
        items.append(ContextMenuItem(l10n.hiddenChats_hide, handler: {
            hidden.setHidden(true, for: peerId)
        }, itemImage: MenuAnimation.menu_hide.value))
    }
    return items
}
