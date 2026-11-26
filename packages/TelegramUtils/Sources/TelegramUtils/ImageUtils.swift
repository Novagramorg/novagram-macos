import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import TGUIKit
import ColorPalette
#if !SHARE
import TelegramMediaResources
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif
#endif




private extension PeerNameColors.Colors {
    init?(colors: EngineAvailableColorOptions.MultiColorPack) {
        if colors.colors.isEmpty {
            return nil
        }
        let secondary: NSColor?
        let tertiary: NSColor?
        
        let main = NSColor(rgb: colors.colors[0])
        if colors.colors.count > 1 {
            secondary = NSColor(rgb: colors.colors[1])
        } else {
            secondary = nil
        }
        if colors.colors.count > 2 {
            tertiary = NSColor(rgb: colors.colors[2])
        } else {
            tertiary = nil
        }
        self.init(main: main, secondary: secondary, tertiary: tertiary)
    }
}


extension PeerNameColors {
    
    
    public func getProfile(_ color: PeerNameColor, dark: Bool = false, subject: Subject = .background) -> Colors {
        switch subject {
        case .background:
            if dark, let colors = self.profileDarkColors[color.rawValue] {
                return colors
            } else if let colors = self.profileColors[color.rawValue] {
                return colors
            } else if case let .other(value) = color {
                return Colors(main: NSColor(UInt32(bitPattern: value)))
            } else {
                return Colors(main: .random)
            }
        case .palette:
            if dark, let colors = self.profilePaletteDarkColors[color.rawValue] {
                return colors
            } else if let colors = self.profilePaletteColors[color.rawValue] {
                return colors
            } else {
                return self.getProfile(color, dark: dark, subject: .background)
            }
        case .stories:
            if dark, let colors = self.profileStoryDarkColors[color.rawValue] {
                return colors
            } else if let colors = self.profileStoryColors[color.rawValue] {
                return colors
            } else {
                return self.getProfile(color, dark: dark, subject: .background)
            }
        }
    }
    
    public static func with(availableReplyColors: EngineAvailableColorOptions, availableProfileColors: EngineAvailableColorOptions) -> PeerNameColors {
        var colors: [Int32: Colors] = [:]
        var darkColors: [Int32: Colors] = [:]
        var displayOrder: [Int32] = []
        var profileColors: [Int32: Colors] = [:]
        var profileDarkColors: [Int32: Colors] = [:]
        var profilePaletteColors: [Int32: Colors] = [:]
        var profilePaletteDarkColors: [Int32: Colors] = [:]
        var profileStoryColors: [Int32: Colors] = [:]
        var profileStoryDarkColors: [Int32: Colors] = [:]
        var profileDisplayOrder: [Int32] = []
        
        var nameColorsChannelMinRequiredBoostLevel: [Int32: Int32] = [:]
        var nameColorsGroupMinRequiredBoostLevel: [Int32: Int32] = [:]
        
        if !availableReplyColors.options.isEmpty {
            for option in availableReplyColors.options {
                if let requiredChannelMinBoostLevel = option.value.requiredChannelMinBoostLevel {
                    nameColorsChannelMinRequiredBoostLevel[option.key] = requiredChannelMinBoostLevel
                }
                if let requiredGroupMinBoostLevel = option.value.requiredGroupMinBoostLevel {
                    nameColorsGroupMinRequiredBoostLevel[option.key] = requiredGroupMinBoostLevel
                }
                
                if let parsedLight = PeerNameColors.Colors(colors: option.value.light.background) {
                    colors[option.key] = parsedLight
                }
                if let parsedDark = (option.value.dark?.background).flatMap(PeerNameColors.Colors.init(colors:)) {
                    darkColors[option.key] = parsedDark
                }
                
                for option in availableReplyColors.options {
                    if !displayOrder.contains(option.key) {
                        displayOrder.append(option.key)
                    }
                }
            }
        } else {
            let defaultValue = PeerNameColors.defaultValue
            colors = defaultValue.colors
            darkColors = defaultValue.darkColors
            displayOrder = defaultValue.displayOrder
        }
            
        if !availableProfileColors.options.isEmpty {
            for option in availableProfileColors.options {
                if let parsedLight = PeerNameColors.Colors(colors: option.value.light.background) {
                    profileColors[option.key] = parsedLight
                }
                if let parsedDark = (option.value.dark?.background).flatMap(PeerNameColors.Colors.init(colors:)) {
                    profileDarkColors[option.key] = parsedDark
                }
                if let parsedPaletteLight = PeerNameColors.Colors(colors: option.value.light.palette) {
                    profilePaletteColors[option.key] = parsedPaletteLight
                }
                if let parsedPaletteDark = (option.value.dark?.palette).flatMap(PeerNameColors.Colors.init(colors:)) {
                    profilePaletteDarkColors[option.key] = parsedPaletteDark
                }
                if let parsedStoryLight = (option.value.light.stories).flatMap(PeerNameColors.Colors.init(colors:)) {
                    profileStoryColors[option.key] = parsedStoryLight
                }
                if let parsedStoryDark = (option.value.dark?.stories).flatMap(PeerNameColors.Colors.init(colors:)) {
                    profileStoryDarkColors[option.key] = parsedStoryDark
                }
                for option in availableProfileColors.options {
                    if !profileDisplayOrder.contains(option.key) {
                        profileDisplayOrder.append(option.key)
                    }
                }
            }
        }
        
        return PeerNameColors(
            colors: colors,
            darkColors: darkColors,
            displayOrder: displayOrder,
            profileColors: profileColors,
            profileDarkColors: profileDarkColors,
            profilePaletteColors: profilePaletteColors,
            profilePaletteDarkColors: profilePaletteDarkColors,
            profileStoryColors: profileStoryColors,
            profileStoryDarkColors: profileStoryDarkColors,
            profileDisplayOrder: profileDisplayOrder,
            nameColorsChannelMinRequiredBoostLevel: nameColorsChannelMinRequiredBoostLevel,
            nameColorsGroupMinRequiredBoostLevel: nameColorsGroupMinRequiredBoostLevel
        )
    }
}
