import Cocoa
import AppKit


open class Button: Control {
    
    
    public var autohighlight:Bool = false
    public var highlightHovered:Bool = false
    public var _thatFit: Bool = false
    
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
    
    open override func layout() {
        super.layout()
        visualEffect?.frame = bounds
    }


    private var stateBackground:[ControlState:NSColor] = [:]
    
    open override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
    }
    
    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        prepare()
        
    }
    
    open override func cursorUpdate(with event: NSEvent) {
        //super.cursorUpdate(with: event)
        NSCursor.arrow.set()
    }
    
//    public func set(backgroundColor:NSColor, for state:ControlState) -> Void {
//        stateBackground[state] = backgroundColor
//        apply(state: self.controlState)
//    }
    
    public override init() {
        super.init()
        prepare()
    }
    
    func prepare() -> Void {
        layer?.removeAllAnimations()
    }
    
    override public func apply(state:ControlState) -> Void {
        let state:ControlState = self.isSelected ? .Highlight : state
        super.apply(state: state)
        
//        if let backgroundColor = stateBackground[state] {
//            self.layer?.backgroundColor = backgroundColor.cgColor
//            if animates {
//                self.layer?.animateBackground()
//            }
//        } else {
//            self.layer?.backgroundColor = self.backgroundColor.cgColor
//        }
    }
    
    override func apply(style:ControlStyle) -> Void {
        super.apply(style:style)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @discardableResult public func sizeToFit(_ addition: NSSize = NSZeroSize, _ maxSize:NSSize = NSZeroSize, thatFit:Bool = false, transition: ContainedViewLayoutTransition = .immediate) -> Bool {
        self._thatFit = thatFit
        return true
    }
    

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    public func updateLayout() -> Void {

    }

    open func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
    }
    
}
