import Cocoa
import TelegramMedia

public enum LocalTelegramCurrency : String {
    case xtr = "XTR"
    case ton = "TON"
    
    public var logo: LocalAnimatedSticker {
        switch self {
        case .xtr:
            return .star_currency_new
        case .ton:
            return .ton_logo
        }
    }
    
    public func colored(_ color: NSColor) -> [LottieColor] {
        switch self {
        case .xtr:
            return []
        case .ton:
            return [.init(keyPath: "", color: color)]
        }
    }
}
