import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import Localization
import TelegramUtils
import AlertsUI
public class FWDNavigationAction: NavigationModalAction {
    
    public let messages:[Message]
    
    public var ids:[MessageId] {
        return messages.map{$0.id}
    }
    public init(messages:[Message], displayName:String) {
        self.messages = messages
        
        super.init(reason: strings().forwardModalActionTitleOther(messages.count), desc: strings().forwardModalActionDescriptionOther(messages.count, displayName))
    }
    
    public override func isInvokable(for value:Any) -> Bool {
        if let value = value as? Peer {
            return value.canSendMessage(false)
        }
        return true
    }
    
    public override func alertError(for value:Any, with window:Window) -> Void {
        if let _ = value as? Peer {
            alert(for: window, info: strings().alertForwardError)
        }
    }
    
}
