import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import TGUIKit
import Localization
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

extension ChatListFilterPeerCategories {
   
    public static let excludeRead = ChatListFilterPeerCategories(rawValue: 1 << 6)
    public static let excludeMuted = ChatListFilterPeerCategories(rawValue: 1 << 7)
    public static let excludeArchived = ChatListFilterPeerCategories(rawValue: 1 << 8)
    
    public static let existingChats = ChatListFilterPeerCategories(rawValue: 1 << 9)
    public static let newChats = ChatListFilterPeerCategories(rawValue: 1 << 10)
    public static let premiumUsers = ChatListFilterPeerCategories(rawValue: 1 << 11)
    public static let miniApps = ChatListFilterPeerCategories(rawValue: 1 << 12)

    public static let Namespace: Int32 = 7
}


public final class TelegramStoryRepostPeerObject : Peer {
    
    public var timeoutAttribute: UInt32?
    
    public var id: PeerId
    
    public var indexName: PeerIndexNameRepresentation
    
    public var associatedPeerId: PeerId?
    public var associatedMediaIds: [MediaId]?
    public var notificationSettingsPeerId: PeerId?
    
    public func isEqual(_ other: Peer) -> Bool {
        if let _ = other as? TelegramStoryRepostPeerObject {
            return true
        }
        return false
    }
    
    
    public init() {
        self.id = PeerId(namespace: Namespaces.Peer.Empty, id: PeerId.Id._internalFromInt64Value(Int64(1000)))
        self.indexName = .title(title: "", addressNames: [""])
        self.notificationSettingsPeerId = nil
    }
    
    public var displayTitle: String? {
        return strings().peerReportStory
    }
    
    
    
    public init(decoder: PostboxDecoder) {
        self.id = PeerId(0)
        self.indexName = .title(title: "", addressNames: [""])
        self.notificationSettingsPeerId = nil
    }
    public func encode(_ encoder: PostboxEncoder) {
        
    }
}



public final class TelegramFilterCategory : Peer {
    
    public var timeoutAttribute: UInt32? 
    
    public var id: PeerId
    
    public var indexName: PeerIndexNameRepresentation
    
    public var associatedPeerId: PeerId?
    public var associatedMediaIds: [MediaId]?
    public var notificationSettingsPeerId: PeerId?
    
    public func isEqual(_ other: Peer) -> Bool {
        if let other = other as? TelegramFilterCategory {
            return other.category == self.category
        }
        return false
    }
    
    public let category: ChatListFilterPeerCategories
    
    public init(category: ChatListFilterPeerCategories) {
        self.id = PeerId(namespace: Namespaces.Peer.Empty, id: PeerId.Id._internalFromInt64Value(Int64(category.rawValue)))
        self.indexName = .title(title: "", addressNames: [""])
        self.notificationSettingsPeerId = nil
        self.category = category
    }
    
    public var displayTitle: String? {
        if category == .contacts {
            return strings().chatListFilterContacts
        }
        if category == .nonContacts {
            return strings().chatListFilterNonContacts
        }
        if category == .groups {
            return strings().chatListFilterGroups
        }
        if category == .channels {
            return strings().chatListFilterChannels
        }
        if category == .bots {
            return strings().chatListFilterBots
        }
        if category == .excludeRead {
            return strings().chatListFilterReadChats
        }
        if category == .excludeMuted {
            return strings().chatListFilterMutedChats
        }
        if category == .excludeArchived {
            return strings().chatListFilterArchive
        }
        if category == .existingChats {
            return strings().chatListFilterExistingChats
        }
        if category == .newChats {
            return strings().chatListFilterNewChats
        }
        if category == .premiumUsers {
            return strings().chatListFilterPremiumUsers
        }
        if category == .miniApps {
            return strings().chatListFilterMiniApps
        }
        return nil
    }
    
    
    
    public init(decoder: PostboxDecoder) {
        self.id = PeerId(0)
        self.indexName = .title(title: "", addressNames: [""])
        self.notificationSettingsPeerId = nil
        self.category = []
    }
    public func encode(_ encoder: PostboxEncoder) {
        
    }
}















extension Peer {
    
    
    public var webUrlRestricted: Bool {
        return hasBannedRights([.banEmbedLinks])
    }
    
    
    public var hasVideo: Bool {
        if let image = self.profileImageRepresentations.first {
            return image.hasVideo
        }
        return false
    }
    
    
    
    
    public var sendPaidMessageStars: StarsAmount? {
        if let channel = self as? TelegramChannel {
            return channel.sendPaidMessageStars
        }
        return nil
    }
    
    
    public var displayTitle: String {
        switch self {
        case let user as TelegramUser:
            if user.id.isAnonymousSavedMessages {
                return strings().chatListAuthorHidden
            }
            if user.firstName == nil && user.lastName == nil {
                return strings().peerDeletedUser
            } else {
                var name: String = ""
                if let firstName = user.firstName {
                    name += firstName
                }
                if let lastName = user.lastName {
                    if user.firstName != nil {
                        name += " "
                    }
                    name += lastName
                }
                if name.isEmpty {
                    if let phone = user.phone {
                        if !phone.isEmpty {
                            name = phone
                        }
                    }
                }
                if name.isEmpty {
                    return " "
                }
                return name
            }
        case let group as TelegramGroup:
            if group.title.isEmpty {
                return " "
            }
            return group.title
        case let channel as TelegramChannel:
            if channel.title.isEmpty {
                return " "
            }
            return channel.title
        case let community as TelegramCommunity:
            if community.title.isEmpty {
                return " "
            }
            return community.title
        case let filter as TelegramFilterCategory:
            let folder = filter.displayTitle ?? ""
            if folder.isEmpty {
                return " "
            }
            return folder
        case let repost as TelegramStoryRepostPeerObject:
            return repost.displayTitle ?? ""
        default:
            return " "
        }
    }
    
