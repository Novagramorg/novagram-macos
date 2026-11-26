import Cocoa
import TGUIKit
import TelegramCore
import TelegramTheme
import TelegramUtils



public enum FolderIconState {
    case sidebar
    case sidebarActive
    case preview
    case settings
    var color: NSColor {
        switch self {
        case .sidebar:
            return theme.colors.text.withAlphaComponent(0.75)
        case .sidebarActive:
            return theme.colors.accent
        case .preview:
            return theme.colors.grayIcon
        case .settings:
            return theme.colors.grayIcon
        }
    }
}

public let allSidebarFolderIcons: [FolderIcon] = [FolderIcon(emoticon: .emoji("🐱")),
                                           FolderIcon(emoticon: .emoji("📕")),
                                           FolderIcon(emoticon: .emoji("💰")),
                                           FolderIcon(emoticon: .emoji("📸")),
                                           FolderIcon(emoticon: .emoji("🎮")),
                                           FolderIcon(emoticon: .emoji("🏡")),
                                           FolderIcon(emoticon: .emoji("💡")),
                                           FolderIcon(emoticon: .emoji("👍")),
                                           FolderIcon(emoticon: .emoji("🔒")),
                                           FolderIcon(emoticon: .emoji("❤️")),
                                           FolderIcon(emoticon: .emoji("➕")),
                                           FolderIcon(emoticon: .emoji("🎵")),
                                           FolderIcon(emoticon: .emoji("🎨")),
                                           FolderIcon(emoticon: .emoji("✈️")),
                                           FolderIcon(emoticon: .emoji("⚽️")),
                                           FolderIcon(emoticon: .emoji("⭐")),
                                           FolderIcon(emoticon: .emoji("🎓")),
                                           FolderIcon(emoticon: .emoji("🛫")),
                                           FolderIcon(emoticon: .emoji("👨‍💼")),
                                           FolderIcon(emoticon: .emoji("👤")),
                                           FolderIcon(emoticon: .emoji("👥")),
                                           //FolderIcon(emoticon: .emoji("📢")),
                                           FolderIcon(emoticon: .emoji("💬")),
                                           FolderIcon(emoticon: .emoji("✅")),
                                           FolderIcon(emoticon: .emoji("☑️")),
                                           FolderIcon(emoticon: .emoji("🤖")),
                                           FolderIcon(emoticon: .emoji("🗂"))]



public enum FolderEmoticon {
    case emoji(String)
    case allChats
    case groups
    case read
    case personal
    case unmuted
    case unread
    case channels
    case bots
    case folder

    public var emoji: String? {
        switch self {
        case let .emoji(emoji):
            return emoji
        case .allChats: return "💬"
        case .personal: return "👤"
        case .groups: return "👥"
        case .read: return "✅"
        case .unmuted: return "🔔"
        case .unread: return "☑️"
        case .channels: return "📢"
        case .bots: return "🤖"
        case .folder: return "🗂"
        }
    }

