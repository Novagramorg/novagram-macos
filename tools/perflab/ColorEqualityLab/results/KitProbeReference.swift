import Cocoa
import TGUIKit

@inline(never) public func kitReference(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        return lhs.argb == rhs.argb
    }
