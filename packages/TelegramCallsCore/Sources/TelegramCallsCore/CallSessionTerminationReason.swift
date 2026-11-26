import Foundation
import TelegramCore
import AVFoundation
import TelegramMediaUtils
import SystemPermissions
import ProxyUtils

extension CallSessionTerminationReason {
    public var recall: Bool {
        let recall:Bool
        switch self {
        case .ended(let reason):
            switch reason {
            case .busy:
                recall = true
            default:
                recall = false
            }
        case .error(let reason):
            switch reason {
            case .disconnected:
                recall = true
            default:
                recall = false
            }
        }
        return recall
    }
}
