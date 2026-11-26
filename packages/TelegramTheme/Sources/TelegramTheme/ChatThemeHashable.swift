import Foundation
import TelegramCore

public extension ChatTheme {
    var wallpaper: TelegramWallpaper {
        switch self {
        case let .emoticon(emoji):
            return .emoticon(emoji)
        case .gift(_, _):
            fatalError()
        }
    }
}

extension ChatTheme : @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .emoticon(emoji):
            hasher.combine("emoji")
            hasher.combine(emoji)
        case let .gift(gift, _):
            hasher.combine("gift")
            switch gift {
            case let .unique(unique):
                hasher.combine(unique.slug)
            default:
                break
            }
        }
    }
}
