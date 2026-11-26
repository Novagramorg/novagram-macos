import Cocoa

import SwiftSignalKit
import TelegramCore
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif


public final class PeerPresenceStatusManager {
    private let update: () -> Void
    private var timer: SwiftSignalKit.Timer?
    
    public init(update: @escaping () -> Void) {
        self.update = update
    }
    
    deinit {
        self.timer?.invalidate()
    }
    
    public func reset(presence: TelegramUserPresence, timeDifference: Int32) {
        timer?.invalidate()
        timer = nil
        
        let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
        let timeout = userPresenceStringRefreshTimeout(presence, timeDifference: timeDifference, relativeTo: Int32(timestamp))
        if timeout.isFinite {
            self.timer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
                if let strongSelf = self {
                    strongSelf.update()
                }
                }, queue: Queue.mainQueue())
            self.timer?.start()
        }
    }
}
