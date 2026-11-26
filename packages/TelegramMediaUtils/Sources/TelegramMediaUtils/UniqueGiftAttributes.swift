import Cocoa
import TelegramCore
import Postbox
import ColorPalette

public extension StarGift.UniqueGift {
    var file: TelegramMediaFile? {
        for attribute in self.attributes {
            inner: switch attribute {
            case .model(_, let file, _, _):
                return file
            default:
                break inner
            }
        }
        return nil
    }
    var pattern: TelegramMediaFile? {
        for attribute in self.attributes {
            inner: switch attribute {
            case let .pattern(_, file, _):
                return file
            default:
                break
            }
        }
        return nil
    }
    var patternColor: NSColor? {
        for attribute in self.attributes {
            inner: switch attribute {
            case let .backdrop(_, _, _, _, patternColor, _, _):
                return NSColor(UInt32(patternColor))
            default:
                break inner
            }
        }
        return nil
    }
    var backdrop: [NSColor]? {
        for attribute in self.attributes {
            inner: switch attribute {
            case let .backdrop(_, _, innerColor, outerColor, _, _, _):
                return [NSColor(UInt32(innerColor)), NSColor(UInt32(outerColor))]
            default:
                break inner
            }
        }
        return nil
    }
}
