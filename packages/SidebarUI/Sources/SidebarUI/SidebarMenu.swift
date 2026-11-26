import Cocoa
import TelegramCore
import TGUIKit
import Localization

internal enum SidebarMenuAction: Equatable {
    case edit, editFolders, addChats, markRead, mute(Bool), share, delete
}

func sidebarMenuItems(filter: ChatListFilter, unreadCount: Int?, includeAllMuted: Bool?, image: (SidebarMenuImage) -> ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)?, perform: @escaping (SidebarMenuAction) -> Void) -> [ContextMenuItem] {
    guard let data = filter.data else {
        return [ContextMenuItem(strings().chatListFilterEditFilters, handler: { perform(.editFolders) }, itemImage: image(.menu_edit))]
    }
    var items = [ContextMenuItem(strings().chatListFilterEdit, handler: { perform(.edit) }, itemImage: image(.menu_edit)),
                 ContextMenuItem(strings().chatListFilterAddChats, handler: { perform(.addChats) }, itemImage: image(.menu_plus))]
    if let unreadCount = unreadCount, unreadCount > 0 {
        items.append(ContextMenuItem(strings().chatListFilterReadAll, handler: { perform(.markRead) }, itemImage: image(.menu_folder_read)))
    }
    if data.categories.isEmpty && !data.excludeRead && !data.excludeMuted && !data.excludeArchived && data.excludePeers.isEmpty && !data.includePeers.peers.isEmpty, let allMuted = includeAllMuted {
        items.append(ContextMenuItem(allMuted ? strings().chatListFilterUnmuteAll : strings().chatListFilterMuteAll, handler: { perform(.mute(!allMuted)) }, itemImage: image(allMuted ? .menu_unmuted : .menu_mute)))
    }
    if data.isShared {
        items.append(ContextMenuItem(strings().chatListFilterShare, handler: { perform(.share) }, itemImage: image(.menu_share)))
    }
    items.append(ContextSeparatorItem())
    items.append(ContextMenuItem(strings().chatListFilterDelete, handler: { perform(.delete) }, itemMode: .destruct, itemImage: image(.menu_delete)))
    return items
}
