#if canImport(AppKit)
import AppKit

/// AppKit replacement for UIRectCorner (UIKit-only).
@available(macOS 12, *)
struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

@available(macOS 12, *)
extension NSBezierPath {
    /// Replacement for UIBezierPath(roundedRect:byRoundingCorners:cornerRadii:). Builds a path in the
    /// flipped (top-left/y-down) space the canvas uses, rounding only the requested corners.
    convenience init(roundedRect rect: NSRect, byRoundingCorners corners: RectCorner, cornerRadius radius: CGFloat) {
        self.init()
        let r = min(radius, min(rect.width, rect.height) / 2)
        let tl = corners.contains(.topLeft) ? r : 0
        let tr = corners.contains(.topRight) ? r : 0
        let bl = corners.contains(.bottomLeft) ? r : 0
        let br = corners.contains(.bottomRight) ? r : 0
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        // Top edge (y = minY in flipped space), going clockwise.
        move(to: NSPoint(x: minX + tl, y: minY))
        line(to: NSPoint(x: maxX - tr, y: minY))
        if tr > 0 { appendArc(from: NSPoint(x: maxX, y: minY), to: NSPoint(x: maxX, y: minY + tr), radius: tr) }
        line(to: NSPoint(x: maxX, y: maxY - br))
        if br > 0 { appendArc(from: NSPoint(x: maxX, y: maxY), to: NSPoint(x: maxX - br, y: maxY), radius: br) }
        line(to: NSPoint(x: minX + bl, y: maxY))
        if bl > 0 { appendArc(from: NSPoint(x: minX, y: maxY), to: NSPoint(x: minX, y: maxY - bl), radius: bl) }
        line(to: NSPoint(x: minX, y: minY + tl))
        if tl > 0 { appendArc(from: NSPoint(x: minX, y: minY), to: NSPoint(x: minX + tl, y: minY), radius: tl) }
        close()
    }
}
#endif
