import Cocoa
import Foundation
import TGUIKit
import TelegramMedia
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import CurrencyFormat
import SceneEffects
import InAppPurchaseManager
import InlineStickers
import ObjcUtils


public final class PremiumLockModalController : ModalViewController {
    
    
    public override var closable: Bool {
        return false
    }
    
    public override var containerBackground: NSColor {
        return .clear
    }
    
    public override var modalTheme:Theme {
        return Theme(text: .clear, grayText: .clear, background: .clear, border: .clear, accent: .clear, grayForeground: .clear, activeBackground: .clear, activeBorder: .clear, listBackground: .clear)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        readyOnce()
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        return .invoked
    }
}
