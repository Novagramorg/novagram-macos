import Postbox
import TelegramCore

func folderSharingInitializeSelection(_ peers: [Peer], selectedIds: Set<PeerId>?, selection: FolderSharingPeerSelection?) {
    for peer in peers {
        if selectedIds == nil || selectedIds!.contains(peer.id) {
            selection?.toggleSelection(peer)
        }
    }
}

func folderSharingToggleAll(_ peers: [Peer], selected: Set<PeerId>, selection: FolderSharingPeerSelection) {
    let allSelected = peers.filter { selected.contains($0.id) }.count == peers.count
    for peer in peers {
        if (allSelected && selected.contains(peer.id)) || (!allSelected && !selected.contains(peer.id)) {
            selection.toggleSelection(peer)
        }
    }
}

func folderSharingJoinedChannelIds(_ peers: [EnginePeer]) -> Set<PeerId> {
    return Set(peers.filter { peer in
        if let channel = peer._asPeer() as? TelegramChannel {
            return channel.participationStatus == .member
        }
        return false
    }.map { $0.id })
}

func folderSharingSaveLink(state: FolderSharingLinkState, original: ExportedChatFolderLink?, edit: (ExportedChatFolderLink, Set<PeerId>, @escaping (ExportedChatFolderLink) -> Void, @escaping () -> Void) -> Void, updated: @escaping (ExportedChatFolderLink, ExportedChatFolderLink?) -> Void, success: @escaping () -> Void, failure: @escaping () -> Void, delete: () -> Void, close: () -> Void) {
    if let current = state.link {
        if state.selected.isEmpty {
            delete()
        } else {
            if state.selected != Set(current.peerIds) || original?.title != current.title {
                edit(current, state.selected, { result in
                    updated(current, result)
                    success()
                }, failure)
            }
            close()
        }
    }
}

func folderSharingDeletedLink(_ link: ExportedChatFolderLink, updated: (ExportedChatFolderLink, ExportedChatFolderLink?) -> Void, close: () -> Void) {
    updated(link, nil)
    close()
}

func folderSharingShouldJoin(_ state: FolderSharingClosureState) -> Bool {
    return !state.isAlreadyInFolder && !state.selected.isEmpty
}

func folderSharingJoinCompleted(close: () -> Void, notify: () -> Void, navigate: () -> Void) {
    close()
    notify()
    navigate()
}

func folderSharingApplyUpdates(hasSelectedToJoin: Bool, join: () -> Void, dismiss: () -> Void, close: () -> Void) {
    if hasSelectedToJoin {
        join()
    } else {
        dismiss()
        close()
    }
}

func folderSharingRemove(hasSharedLinks: Bool, confirm: (@escaping () -> Void) -> Void, invoke: @escaping () -> Void) {
    if hasSharedLinks {
        confirm(invoke)
    } else {
        invoke()
    }
}

func folderSharingProcessJoinError(_ error: JoinChatFolderLinkError, premium: (FolderSharingPremiumLimit) -> Void, inactiveChannels: () -> Void, unknown: () -> Void) {
    switch error {
    case .dialogFilterLimitExceeded:
        premium(.folders)
    case .sharedFolderLimitExceeded:
        premium(.sharedFolders)
    case .tooManyChannels:
        inactiveChannels()
    case .tooManyChannelsInAccount:
        premium(.channels)
    case .generic:
        unknown()
    }
}
