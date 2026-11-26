import Cocoa

open class ColorSwatchView : View {
    
    private let fillView: SimpleLayer = SimpleLayer()
    private let ringView: SimpleLayer = SimpleLayer()
    public let control = Control()
    
    private var wasSelected: Bool = false
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.addSublayer(ringView)
        self.layer?.addSublayer(fillView)
        addSubview(control)
        let bounds = focus(CGSize(width: 35, height: 35))
        
        fillView.frame = bounds
        ringView.frame = bounds
        control.frame = bounds
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(fill: CGImage?, ring: CGImage?, selected: Bool, animated: Bool) {
        self.fillView.contents = fill
        self.ringView.contents = ring
        
        if wasSelected != selected {
            if selected {
                self.fillView.transform = CATransform3DScale(CATransform3DIdentity, 0.8, 0.8, 1.0)
                if animated {
                    self.fillView.animateScale(from: 1, to: 0.8, duration: animated ? 0.2 : 0, removeOnCompletion: true)
                }
            } else {
                self.fillView.transform = CATransform3DScale(CATransform3DIdentity, 1.0, 1.0, 1.0)
                if animated {
                    self.fillView.animateScale(from: 0.8, to: 1, duration: animated ? 0.2 : 0, removeOnCompletion: true)
                }
            }
        }
        
        self.wasSelected = selected
    }
}
