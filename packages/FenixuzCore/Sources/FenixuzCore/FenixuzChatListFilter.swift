import AppKit
import Postbox
import TelegramCore
import TGUIKit

// Chat list rules from Settings → Novagram: hidden chats, foreign-number block, hide folders, stories strip.
public enum FenixuzChatListFilter {
    // Posted by every Novagram settings toggle.
    public static let settingsChanged = Notification.Name("FenixSettingsChanged")

    public static var hideFolders: Bool {
        return FenixuzSettingsKey.bool("hide_folders")
    }

    public static var showStories: Bool {
        return FenixuzSettingsKey.bool("show_stories", default: true)
    }

    public static func isFiltered(peerId: PeerId, mainPeer: Peer?, myPhone: String?) -> Bool {
        if FenixuzHiddenChatsManager.shared.isHidden(peerId: peerId) {
            return true
        }
        if FenixuzSettingsKey.bool("block_foreign_users"), isForeignUser(peer: mainPeer, myPhone: myPhone) {
            return true
        }
        return false
    }
}

// Cmd+Shift+H reveals or hides the hidden chats. One monitor for the whole app (the old fork added one per chat list).
public enum FenixuzHiddenChatsShortcut {
    private static var monitor: Any?

    public static func install() {
        guard monitor == nil else {
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains([.command, .shift]), event.charactersIgnoringModifiers?.lowercased() == "h", let window = NSApp.keyWindow as? Window else {
                return event
            }
            FenixuzHiddenChatsManager.shared.toggleReveal(for: window)
            return nil
        }
    }
}
