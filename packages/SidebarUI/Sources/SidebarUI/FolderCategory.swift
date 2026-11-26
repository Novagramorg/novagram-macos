import TelegramCore

extension ChatListFilterPeerCategories {
    static let excludeRead = ChatListFilterPeerCategories(rawValue: 1 << 6)
    static let excludeMuted = ChatListFilterPeerCategories(rawValue: 1 << 7)
    static let excludeArchived = ChatListFilterPeerCategories(rawValue: 1 << 8)
}
