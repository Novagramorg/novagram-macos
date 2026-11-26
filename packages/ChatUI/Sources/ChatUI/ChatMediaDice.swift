import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit

public class ChatMediaDice: ChatMediaItem {
    public override var isForceRightLine: Bool {
        return true
    }
   
    public override var isBubbleFullFilled: Bool {
        return true
    }
    
}
