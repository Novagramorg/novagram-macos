import Cocoa
import TelegramCore
import TGUIKit
import TelegramTheme
import ColorPalette
import TelegramContext

public extension PeerColor {
    var nameColor: PeerNameColor? {
        switch self {
        case let .preset(value):
            return value
        default:
            return nil
        }
    }
    func nameColors(_ context: any AccountContextProtocol, isDark: Bool = theme.colors.isDark)-> PeerNameColors.Colors {
        return nameColors(context.peerNameColors, isDark: isDark)
    }
    func nameColors(_ colors: PeerNameColors, isDark: Bool = theme.colors.isDark)-> PeerNameColors.Colors {
        switch self {
        case let .preset(value):
            return colors.get(value)
        case let .collectible(value):
            let dark = value.darkColors?.map { NSColor($0) }
            let light = value.colors.map { NSColor($0) }
            if isDark {
                return .init(colors: dark ?? light) ?? .init(main: NSColor(value.accentColor))
            } else {
                return .init(colors: light) ?? .init(main: NSColor(value.accentColor))
            }
        }
    }
    func profileColors(_ context: any AccountContextProtocol)-> PeerNameColors.Colors {
        switch self {
        case let .preset(value):
            return context.peerNameColors.getProfile(value)
        case .collectible:
            return nameColors(context)
        }
    }

    func getUpdate(_ backgroundEmojiId: Int64?) -> UpdateNameColor {
        switch self {
        case let .preset(value):
            return .preset(color: value, backgroundEmojiId: backgroundEmojiId)
        case let .collectible(value):
            return .collectible(value)
        }
    }

    var collectibleId: Int64? {
        switch self {
        case .preset:
            return nil
        case let .collectible(value):
            return value.collectibleId
        }
    }
}
