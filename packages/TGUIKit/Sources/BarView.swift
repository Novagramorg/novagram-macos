import Cocoa

open class BarView: Control {
    
    
    
    public var clickHandler:()->Void = {}
    
    public var minWidth:CGFloat = 20
    public private(set) weak var controller: ViewController?
    
    
    override open func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
    }
    
    
    var isFitted: Bool {
        return true
    }
    
    @discardableResult
    open func fit(to maxWidth: CGFloat, transition: ContainedViewLayoutTransition = .immediate) -> CGFloat {
        return frame.width
    }

    open func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
    }
    
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.setNeedsDisplay()
    }
    
    public init(_ width:CGFloat = 20, controller: ViewController) {
        self.minWidth = width
        self.controller = controller
        super.init(frame: NSMakeRect(0, 0, minWidth, 50))
        self.layer?.masksToBounds = false
        animates = false
        overlayInitEvent()
    }
    
    open override var isHidden: Bool {
        didSet {
            if !isHidden {
             //   layer?.opacity = 1
            }
        }
    }
    
    override open func updateLocalizationAndTheme(theme: PresentationTheme) {
       // super.updateLocalizationAndTheme(theme: theme)
        guard let _ = self.controller else {
            return
        }
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    public override var style: ControlStyle {
        didSet {
            updateLocalizationAndTheme(theme: presentation)
        }
    }
    

    func overlayInitEvent() -> Void {
        set(handler: { [weak self] control in
            self?.clickHandler()
        }, for: .Click)
        updateLocalizationAndTheme(theme: presentation)
    }
    
    required public init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        self.layer?.masksToBounds = false
        overlayInitEvent()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}
