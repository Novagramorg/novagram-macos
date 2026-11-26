import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ProxyUI

func installProxyUIHooks() {
    installProxyHooks(.init(currentContext: {
        return appDelegate?.currentContext
    }))
}
