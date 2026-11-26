import Cocoa
import TGUIKit

open class VideoDurationView : View {
    private var textNode:(TextNodeLayout, TextNode)
    public init(_ textNode:(TextNodeLayout, TextNode)) {
        self.textNode = textNode
        super.init()
        self.backgroundColor = .clear
    }
    
    public func updateNode(_ textNode:(TextNodeLayout, TextNode)) {
        self.textNode = textNode
        needsDisplay = true
    }
    
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    public func sizeToFit() {
        setFrameSize(textNode.0.size.width + 10, textNode.0.size.height + 6)
        needsDisplay = true
    }
    
    open override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        ctx.setFillColor(NSColor(0x000000, 0.8).cgColor)
        ctx.round(frame.size, 4)
        ctx.fill(bounds)
        
        let f = focus(textNode.0.size)
        textNode.1.draw(f, in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}
