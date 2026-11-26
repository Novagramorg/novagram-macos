import Cocoa
import TGUIKit

@inline(never) public func kitCandidate(_ lhs: NSColor, _ rhs: NSColor) -> Bool { lhs == rhs }
public func kitOptional(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool { lhs == rhs }
public func kitPacked(_ color: NSColor) -> UInt32 { color.argb }

public struct StylePair {
    private let lhs: ControlStyle
    private let rhs: ControlStyle
    public init(_ foreground: NSColor, _ background: NSColor, otherForeground: NSColor? = nil, otherBackground: NSColor? = nil, differentFont: Bool = false) {
        lhs = ControlStyle(font: .systemFont(ofSize: 13), foregroundColor: foreground, backgroundColor: background)
        rhs = ControlStyle(font: .systemFont(ofSize: differentFont ? 15 : 13), foregroundColor: otherForeground ?? foreground, backgroundColor: otherBackground ?? background)
    }
    @inline(never) public func candidate() -> Bool { lhs == rhs }
    @inline(never) public func reference() -> Bool {
        return lhs.font == rhs.font && kitReference(lhs.foregroundColor, rhs.foregroundColor) && kitReference(rhs.backgroundColor, lhs.backgroundColor)
    }
}