    public var iconName: String {
        switch self {
        case .allChats:
            return "Icon_Sidebar_AllChats"
        case .groups:
            return "Icon_Sidebar_Group"
        case .read:
            return "Icon_Sidebar_Read"
        case .unread:
            return "Icon_Sidebar_Unread"
        case .personal:
            return "Icon_Sidebar_Personal"
        case .unmuted:
            return "Icon_Sidebar_Unmuted"
        case .channels:
            return "Icon_Sidebar_Channel"
        case .bots:
            return "Icon_Sidebar_Bot"
        case .folder:
            return "Icon_Sidebar_Folder"
        case let .emoji(emoji):
            switch emoji {
            case "👤":
                return "Icon_Sidebar_Personal"
            case "👥":
                return "Icon_Sidebar_Group"
            case "📢":
                return "Icon_Sidebar_Channel"
            case "💬":
                return "Icon_Sidebar_AllChats"
            case "✅":
                return "Icon_Sidebar_Read"
            case "☑️":
                return "Icon_Sidebar_Unread"
            case "🔔":
                return "Icon_Sidebar_Unmuted"
            case "🗂":
                return "Icon_Sidebar_Folder"
            case "🤖":
                return "Icon_Sidebar_Bot"
            case "🐶", "🐱":
                return "Icon_Sidebar_Animal"
            case "📕":
                return "Icon_Sidebar_Book"
            case "💰":
                return "Icon_Sidebar_Coin"
            case "📸":
                return "Icon_Sidebar_Flash"
            case "🎮":
                return "Icon_Sidebar_Game"
            case "🏡":
                return "Icon_Sidebar_Home"
            case "💡":
                return "Icon_Sidebar_Lamp"
            case "👍":
                return "Icon_Sidebar_Like"
            case "🔒":
                return "Icon_Sidebar_Lock"
            case "❤️":
                return "Icon_Sidebar_Love"
            case "➕":
                return "Icon_Sidebar_Math"
            case "🎵":
                return "Icon_Sidebar_Music"
            case "🎨":
                return "Icon_Sidebar_Paint"
            case "✈️":
                return "Icon_Sidebar_Plane"
            case "⚽️":
                return "Icon_Sidebar_Sport"
            case "⭐":
                return "Icon_Sidebar_Star"
            case "🎓":
                return "Icon_Sidebar_Student"
            case "🛫":
                return "Icon_Sidebar_Telegram"
            case "👨‍💼":
                return "Icon_Sidebar_Work"
            case "🍷":
                return "Icon_Sidebar_Wine"
            case "🎭":
                return "Icon_Sidebar_Mask"
            default:
                return "Icon_Sidebar_Folder"
            }
        }
    }
}

public final class FolderIcon {
    public let emoticon: FolderEmoticon

    public init(emoticon: FolderEmoticon) {
        self.emoticon = emoticon
    }

    public func icon(for state: FolderIconState, image: (String) -> NSImage) -> CGImage {
        return image(self.emoticon.iconName).precomposed(state.color, flipVertical: state == .preview)
    }

}

public enum ChatListFilterType {
    case generic
    case unmuted
    case unread
    case channels
    case groups
    case bots
    case contacts
    case nonContacts
}

public func chatListFilterType(_ filter: ChatListFilter) -> ChatListFilterType {
    let filterType: ChatListFilterType
    switch filter {
    case .allChats:
        filterType = .generic
    case let .filter(_, _, _, data):
        if data.includePeers.peers.isEmpty {
            if data.categories == .all {
                if data.excludeRead {
                    filterType = .unread
                } else if data.excludeMuted {
                    filterType = .unmuted
                } else {
                    filterType = .generic
                }
            } else {
                if data.categories == .channels {
                    filterType = .channels
                } else if data.categories == .groups {
                    filterType = .groups
                } else if data.categories == .bots {
                    filterType = .bots
                } else if data.categories == .contacts {
                    filterType = .contacts
                } else if data.categories == .nonContacts {
                    filterType = .nonContacts
                } else {
                    filterType = .generic
                }
            }
        } else {
            filterType = .generic
        }
    }

    return filterType
}

public extension FolderIcon {
    convenience init(_ filter: ChatListFilter) {
        switch filter {
        case .allChats:
            self.init(emoticon: .allChats)
        case .filter:
            if let emoticon = filter.emoticon {
                self.init(emoticon: .emoji(emoticon))
            } else {
                switch chatListFilterType(filter) {
                case .bots:
                    self.init(emoticon: .bots)
                case .channels:
                    self.init(emoticon: .channels)
                case .contacts:
                    self.init(emoticon: .personal)
                case .groups:
                    self.init(emoticon: .groups)
                case .nonContacts:
                    self.init(emoticon: .personal)
                case .unmuted:
                    self.init(emoticon: .unmuted)
                case .unread:
                    self.init(emoticon: .unread)
                case .generic:
                    self.init(emoticon: .folder)
                }
            }
        }
    }
}
