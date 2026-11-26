import Cocoa
import TelegramCore
import TGUIKit

public extension ChatListFilter {
    var icon: CGImage {
        if case let .filter(_, _, _, data) = self {
            if data.categories == .all && data.excludeMuted && !data.excludeRead {
                return theme.icons.chat_filter_unmuted
            } else if data.categories == .all && !data.excludeMuted && data.excludeRead {
                return theme.icons.chat_filter_unread
            } else if data.categories == .groups {
                return theme.icons.chat_filter_groups
            } else if data.categories == .channels {
                return theme.icons.chat_filter_channels
            } else if data.categories == .contacts {
                return theme.icons.chat_filter_private_chats
            } else if data.categories == .nonContacts {
                return theme.icons.chat_filter_non_contacts
            } else if data.categories == .bots {
                return theme.icons.chat_filter_bots
            }
        }
        return theme.icons.chat_filter_custom
    }
}
