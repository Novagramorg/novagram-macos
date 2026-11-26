import TelegramCore
import Postbox
import Localization
import SwiftSignalKit

extension ChatListFilter {
    var data: ChatListFilterData? {
        switch self {
        case .allChats:
            return nil
        case let .filter(_, _, _, data):
            return data
        }
    }

    var title: String {
        switch self {
        case .allChats:
            return strings().chatListFilterAllChats
        case let .filter(_, title, _, _):
            return title.text
        }
    }

    var entities: [MessageTextEntity] {
        switch self {
        case .allChats:
            return []
        case let .filter(_, title, _, _):
            return title.entities
        }
    }

    var folderSharingId: Int32 {
        switch self {
        case .allChats:
            return -1
        case let .filter(id, _, _, _):
            return id
        }
    }

}

struct FolderSharingPeer: Equatable {
    let peer: Peer

    init(_ peer: Peer) {
        self.peer = peer
    }

    init?(_ peer: Peer?) {
        guard let peer = peer else { return nil }
        self.peer = peer
    }

    static func == (lhs: FolderSharingPeer, rhs: FolderSharingPeer) -> Bool {
        return lhs.peer.isEqual(rhs.peer)
    }
}

func folderSharingPeerView(peerId: PeerId, postbox: Postbox) -> Signal<Peer?, NoError> {
    return postbox.combinedView(keys: [.basicPeer(peerId)]) |> map { view in
        return (view.views[.basicPeer(peerId)] as? BasicPeerView)?.peer
    }
}
