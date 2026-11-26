import Cocoa
import TGUIKit

final class ReferenceChatRightTextLayer: SimpleLayer {
    private final class DrawLayer: SimpleLayer {
        var textLayout: TextViewLayout?
        var textSize: NSSize = .zero

        override func draw(in ctx: CGContext) {
            guard let textLayout = textLayout else {
                return
            }
            let renderer = ReferenceChatRightTextLayer.renderer
            renderer.update(textLayout)
            renderer.setFrameSize(textSize)
            renderer.draw(renderer.drawingLayer, in: ctx)
        }
    }

    static let renderer: TextView = {
        let view = TextView()
        view.disableBackgroundDrawing = true
        view.userInteractionEnabled = false
        view.isSelectable = false
        return view
    }()

    private let drawLayer = DrawLayer()

    var textLayout: TextViewLayout? {
        return drawLayer.textLayout
    }

    override init() {
        super.init()
        anchorPoint = .zero
        zPosition = 1
        masksToBounds = false
        addSublayer(drawLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ layout: TextViewLayout) {
        drawLayer.textLayout = layout
        bounds = CGRect(origin: .zero, size: layout.layoutSize)
        updateDrawLayer()
        drawLayer.setNeedsDisplay()
    }

    func updateDrawLayer() {
        if drawLayer.textSize != bounds.size {
            drawLayer.textSize = bounds.size
            drawLayer.setNeedsDisplay()
        }
        drawLayer.frame = bounds
        drawLayer.bounds = bounds.insetBy(dx: -2, dy: -3)
    }

    func updateScale(_ scale: CGFloat) {
        drawLayer.contentsScale = scale
        drawLayer.setNeedsDisplay()
    }
}
