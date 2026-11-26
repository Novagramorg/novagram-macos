import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import GeneralRows
import Localization

public enum WalletUIAnimation {
    case wallet_word_list
    case wallet_word_check
}

public enum WalletUIMenuImage {
    case menu_folder_coin
    case menu_folder_lock
    case menu_apps
    case menu_show_info
    case menu_open_with
    case menu_plus
    case menu_message
    case menu_lock
    case menu_cloud
    case menu_gram
    case menu_globe
    case menu_change_colors
    case menu_add
    case menu_hide
}

open class WalletUIAvatarView: View {
    open func update(peer: Peer?, synchronousLoad: Bool = false) {
    }
}

public protocol WalletUIEnvironment: AnyObject {
    func shortTimestamp(hours: Int32, minutes: Int32) -> String
    func peerTitle(_ peer: Peer, compact: Bool) -> String
    func openChat(_ peerId: PeerId)
    func openAccountProtection()
    func openPasscodeSettings()
    func rarityBadge(_ rarity: StarGift.UniqueGift.Attribute.Rarity) -> (text: String, color: NSColor?)
    func openGiftValue(_ gift: StarGift.UniqueGift)
    func openGiftStore(_ gift: StarGift.Gift)
    func openGift(_ gift: StarGift.UniqueGift)
    func openExternalURL(_ url: String)
    func prepareOnrampNavigation(_ url: String) -> (() -> Void)?
    func presentAlert(window: Window, header: String?, text: String?, ok: String, onClose: (() -> Void)?)
    func presentAlert(window: Window, header: String?, ok: String, content: @escaping (NSSize, AnyHashable) -> TableRowItem)
    func presentDismissableAlert(window: Window, header: String?, text: String?, ok: String) -> () -> Void
    func presentConfirmation(window: Window, header: String, ok: String, cancel: String, content: @escaping (NSSize, AnyHashable, @escaping () -> Void) -> TableRowItem, confirmed: @escaping () -> Void)
    func presentConfirmation(window: Window, header: String, text: String?, ok: String, cancel: String, buttonStyle: Bool, confirmed: @escaping () -> Void, cancelled: @escaping () -> Void)
    func presentConfirmation(window: Window, header: String, text: String?, ok: String, cancel: String, option: String, optionIsSelected: Bool, confirmed: @escaping (Bool) -> Void, cancelled: @escaping () -> Void)
    func presentText(window: Window, text: String, title: String?, button: String?, callback: ((String) -> Void)?)
    func clipboardString() -> String?
    func copyToClipboard(_ text: String)
    func menuImage(_ image: WalletUIMenuImage) -> ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)?
    func makeLoadingRow(_ size: NSSize, stableId: AnyHashable, height: CGFloat, viewType: GeneralViewType) -> TableRowItem
    func makePeerRow(_ size: NSSize, stableId: AnyHashable, peer: Peer, status: String?, isResolving: Bool, viewType: GeneralViewType, action: @escaping () -> Void, deselect: (() -> Void)?) -> TableRowItem
    func makeAnimatedHeader(_ size: NSSize, stableId: AnyHashable, sticker: WalletUIAnimation?, text: NSAttributedString, infoText: NSAttributedString, stickerSize: NSSize, image: CGImage?, infoLinkHandler: ((String) -> Void)?, viewType: GeneralViewType) -> TableRowItem
    func webFilePhoto(photo: TelegramMediaWebFile, scale: CGFloat, useActualDimensions: Bool) -> Signal<ImageDataTransformation, NoError>
    func ownerAvatar(_ peer: Peer, size: NSSize, font: NSFont) -> Signal<CGImage?, NoError>
    func makeAvatar(font: NSFont) -> WalletUIAvatarView
    func setCollectibleAnimation(in view: Control, contents: Data?, key: String, size: NSSize)
}

extension WalletUIEnvironment {
    func makeAnimatedHeader(_ size: NSSize, stableId: AnyHashable, sticker: WalletUIAnimation?, text: NSAttributedString, infoText: NSAttributedString, stickerSize: NSSize, image: CGImage?, viewType: GeneralViewType = .legacy) -> TableRowItem {
        makeAnimatedHeader(size, stableId: stableId, sticker: sticker, text: text, infoText: infoText, stickerSize: stickerSize, image: image, infoLinkHandler: nil, viewType: viewType)
    }

    func alert(for window: Window, header: String? = "Telegram", info: String?, ok: String = strings().modalOK, onClose: (() -> Void)? = nil) {
        presentAlert(window: window, header: header, text: info, ok: ok, onClose: onClose)
    }

    func dismissableAlert(for window: Window, header: String? = "Telegram", info: String?, ok: String = strings().modalOK) -> () -> Void {
        presentDismissableAlert(window: window, header: header, text: info, ok: ok)
    }

    func verifyAlert(for window: Window, header: String, information: String?, ok: String, cancel: String, successHandler: @escaping (Bool) -> Void, cancelHandler: @escaping () -> Void = {}) {
        presentConfirmation(window: window, header: header, text: information, ok: ok, cancel: cancel, buttonStyle: false, confirmed: { successHandler(true) }, cancelled: cancelHandler)
    }

    func verifyAlert(for window: Window, header: String, information: String?, ok: String, cancel: String, option: String, optionIsSelected: Bool, successHandler: @escaping (Bool) -> Void, cancelHandler: @escaping () -> Void = {}) {
        presentConfirmation(window: window, header: header, text: information, ok: ok, cancel: cancel, option: option, optionIsSelected: optionIsSelected, confirmed: successHandler, cancelled: cancelHandler)
    }

    func verifyAlert_button(for window: Window, header: String, information: String?, ok: String, cancel: String, successHandler: @escaping (Bool) -> Void, cancelHandler: @escaping () -> Void = {}) {
        presentConfirmation(window: window, header: header, text: information, ok: ok, cancel: cancel, buttonStyle: true, confirmed: { successHandler(true) }, cancelled: cancelHandler)
    }

    func showModalText(for window: Window, text: String, title: String? = nil, button: String? = nil, callback: ((String) -> Void)? = nil) {
        presentText(window: window, text: text, title: title, button: button, callback: callback)
    }

    func webFilePhoto(photo: TelegramMediaWebFile, scale: CGFloat) -> Signal<ImageDataTransformation, NoError> {
        return webFilePhoto(photo: photo, scale: scale, useActualDimensions: false)
    }
}
