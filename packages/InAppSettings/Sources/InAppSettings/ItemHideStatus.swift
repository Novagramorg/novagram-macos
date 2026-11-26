import Foundation

public enum ItemHideStatus : Equatable {
    case normal
    case collapsed
    case hidden(Bool)
    
    public var rawValue: Int {
        switch self {
        case .normal:
            return 0
        case .collapsed:
            return 1
        case .hidden:
            return 2
        }
    }
    public var isHidden: Bool {
        switch self {
        case .hidden:
            return true
        default:
            return false
        }
    }
    
    public init?(rawValue: Int) {
        switch rawValue {
        case 0:
            self = .normal
        case 1:
            self = .collapsed
        case 2:
            self = .hidden(true)
        default:
            return nil
        }
    }
}
