import Cocoa
import TGUIKit
#if SHARE
import TelegramContextShare
#else
import TelegramContext
#endif

public func bestWindow(_ accountContext: any AccountContextProtocol, _ controller: ViewController?) -> Window {
    return controller?.window ?? accountContext.window
}
