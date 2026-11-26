import Cocoa
import Colors

@inline(never) public func coreCandidate(_ lhs: NSColor, _ rhs: NSColor) -> Bool { lhs == rhs }
public func coreOptional(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool { lhs == rhs }
public func corePacked(_ color: NSColor) -> UInt32 { color.argb }
