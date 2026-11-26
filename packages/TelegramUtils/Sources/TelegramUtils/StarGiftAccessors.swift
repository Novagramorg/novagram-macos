import Cocoa
import TelegramCore
import ColorPalette

public extension StarGift.Gift {
    var isAuction: Bool {
        return availability != nil && self.flags.contains(.isAuction)
    }
}

public extension StarGift {
    var generic: StarGift.Gift? {
        switch self {
        case let .generic(gift):
            return gift
        case .unique:
            return nil
        }
    }
    
    
    var unique: StarGift.UniqueGift? {
        switch self {
        case .generic:
            return nil
        case let .unique(unique):
            return unique
        }
    }
    
    var backdropColor: [NSColor]? {
        if let unique {
            for attribute in unique.attributes {
                switch attribute {
                case .backdrop(_, _, let innerColor, let outerColor, _, _, _):
                    return [NSColor(UInt32(innerColor)), NSColor(UInt32(outerColor))]
                default:
                    break
                }
            }
        }
        return nil
    }
}
