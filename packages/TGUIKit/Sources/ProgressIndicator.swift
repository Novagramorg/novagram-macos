import Cocoa


public class ProgressIndicator : Control {
    
    public var alwaysAnimate: Bool = false {
        didSet {
            if alwaysAnimate != oldValue { updateWantsAnimation() }
        }
    }
    
    private var visualEffect: VisualEffect?
    public var blurBackground: NSColor? = nil {
        didSet {
            updateBackgroundBlur()
        }
    }
    
    private func updateBackgroundBlur() {
        updateVisualEffectBackground(for: self, visualEffect: &visualEffect, blurBackground: blurBackground)
        needsLayout = true
    }
    
    public var progressColor: NSColor? = nil {
        didSet {
            indicator.color = progressColor ?? presentation.colors.text
            indicator.setNeedsDisplay()
        }
    }
    public var innerInset: CGFloat = 0 {
        didSet {
            needsLayout = true
           // indicator.lineWidth = lineWidth
        }
    }
    private let indicator: SpinningProgressView = SpinningProgressView(frame: NSZeroRect)
    var isSpinning: Bool {
        return indicator.isAnimating
    }
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        indicator.frame = bounds
        self.addSubview(indicator)
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        let prev = self.frame
        super.setFrameSize(newSize)
        if prev != self.frame {
            updateWantsAnimation()
        }
    }
    
    
    public override func layout() {
        super.layout()
        indicator.setFrameSize(NSMakeSize(frame.width - innerInset, frame.height - innerInset))
        indicator.center()
        visualEffect?.frame = bounds
    }
    
    public override init() {
        super.init(frame: NSMakeRect(0, 0, 20, 20))
        indicator.frame = bounds
        self.addSubview(indicator)
    }

    public override func viewDidMoveToSuperview() {
        updateWantsAnimation()
    }
    
    public override func viewDidMoveToWindow() {
        updateWantsAnimation()
    }

    public override func viewDidHide() {
        updateWantsAnimation()
    }

    public override func viewDidUnhide() {
        updateWantsAnimation()
    }

    private func updateWantsAnimation() {
        if (window != nil && !isHiddenOrHasHiddenAncestor) || alwaysAnimate {
            indicator.startAnimation()
        } else {
            indicator.stopAnimation()
        }
    }
    

    override public func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)

    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

