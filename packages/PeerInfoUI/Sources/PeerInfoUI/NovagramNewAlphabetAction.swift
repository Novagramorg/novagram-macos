import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import GeneralRows
import TelegramTheme
import NovagramCore

// "Lotin → Кирилл" / "Кирилл → Lotin" in a private chat's profile actions (Yangi alifbo, "Lotin ↔ Кирилл" switch on).
func novagramNewAlphabetActionItem(peer: Peer, accountPeerId: PeerId, color: NSColor, window: Window) -> ActionItem? {
    guard peer is TelegramUser, peer.id != accountPeerId, let menu = NovagramUzScript.chatMenuToggle(peerId: peer.id) else {
        return nil
    }
    let image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: menu.title)?.precomposed(color) ?? theme.icons.profile_more
    return ActionItem(text: menu.title, color: color, image: image, animation: .menu_edit, action: {
        showModalText(for: window, text: menu.toggle())
    })
}
