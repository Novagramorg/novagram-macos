import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import LocalAnimations
import NovagramCore

// "Script ▸ Default / Cyrillic / Old Latin / New Latin" in a private chat's "⋯" header menu (Yangi alifbo, "Lotin ↔ Кирилл" switch on).
func novagramNewAlphabetMenuItem(peer: Peer?, accountPeerId: PeerId, window: Window) -> ContextMenuItem? {
    guard let user = peer as? TelegramUser, user.botInfo == nil, user.id != accountPeerId, let menu = NovagramUzScript.chatScriptMenu(peerId: user.id) else {
        return nil
    }
    let item = ContextMenuItem(menu.title, itemImage: MenuAnimation.menu_translate.value)
    let submenu = ContextMenu()
    for choice in menu.choices {
        submenu.addItem(ContextMenuItem(choice.title, handler: {
            if let notice = choice.select() {
                showModalText(for: window, text: notice)
            }
        }, state: choice.isSelected ? .on : nil))
    }
    item.submenu = submenu
    return item
}
