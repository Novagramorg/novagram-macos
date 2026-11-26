import TelegramCore
import Postbox
import Localization

extension ChatListFilter {
    var data: ChatListFilterData? {
        switch self {
        case .allChats:
            return nil
        case let .filter(_, _, _, data):
            return data
        }
    }

    var isAllChats: Bool {
        switch self {
        case .allChats:
            return true
        case .filter:
            return false
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

    var enableAnimations: Bool {
        switch self {
        case .allChats:
            return false
        case let .filter(_, title, _, _):
            return title.enableAnimations
        }
    }

    var emoticon: String? {
        switch self {
        case .allChats:
            return nil
        case let .filter(_, _, emoticon, _):
            return emoticon
        }
    }
    var sidebarId: Int32 {
        switch self {
        case .allChats:
            return -1
        case let .filter(id, _, _, _):
            return id
        }
    }

    func withUpdatedTitle(string: String, entities: [MessageTextEntity], enableAnimations: Bool) -> ChatListFilter {
        switch self {
        case .allChats:
            return self
        case let .filter(id, _, emoticon, data):
            return .filter(id: id, title: .init(text: string, entities: entities, enableAnimations: enableAnimations), emoticon: emoticon, data: data)
        }
    }

    func withUpdatedTitle(_ title: ChatFolderTitle) -> ChatListFilter {
        switch self {
        case .allChats:
            return self
        case let .filter(id, _, emoticon, data):
            return .filter(id: id, title: title, emoticon: emoticon, data: data)
        }
    }

    func withUpdatedEmoticon(_ string: String) -> ChatListFilter {
        switch self {
        case .allChats:
            return self
        case let .filter(id, title, _, data):
            return .filter(id: id, title: title, emoticon: string, data: data)
        }
    }
    func withUpdatedData(_ data: ChatListFilterData) -> ChatListFilter {
        switch self {
        case .allChats:
            return self
        case let .filter(id, title, emoticon, _):
            return .filter(id: id, title: title, emoticon: emoticon, data: data)
        }
    }
}




struct SidebarPeerEquatable: Equatable {
    let peer: Peer

    init(_ peer: Peer) {
        self.peer = peer
    }

    static func == (lhs: SidebarPeerEquatable, rhs: SidebarPeerEquatable) -> Bool {
        return lhs.peer.isEqual(rhs.peer)
    }
}
