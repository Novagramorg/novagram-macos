import Cocoa

extension FolderEmoticon {
    public var drawable: MenuAnimation {
        switch self {
        case .allChats:
            return .menu_folder_all_chats
        case .groups:
            return .menu_folder_group
        case .read:
            return .menu_folder_read
        case .unread:
            return .menu_folder_unread
        case .personal:
            return .menu_folder_personal
        case .unmuted:
            return .menu_unmuted
        case .channels:
            return .menu_channel
        case .bots:
            return .menu_folder_bot
        case .folder:
            return .menu_folder_folder
        case let .emoji(emoji):
            switch emoji {
            case "👤":
                return .menu_folder_personal
            case "👥":
                return .menu_folder_group
            case "📢":
                return .menu_channel
            case "💬":
                return .menu_folder_all_chats
            case "✅":
                return .menu_folder_read
            case "☑️":
                return .menu_folder_unread
            case "🔔":
                return .menu_unmuted
            case "🗂":
                return .menu_folder_folder
            case "🤖":
                return .menu_folder_bot
            case "🐶", "🐱":
                return .menu_folder_animal
            case "📕":
                return .menu_folder_book
            case "💰":
                return .menu_folder_coin
            case "📸":
                return .menu_folder_flash
            case "🎮":
                return .menu_folder_game
            case "🏡":
                return .menu_folder_home
            case "💡":
                return .menu_folder_lamp
            case "👍":
                return .menu_folder_like
            case "🔒":
                return .menu_folder_lock
            case "❤️":
                return .menu_folder_love
            case "➕":
                return .menu_folder_math
            case "🎵":
                return .menu_folder_music
            case "🎨":
                return .menu_folder_paint
            case "✈️":
                return .menu_folder_plane
            case "⚽️":
                return .menu_folder_sport
            case "⭐":
                return .menu_folder_star
            case "🎓":
                return .menu_folder_student
            case "🛫":
                return .menu_folder_telegram
            case "👨‍💼":
                return .menu_folder_work
            default:
                return .menu_folder_folder
            }
        }
    }


}
