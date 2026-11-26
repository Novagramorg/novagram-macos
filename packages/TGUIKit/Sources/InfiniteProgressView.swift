import Foundation
import AppKit

public final class InfiniteProgressView: View {
    var progressAnimationCompleted: (() -> Void)?

    private static let rotationAnimationKey = "progressRotation"
    private static let indefiniteAnimationKey = "progressIndefinite"
    private static let determinateAnimationKey = "progressDeterminate"

    private let pLayer = CAShapeLayer()
    private var isAnimatingDeterminate: Bool = false
    
    public var color: NSColor {
        didSet {
            pLayer.strokeColor = color.cgColor
        }
    }
    
    public var progress: CGFloat? {
        didSet {
            self.updateProgressAnimation()
        }
    }
    
    public var isAnimatingProgress: Bool {
        return self.isAnimatingDeterminate
    }
    
    let lineWidth: CGFloat?
    let insets: CGFloat
    
    public init(color: NSColor, lineWidth: CGFloat?, insets: CGFloat = 0) {
        self.color = color
        self.lineWidth = lineWidth
        self.insets = insets

        super.init()
        pLayer.contentsScale = backingScaleFactor
        pLayer.fillColor = nil
        pLayer.strokeColor = color.cgColor
        pLayer.lineCap = .round
        pLayer.strokeStart = 0
        pLayer.strokeEnd = 0
        layer?.addSublayer(pLayer)
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        pLayer.contentsScale = backingScaleFactor
    }
    
    public override func layout() {
        super.layout()
        pLayer.frame = bounds
        self.updatePath()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private func updatePath() {
        let size = bounds.size
        let factor = size.width / 50.0
        let lineWidth: CGFloat = self.lineWidth ?? max(1.6, 2.25 * factor)
        let pathDiameter: CGFloat
        if self.lineWidth != nil {
            pathDiameter = size.width - lineWidth - self.insets
        } else {
            pathDiameter = size.width - lineWidth - 2.5 * 2.0 - self.insets
        }
        let startAngle = -CGFloat.pi / 2.0
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: size.width / 2.0, y: size.height / 2.0), radius: max(0, pathDiameter / 2.0), startAngle: startAngle, endAngle: startAngle + 2.0 * CGFloat.pi, clockwise: false)
        pLayer.lineWidth = lineWidth
        pLayer.path = path
    }

    private func updateProgressAnimation() {
        guard window != nil else {
            return
        }
        if let progress = self.progress {
            pLayer.removeAnimation(forKey: Self.indefiniteAnimationKey)
            let current = (pLayer.presentation() ?? pLayer).strokeEnd
            var duration = 0.2
            let delta = max(0.0, progress - current)
            if delta > 0.25 {
                duration += Double(min(0.45, 0.45 * ((delta - 0.25) * 5)))
            }
            pLayer.strokeStart = 0
            pLayer.strokeEnd = progress
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = current
            animation.toValue = progress
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.isAnimatingDeterminate = true
            CATransaction.begin()
            CATransaction.setCompletionBlock({ [weak self] in
                guard let self, self.progress == progress else {
                    return
                }
                self.isAnimatingDeterminate = false
                self.progressAnimationCompleted?()
            })
            pLayer.add(animation, forKey: Self.determinateAnimationKey)
            CATransaction.commit()
        } else {
            pLayer.removeAnimation(forKey: Self.determinateAnimationKey)
            self.isAnimatingDeterminate = false
            guard pLayer.animation(forKey: Self.indefiniteAnimationKey) == nil else {
                return
            }
            pLayer.strokeStart = 0
            pLayer.strokeEnd = 0
            let grow = CABasicAnimation(keyPath: "strokeEnd")
            grow.fromValue = 0
            grow.toValue = 1
            grow.beginTime = 0
            grow.duration = 1.25
            grow.fillMode = .forwards
            let shrink = CABasicAnimation(keyPath: "strokeStart")
            shrink.fromValue = 0
            shrink.toValue = 1
            shrink.beginTime = 1.25
            shrink.duration = 1.25
            shrink.fillMode = .backwards
            let group = CAAnimationGroup()
            group.animations = [grow, shrink]
            group.duration = 2.5
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pLayer.add(group, forKey: Self.indefiniteAnimationKey)
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil {
            let basicAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
            basicAnimation.duration = 1.5
            var fromValue = Float.pi + 0.58
            if let presentation = self.pLayer.presentation(), let value = (presentation.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.floatValue {
                fromValue = value
            }
            basicAnimation.fromValue = NSNumber(value: fromValue)
            basicAnimation.toValue = NSNumber(value: fromValue + Float.pi * 2.0)
            basicAnimation.repeatCount = Float.infinity
            basicAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
            basicAnimation.beginTime = 0.0
            
            self.pLayer.add(basicAnimation, forKey: Self.rotationAnimationKey)
            self.updateProgressAnimation()
        } else {
            self.pLayer.removeAllAnimations()
        }
    }
}
