import Cocoa

public func parabollicReactionAnimation(_ layer: CALayer, fromPoint: NSPoint, toPoint: NSPoint, window: Window, completion: ((Bool)->Void)? = nil, duration: Double = 0.2) {
    
    let view = FlippableView(frame: window.frame.size.bounds)
    view.isEventLess = true
    view.flip = false
    view.backgroundColor = .clear
    window.contentView?.addSubview(view)
    
    layer.removeFromSuperlayer()
    layer.frame = CGRect(origin: toPoint.offsetBy(dx: -layer.frame.width/2, dy: -layer.frame.height/2), size: layer.frame.size)
    
    view.layer?.addSublayer(layer)
    
    let transition = ContainedViewLayoutTransition.animated(duration: duration, curve: .linear)
    
    let keyFrames = generateParabollicMotionKeyframes(from: fromPoint, to: toPoint, elevation: fromPoint.y < toPoint.y ? 50 : -50)
    
    let animation = CABasicAnimation(keyPath: "transform.scale")
    animation.fromValue = 1
    animation.toValue = 2.0
    animation.duration = transition.duration / 2
    animation.timingFunction = CAMediaTimingFunction(name: .linear)
    animation.isRemovedOnCompletion = true
    animation.fillMode = .forwards
    animation.speed = 1
    animation.repeatCount = 1
    animation.autoreverses = true
    
    layer.add(animation, forKey: "transform.scale")
    
    transition.animatePositionWithKeyframes(layer: layer, keyframes: keyFrames, removeOnCompletion: true, completion: { [weak view] completed in
        CATransaction.begin()
        completion?(completed)

        CATransaction.commit()
        DispatchQueue.main.async {
            view?.removeFromSuperview()
        }
    })
}



private func generateParabollicMotionKeyframes(from sourcePoint: CGPoint, to targetPosition: CGPoint, elevation: CGFloat) -> [CGPoint] {
    let midPoint = CGPoint(x: (sourcePoint.x + targetPosition.x) / 2.0, y: sourcePoint.y - elevation)
    
    let x1 = sourcePoint.x
    let y1 = sourcePoint.y
    let x2 = midPoint.x
    let y2 = midPoint.y
    let x3 = targetPosition.x
    let y3 = targetPosition.y
    
    var keyframes: [CGPoint] = []
    if abs(y1 - y3) < 5.0 && abs(x1 - x3) < 5.0 {
        for i in 0 ..< 10 {
            let k = CGFloat(i) / CGFloat(10 - 1)
            let x = sourcePoint.x * (1.0 - k) + targetPosition.x * k
            let y = sourcePoint.y * (1.0 - k) + targetPosition.y * k
            keyframes.append(CGPoint(x: x, y: y))
        }
    } else {
        let a = (x3 * (y2 - y1) + x2 * (y1 - y3) + x1 * (y3 - y2)) / ((x1 - x2) * (x1 - x3) * (x2 - x3))
        let b = (x1 * x1 * (y2 - y3) + x3 * x3 * (y1 - y2) + x2 * x2 * (y3 - y1)) / ((x1 - x2) * (x1 - x3) * (x2 - x3))
        let c = (x2 * x2 * (x3 * y1 - x1 * y3) + x2 * (x1 * x1 * y3 - x3 * x3 * y1) + x1 * x3 * (x3 - x1) * y2) / ((x1 - x2) * (x1 - x3) * (x2 - x3))
        
        for i in 0 ..< 10 {
            let k = CGFloat(i) / CGFloat(10 - 1)
            let x = sourcePoint.x * (1.0 - k) + targetPosition.x * k
            let y = a * x * x + b * x + c
            keyframes.append(CGPoint(x: x, y: y))
        }
    }
    
    return keyframes
}
