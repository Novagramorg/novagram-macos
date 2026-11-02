import Cocoa
import TelegramCore
import ColorPalette
import TGUIKit
import NovagramCore

// The Novagram brand accent takes the place of Telegram's default blue in the accent picker of a built-in theme.
// Cloud themes and themes without a picker are left as they are.
func novagramAccentList(_ list: [AppearanceAccentColor], palette: ColorPalette, cloudTheme: TelegramTheme?) -> [AppearanceAccentColor] {
    guard cloudTheme == nil, !palette.accentList.isEmpty else { return list }
    guard let value = NovagramBrandColors.themeAccent(for: palette.parent.rawValue) else { return list }
    let ours = PaletteAccentColor(value.accent, value.messages)
    let telegramDefault = palette.parent.palette.accentList.first?.accent.argb
    var result = list
    result.removeAll(where: { $0.cloudTheme == nil && $0.accent.accent.argb == telegramDefault && telegramDefault != ours.accent.argb })
    if !result.contains(where: { $0.cloudTheme == nil && $0.accent.accent.argb == ours.accent.argb }) {
        result.insert(AppearanceAccentColor(accent: ours, cloudTheme: nil), at: 0)
    }
    return result
}
