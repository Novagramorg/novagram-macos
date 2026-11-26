import Cocoa
import TGUIKit
import GeneralRows
import TelegramCore
import Postbox
import SwiftSignalKit

public protocol FolderSharingPeerSelection: AnyObject {
    var selectedPeerIds: Set<PeerId> { get }
    var action: (PeerId, Int64?) -> Void { get set }
    func toggleSelection(_ peer: Peer)
    func toggleFromRow(_ peer: Peer)
}

public enum FolderSharingMenuImage {
    case copy, edit, delete
}

public enum FolderSharingPremiumLimit {
    case folders, sharedFolders, sharedInvites, channels
}

public protocol FolderSharingUIEnvironment: AnyObject {
    func makeSelection() -> FolderSharingPeerSelection
    func makePeerRow(_ size: NSSize, peer: Peer, enabled: Bool, status: String, selection: FolderSharingPeerSelection?, viewType: GeneralViewType, disabledAction: (() -> Void)?) -> TableRowItem
    func makeInvitationRow(_ size: NSSize, stableId: AnyHashable, link: ExportedChatFolderLink, menuItems: @escaping () -> Signal<[ContextMenuItem], NoError>, share: @escaping (String) -> Void, copyLink: @escaping (String) -> Void) -> TableRowItem
    func makeAnimatedHeader(_ size: NSSize, stableId: AnyHashable, text: NSAttributedString) -> TableRowItem
    func applyInlineStickers(to text: NSMutableAttributedString, entities: [MessageTextEntity], isPremium: Bool)
    func menuImage(_ image: FolderSharingMenuImage) -> ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)?
    func sharingLimits(current: ChatListFilter, links: [ExportedChatFolderLink]?) -> Signal<(limitFilters: Bool, limitInvites: Bool), NoError>
    func navigateToFilter(_ id: Int32)
    func showPremiumLimit(_ limit: FolderSharingPremiumLimit)
    func showInactiveChannels()
    func copyToClipboard(_ text: String)
    func shareLink(_ link: String)
    func promptLinkName(initialText: String, callback: @escaping (String) -> Void)
    func alert(_ text: String)
    func showSuccess()
    func showText(_ text: String, title: String?)
    func confirm(header: String?, information: String?, ok: String?, successHandler: @escaping () -> Void)
}

extension FolderSharingUIEnvironment {
    func confirmAction(header: String? = nil, information: String?, ok: String? = nil, successHandler: @escaping () -> Void) {
        confirm(header: header, information: information, ok: ok, successHandler: successHandler)
    }

    func notify(_ text: String, title: String? = nil) {
        showText(text, title: title)
    }
}
