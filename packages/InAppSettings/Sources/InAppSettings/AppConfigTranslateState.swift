import Foundation

public enum AppConfigTranslateState : String {
    case enabled
    case disabled
    case system
    case alternative
    
    public var canTranslate: Bool {
        switch self {
        case .enabled, .alternative:
            return true
        default:
            return false
        }
    }
}
