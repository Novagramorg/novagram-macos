import Cocoa
import TGUIKit
import Postbox
import TelegramCore

import SwiftSignalKit
import Localization
import TelegramUtils
import AlertsUI

public class ShareInlineResultNavigationAction: NavigationModalAction {

    public let payload:String
    public init(payload:String, botName:String) {
        self.payload = payload
        super.init(reason: strings().inlineModalActionTitle, desc: strings().inlineModalActionDesc(botName))
    }
    
    public override func isInvokable(for value:Any) -> Bool {
        if let value = value as? Peer, value.canSendMessage(false) {
            return true
        }
        return false
    }
    
    public override func alertError(for value:Any, with window:Window) -> Void {
        if let _ = value as? Peer {
            alert(for: window, info: strings().alertForwardError)
        }
    }
}