    public var rawDisplayTitle: String {
        switch self {
        case let user as TelegramUser:
            if user.firstName == nil && user.lastName == nil {
                return ""
            } else {
                var name: String = ""
                if let firstName = user.firstName {
                    name += firstName
                }
                if let lastName = user.lastName {
                    if user.firstName != nil {
                        name += " "
                    }
                    name += lastName
                }
                return name
            }
        case let group as TelegramGroup:
            return group.title
        case let channel as TelegramChannel:
            return channel.title
        case let community as TelegramCommunity:
            return community.title
        default:
            return ""
        }
    }
    
    public var compactDisplayTitle: String {
        switch self {
        case let user as TelegramUser:
            if user.id.isAnonymousSavedMessages {
                return strings().chatListAuthorHidden
            }
            if let firstName = user.firstName {
                if !firstName.isEmpty {
                    return firstName
                }
            }
            if let lastName = user.lastName {
                if !lastName.isEmpty {
                    return lastName
                }
            }
            if let phone = user.phone {
                if !phone.isEmpty {
                    return phone
                }
            }
            if user.firstName == nil, user.lastName == nil {
                return strings().peerDeletedUser
            }
            return " "
        default:
            return displayTitle
        }
    }
    
    

    
    
    public var isCommunity: Bool {
        return self is TelegramCommunity
    }

    
    
    
}

extension PeerId {
    public static func _optionalInternalFromInt64Value(_ id: Int64) -> PeerId.Id? {
        let peerId = PeerId.Id._internalFromInt64Value(id)
        if id < 0 {
            if let _ = Int32(exactly: id) {
                return peerId
            } else {
                return nil
            }
        }
        return peerId
    }
}


public struct StoryInitialIndex {
    public let peerId: PeerId
    public let id: Int32?
    public let messageId: MessageId?
    public let takeControl:((PeerId, MessageId?, Int32?)->NSView?)?
    public let setProgress:((Signal<Never, NoError>)->Void)?
    public init(peerId: PeerId, id: Int32?, messageId: MessageId?, takeControl: ((PeerId, MessageId?, Int32?) -> NSView?)?, setProgress: ((Signal<Never, NoError>) -> Void)? = nil) {
        self.peerId = peerId
        self.id = id
        self.messageId = messageId
        self.takeControl = takeControl
        self.setProgress = setProgress
    }
}

extension TelegramStoryRepostPeerObject {
    public var icon: EmptyAvatartType? {
        return .icon(colors: theme.colors.peerColors(4), icon: TelegramThemeHooks.shared.image(.iconStoryRepost).precomposed(), iconSize: NSMakeSize(36, 36), cornerRadius: nil)
    }
}

extension TelegramFilterCategory {
    public var icon: EmptyAvatartType? {
        if category == .contacts {
            return .icon(colors: theme.colors.peerColors(5), icon: theme.icons.chat_filter_private_chats_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .nonContacts {
            return .icon(colors: theme.colors.peerColors(1), icon: theme.icons.chat_filter_non_contacts_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .groups {
            return .icon(colors: theme.colors.peerColors(2), icon: theme.icons.chat_filter_large_groups_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .channels {
            return .icon(colors: theme.colors.peerColors(0), icon: theme.icons.chat_filter_channels_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .bots {
            return .icon(colors: theme.colors.peerColors(6), icon: theme.icons.chat_filter_bots_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .excludeMuted {
            return .icon(colors: theme.colors.peerColors(0), icon: theme.icons.chat_filter_muted_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .excludeRead {
            return .icon(colors: theme.colors.peerColors(3), icon: theme.icons.chat_filter_read_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .excludeArchived {
            return .icon(colors: theme.colors.peerColors(5), icon: theme.icons.chat_filter_archive_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .newChats {
            return .icon(colors: theme.colors.peerColors(2), icon: theme.icons.chat_filter_new_chats, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .existingChats {
            return .icon(colors: theme.colors.peerColors(2), icon: theme.icons.chat_filter_existing_chats, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
        }
        if category == .premiumUsers {
            return .icon(colors: (top: premiumGradient[1], bottom: premiumGradient[0]), icon: TelegramThemeHooks.shared.image(.iconPeerPremium).precomposed(.white), iconSize: NSMakeSize(20, 20), cornerRadius: 8)
        }
        if category == .miniApps {
            return .icon(colors: (top: premiumGradient[1], bottom: premiumGradient[0]), icon: TelegramThemeHooks.shared.image(.iconFilterBots).precomposed(.white), iconSize: NSMakeSize(20, 20), cornerRadius: 8)
        }
        return nil
    }
}

extension Peer {
    public var emptyAvatar: EmptyAvatartType? {
        if let peer = self as? TelegramFilterCategory {
            return peer.icon
        }
        if let peer = self as? TelegramStoryRepostPeerObject {
            return peer.icon
        }
        return nil
    }
}
