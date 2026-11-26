import Cocoa
import TGUIKit

open class SendingClockProgress: View {
    
    private var isAnimating:Bool = false

    private let clockFrame:CALayer
    private let clockHour:CALayer
    private let clockMin:CALayer
    
    private var hourSize: NSSize = .zero
    private var minSize: NSSize = .zero
    
    required public init(frame frameRect: NSRect) {
        
        clockFrame = CALayer()
        clockHour = CALayer()
        clockMin = CALayer()
        
        super.init(frame: frameRect)
        self.backgroundColor = .clear

        self.layer?.addSublayer(clockFrame)
        self.layer?.addSublayer(clockHour)
        self.layer?.addSublayer(clockMin)
        
    }
    
    open override func layout() {
        super.layout()
        
        clockMin.frame = focus(minSize)
        clockHour.frame = focus(hourSize)
    }
    
    
    public func set(frame: CGImage, hour: CGImage, minute: CGImage) {
        clockFrame.contents = frame
        clockFrame.frame = frame.backingBounds
        clockHour.contents = hour
        clockMin.contents = minute
        self.hourSize = hour.backingSize
        self.minSize = minute.backingSize
        needsLayout = true
        viewDidMoveToWindow()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    public func startAnimating() -> Void {
        if isAnimating {
            return
        }
        
        clockHour.removeAllAnimations()
        clockMin.removeAllAnimations()
        isAnimating = true
        
        animateHour()
        animateMin()
    }
    
    private func animateHour() -> Void {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        animation.duration = 6
        animation.repeatCount = .infinity
        animation.fromValue = 0
        animation.toValue = (Double.pi * 2.0)
        animation.beginTime = 1.0
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        clockHour.add(animation, forKey: "clockFrameAnimation")
    }
    

    private func animateMin() -> Void {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        animation.duration = 1
        animation.repeatCount = .infinity
        animation.fromValue = 0
        animation.toValue = (Double.pi * 2.0)
        animation.beginTime = 1.0
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        clockMin.add(animation, forKey: "clockFrameAnimation")
    }
    
    public func stopAnimating() -> Void {
        if !isAnimating {
            return
        }
        
        isAnimating = false
        clockHour.removeAllAnimations()
        clockMin.removeAllAnimations()
    }
    
    
    open override func viewDidMoveToSuperview() {
        if window != nil && superview != nil {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
    open override func viewDidMoveToWindow() {
        if window != nil && superview != nil {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
    
}
