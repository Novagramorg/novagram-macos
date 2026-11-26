import Cocoa
import TGUIKit

public func getStarAmountColorMapping(value: Int64) -> NSColor {
    if value >= 10000 {
        return NSColor(rgb: 0x7C8695)
    }
    if value >= 2000 {
        return NSColor(rgb: 0xE6514E)
    }
    if value >= 500 {
        return NSColor(rgb: 0xEE7E20)
    }
    if value >= 250 {
        return NSColor(rgb: 0xE4A20A)
    }
    if value >= 100 {
        return NSColor(rgb: 0x5AB03D)
    }
    if value >= 50 {
        return NSColor(rgb: 0x3E9CDF)
    }
    return NSColor(rgb: 0x985FDC)
}
