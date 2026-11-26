import Cocoa
import Colors

@inline(never) public func coreReference(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        return lhs.argb == rhs.argb
    }
