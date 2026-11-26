import Foundation
import Postbox
import TelegramCore
import TgVoipWebrtc
import SwiftSignalKit
import TelegramCallsCore

public enum RequestOrJoinGroupCallResult {
    case success(GroupCallContext)
    case fail
    case samePeer(GroupCallContext)
}
