import Cocoa
import ColorPalette
import TelegramTheme
import TGUIKit
import GeneralRows
import InputDataUI

var walletClassicAccent: NSColor {
    return walletDefaultAccent(for: theme.colors)
}

func walletGramColor(for palette: ColorPalette) -> NSColor {
    return NSColor(rgb: palette.isDark ? 0x30A1F5 : 0x0088ff)
}

func walletDefaultAccent(for palette: ColorPalette) -> NSColor {
    if palette.parent == .nightAccent {
        return nightAccentPalette.accent
    }
    return palette.isDark ? darkPalette.accent : dayClassicPalette.accent
}

var walletRowTheme: GeneralRowItem.Theme {
    return GeneralRowItem.Theme(accentColor: walletClassicAccent, switchAppearance: SwitchViewAppearance(backgroundColor: theme.colors.background, stateOnColor: walletClassicAccent, stateOffColor: theme.colors.grayForeground, disabledColor: theme.colors.grayTransparent, borderColor: theme.colors.border))
}

var walletModalTheme: ModalViewController.Theme {
    return ModalViewController.Theme(accent: walletClassicAccent)
}

func walletAlertPalette(_ palette: ColorPalette) -> ColorPalette {
    return palette.withAccentColor(PaletteAccentColor(walletDefaultAccent(for: palette)), disableTint: true)
}

public var walletAlertPresentation: TelegramPresentationTheme {
    return theme.withUpdatedColors(walletAlertPalette(theme.colors))
}

final class WalletModalController: InputDataModalController {
    override var modalTheme: ModalViewController.Theme {
        return .init(text: theme.colors.text, grayText: theme.colors.grayText, background: .clear, border: .clear, accent: walletClassicAccent, grayForeground: theme.colors.grayBackground, activeBackground: theme.colors.background, activeBorder: theme.colors.border)
    }
}
