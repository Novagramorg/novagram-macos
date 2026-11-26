import Cocoa
import TGUIKit

open class CornerView : View {

    public var positionFlags: LayoutPositionFlags? {
        didSet {
            needsLayout = true
        }
    }

    public var corners: ImageCorners? {
        didSet {
            needsLayout = true
        }
    }
    
    public var didChangeSuperview: (()->Void)? = nil
    
    open override func viewDidMoveToSuperview() {
        didChangeSuperview?()
    }
    
    open override var backgroundColor: NSColor {
        didSet {
            layer?.backgroundColor = .clear
        }
    }
    
    open override func draw(_ layer: CALayer, in ctx: CGContext) {
        if let corners = corners {
            ctx.addPath(CGPath.bubbleCorners(size: frame.size, corners: corners))
            ctx.clip()
        } else if let positionFlags = positionFlags {
            ctx.roundPositioned(frame.size, positionFlags.isEmpty ? 0 : .cornerRadius, positionFlags: positionFlags)
        }
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fill(bounds)
    }
    
}
