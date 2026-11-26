import Cocoa
import FolderSharingUI
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit

func ShareCloudFolderController(context: AccountContext, filter: ChatListFilter, link: ExportedChatFolderLink?, updated: @escaping (ExportedChatFolderLink, ExportedChatFolderLink?) -> Void) -> InputDataModalController {
    return FolderSharingUI.ShareCloudFolderController(context: context, environment: AppFolderSharingUIEnvironment(context), filter: filter, link: link, updated: updated)
}

func SharedFolderClosureController(context: AccountContext, content: JoinCloudFolderMode) -> InputDataModalController {
    return FolderSharingUI.SharedFolderClosureController(context: context, environment: AppFolderSharingUIEnvironment(context), content: content)
}

func loadAndShowSharedFolder(context: AccountContext, slug: String) {
    FolderSharingUI.loadAndShowSharedFolder(context: context, environment: AppFolderSharingUIEnvironment(context), slug: slug)
}

func shareSharedFolder(context: AccountContext, filter: ChatListFilter) {
    FolderSharingUI.shareSharedFolder(context: context, environment: AppFolderSharingUIEnvironment(context), filter: filter)
}

func deleteSharedFolder(context: AccountContext, filter: ChatListFilter) {
    FolderSharingUI.deleteSharedFolder(context: context, environment: AppFolderSharingUIEnvironment(context), filter: filter)
}

func peerCanBeSharedInFolder(_ peer: Peer, filter: ChatListFilter? = nil) -> Bool {
    return FolderSharingUI.peerCanBeSharedInFolder(peer, filter: filter)
}

private final class AppFolderSharingPeerSelection: FolderSharingPeerSelection {
    let interaction = SelectPeerInteraction()

    var selectedPeerIds: Set<PeerId> {
        return interaction.presentation.selected
    }

    var action: (PeerId, Int64?) -> Void {
        get { interaction.action }
        set { interaction.action = newValue }
    }

    func toggleSelection(_ peer: Peer) {
        interaction.toggleSelection(peer)
    }

    func toggleFromRow(_ peer: Peer) {
        interaction.update { $0.withToggledSelected(peer.id, peer: peer) }
    }
}

private final class AppFolderSharingUIEnvironment: FolderSharingUIEnvironment {
    private let context: AccountContext

    init(_ context: AccountContext) {
        self.context = context
    }

    func makeSelection() -> FolderSharingPeerSelection {
        return AppFolderSharingPeerSelection()
    }

    func makePeerRow(_ size: NSSize, peer: Peer, enabled: Bool, status: String, selection: FolderSharingPeerSelection?, viewType: GeneralViewType, disabledAction: (() -> Void)?) -> TableRowItem {
        let interactionType: ShortPeerItemInteractionType
        if let selection = selection {
            guard let selection = selection as? AppFolderSharingPeerSelection else {
                preconditionFailure("Unexpected folder sharing selection adapter")
            }
            interactionType = .selectable(selection.interaction, side: .left)
        } else {
            interactionType = .plain
        }
        return ShortPeerRowItem(size, peer: peer, account: context.account, context: context, enabled: enabled, status: status, inset: NSEdgeInsets(left: 20, right: 20), interactionType: interactionType, viewType: viewType, disabledAction: disabledAction)
    }

    func makeInvitationRow(_ size: NSSize, stableId: AnyHashable, link: ExportedChatFolderLink, menuItems: @escaping () -> Signal<[ContextMenuItem], NoError>, share: @escaping (String) -> Void, copyLink: @escaping (String) -> Void) -> TableRowItem {
        return ExportedInvitationRowItem(size, stableId: stableId, context: context, exportedLink: _ExportedInvitation.initialize(.link(link: link.link, title: link.title, isPermanent: true, requestApproval: false, isRevoked: false, adminId: context.peerId, date: 0, startDate: 0, expireDate: nil, usageLimit: nil, count: nil, requestedCount: nil, pricing: nil)), lastPeers: [], viewType: .singleItem, mode: .normal(hasUsage: false), menuItems: menuItems, share: share, copyLink: copyLink)
    }

    func makeAnimatedHeader(_ size: NSSize, stableId: AnyHashable, text: NSAttributedString) -> TableRowItem {
        return AnimatedStickerHeaderItem(size, stableId: stableId, context: context, sticker: .share_folder, text: text, stickerSize: NSMakeSize(80, 80))
    }

    func applyInlineStickers(to text: NSMutableAttributedString, entities: [MessageTextEntity], isPremium: Bool) {
        InlineStickerItem.apply(to: text, associatedMedia: [:], entities: entities, isPremium: isPremium)
    }

    func menuImage(_ image: FolderSharingMenuImage) -> ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)? {
        switch image {
        case .copy: return MenuAnimation.menu_copy.value
        case .edit: return MenuAnimation.menu_edit.value
        case .delete: return MenuAnimation.menu_delete.value
        }
    }

    func sharingLimits(current: ChatListFilter, links: [ExportedChatFolderLink]?) -> Signal<(limitFilters: Bool, limitInvites: Bool), NoError> {
        return shareFolderPremiumLimits(context: context, current: current, links: links)
    }

    func navigateToFilter(_ id: Int32) {
        navigateToChatListFilter(id, context: context)
    }

    func showPremiumLimit(_ limit: FolderSharingPremiumLimit) {
        folderSharingPresentPremium(context, limit: limit)
    }

    func showInactiveChannels() {
        folderSharingPresentInactiveChannels(context)
    }

    func copyToClipboard(_ text: String) {
        folderSharingCopyToClipboard(text)
    }

    func shareLink(_ link: String) {
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }

    func promptLinkName(initialText: String, callback: @escaping (String) -> Void) {
        showModal(with: TextInputController(context: context, title: strings().shareFolderNameLinkTitle, placeholder: strings().shareFolderNameLinkPlaceholder, initialText: initialText, limit: 32, callback: callback), for: context.window)
    }

    func alert(_ text: String) {
        folderSharingPresentAlert(context, text: text)
    }

    func showSuccess() {
        folderSharingPresentSuccess(context)
    }

    func showText(_ text: String, title: String?) {
        showModalText(for: context.window, text: text, title: title)
    }

    func confirm(header: String?, information: String?, ok: String?, successHandler: @escaping () -> Void) {
        verifyAlert_button(for: context.window, header: header ?? appName, information: information, ok: ok ?? strings().alertOK, successHandler: { _ in successHandler() })
    }
}

private func folderSharingPresentPremium(_ context: AccountContext, limit: FolderSharingPremiumLimit) {
    switch limit {
    case .folders: showPremiumLimit(context: context, type: .folders)
    case .sharedFolders: showPremiumLimit(context: context, type: .sharedFolders)
    case .sharedInvites: showPremiumLimit(context: context, type: .sharedInvites)
    case .channels: showPremiumLimit(context: context, type: .channels)
    }
}

private func folderSharingPresentInactiveChannels(_ context: AccountContext) {
    showInactiveChannels(context: context, source: .join)
}

private func folderSharingCopyToClipboard(_ text: String) {
    copyToClipboard(text)
}

private func folderSharingPresentAlert(_ context: AccountContext, text: String) {
    alert(for: context.window, info: text)
}

private func folderSharingPresentSuccess(_ context: AccountContext) {
    showSuccess(window: context.window)
}
