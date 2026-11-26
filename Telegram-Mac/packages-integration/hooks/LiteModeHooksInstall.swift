import Cocoa
import TGUIKit
import TelegramTheme
import SettingsUI

func installLiteModeUIHooks() {
    LiteModeHooks.install(LiteModeHooks(
        updateTheme: { theme, animated in
        telegramUpdateTheme(theme, animated: animated) }
    ))
}
