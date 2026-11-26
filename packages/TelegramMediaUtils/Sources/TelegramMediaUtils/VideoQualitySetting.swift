import Foundation
import TelegramMedia
import InAppSettings

private let kVideoQuality = "kVideoQuality"


extension UniversalVideoContentVideoQuality {
    public typealias RawValue = Int
    
    public init?(rawValue: Int) {
        switch rawValue {
        case -1: // Use -1 to represent auto
            self = .auto
        case let quality where quality >= 0:
            self = .quality(quality)
        default:
            return nil
        }
    }
    
    public var rawValue: Int {
        switch self {
        case .auto:
            return -1 // Use -1 to represent auto
        case .quality(let value):
            return value
        }
    }
}

extension FastSettings {
    public static var videoQuality: UniversalVideoContentVideoQuality {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: kVideoQuality)
            return UniversalVideoContentVideoQuality(rawValue: rawValue) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: kVideoQuality)
            UserDefaults.standard.synchronize()
        }
    }
}
