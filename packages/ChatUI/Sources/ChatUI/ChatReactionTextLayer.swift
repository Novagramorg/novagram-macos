import Cocoa
import TGUIKit

final class ChatReactionTextLayer: SimpleLayer {
    private final class TextAccessibilityElement: NSAccessibilityElement {
        private weak var owner: ChatReactionTextLayer?

        init(owner: ChatReactionTextLayer) {
            self.owner = owner
            super.init()
        }

        override func isAccessibilityElement() -> Bool {
            guard TGUIKitAccessibility.isEnabled, let owner, let host = owner.host else { return false }
            return !host.isHiddenOrHasHiddenAncestor && !owner.isHidden && owner.opacity > 0 && (owner.textLayout?.attributedString.length ?? 0) > 0
        }

        override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
        override func accessibilityLabel() -> String? { nil }
        override func accessibilityValue() -> Any? { owner?.textLayout?.attributedString.string }
        override func accessibilityParent() -> Any? {
            guard let host = owner?.host else { return nil }
            return NSAccessibility.unignoredAncestor(of: host)
        }

        override func accessibilityFrame() -> NSRect {
            guard let owner, let host = owner.host, let layer = host.layer, let window = host.window else { return .zero }
            let rect = layer.convert(owner.bounds, from: owner)
            return window.convertToScreen(host.convert(rect, to: nil))
        }
    }

    private let drawingLayer = TextViewLayer()
    private weak var host: NSView?
    private var textAccessibilityElement: TextAccessibilityElement?

    var textLayout: TextViewLayout? { drawingLayer.textLayout }

    override init() {
        super.init()
        anchorPoint = .zero
        masksToBounds = false
        addSublayer(drawingLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ layout: TextViewLayout, in host: NSView, parent: CALayer? = nil) {
        self.host = host
        let target = parent ?? host.layer
        if superlayer !== target { target?.addSublayer(self) }
        drawingLayer.update(layout)
        bounds.size = drawingLayer.textSize
        updateScale(host.backingScaleFactor)
        updateDrawingGeometry()
    }

    func updateFrame(_ frame: CGRect, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(layer: self, frame: frame)
        updateDrawingGeometry()
    }

    private func updateDrawingGeometry() {
        drawingLayer.textSize = bounds.size
        drawingLayer.bounds = bounds.insetBy(dx: -2, dy: -3)
        drawingLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func updateScale(_ scale: CGFloat) {
        if drawingLayer.contentsScale != scale {
            drawingLayer.contentsScale = scale
            drawingLayer.setNeedsDisplay()
        }
    }

    func accessibleChild() -> NSAccessibilityElement? {
        guard TGUIKitAccessibility.isEnabled, host != nil, (textLayout?.attributedString.length ?? 0) > 0 else { return nil }
        let element = textAccessibilityElement ?? TextAccessibilityElement(owner: self)
        textAccessibilityElement = element
        return element.isAccessibilityElement() ? element : nil
    }

    func accessibilityHit(at point: NSPoint) -> NSAccessibilityElement? {
        guard let element = accessibleChild(), element.accessibilityFrame().contains(point) else { return nil }
        return element
    }

    func remove(animated: Bool) {
        host = nil
        performSublayerRemoval(self, animated: animated)
    }
}

final class ChatReactionTagBackgroundLayer: SimpleLayer {
    var image: NSImage? {
        didSet {
            if image !== oldValue { setNeedsDisplay() }
        }
    }
    var capInsets = NSEdgeInsets() {
        didSet {
            if !NSEdgeInsetsEqual(capInsets, oldValue) { setNeedsDisplay() }
        }
    }

    override init() {
        super.init()
        anchorPoint = .zero
        edgeAntialiasingMask = []
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let layer = layer as? ChatReactionTagBackgroundLayer {
            image = layer.image
            capInsets = layer.capInsets
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateScale(_ scale: CGFloat) {
        if contentsScale != scale {
            contentsScale = scale
            setNeedsDisplay()
        }
    }

    override func draw(in ctx: CGContext) {
        guard let image else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.drawInRect(rect: bounds, withCapInsets: capInsets)
        NSGraphicsContext.restoreGraphicsState()
    }
}
