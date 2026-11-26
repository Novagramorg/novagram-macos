import Foundation
import TGUIKit
import Localization
import TelegramTheme
import TelegramContext
import FilePanels
import PhoneNumberUtils
import LocalAnimations
import TelegramUtils


public final class Auth_NextView: TextButton {
    
    private var locked: Bool = false
    private var string: String = strings().loginNext
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.scaleOnClick = true
        self.set(font: .medium(.title), for: .Normal)
        self.style = ControlStyle(font: .medium(15.0), foregroundColor: theme.colors.underSelectedColor, backgroundColor: locked ? theme.colors.grayText : theme.colors.accent)
        self.set(text: string, for: .Normal)
        self.sizeToFit(NSMakeSize(30, 0), NSMakeSize(0, Auth_Insets.nextHeight), thatFit: true)
        self.layer?.cornerRadius = self.frame.height / 2
    }
    
    public func updateLocked(_ locked: Bool, string: String = strings().loginNext) {
        self.locked = locked
        self.string = string
        userInteractionEnabled = !locked
        updateLocalizationAndTheme(theme: theme)
       // self.isEnabled = !locked
    }
}
