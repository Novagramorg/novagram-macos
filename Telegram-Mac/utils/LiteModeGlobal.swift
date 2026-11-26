import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import ColorPalette
import ThemeSettings

func isLite(_ key: LiteModeKey = .any) -> Bool {
    return appDelegate?.sharedApplicationContextValue?.sharedContext.isLite(key) ?? false
}
