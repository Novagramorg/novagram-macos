import Cocoa

public struct TableRowResizeAnchor: Equatable {
    public let from: CGFloat
    public let to: CGFloat

    public init(from: CGFloat, to: CGFloat) {
        self.from = from
        self.to = to
    }

    public static let top = TableRowResizeAnchor(from: 0, to: 0)

    public static func bottom(oldHeight: CGFloat, newHeight: CGFloat) -> TableRowResizeAnchor {
        return TableRowResizeAnchor(from: oldHeight, to: newHeight)
    }

    public static func resolve(oldHeight: CGFloat, newHeight: CGFloat, click: CGFloat?, unchangedTop: CGFloat? = nil, unchangedBottom: CGFloat? = nil, sticksToBottom: Bool) -> TableRowResizeAnchor {
        let delta = newHeight - oldHeight
        guard let click = click.map({ min(max($0, 0), oldHeight) }) else {
            if sticksToBottom {
                return .bottom(oldHeight: oldHeight, newHeight: newHeight)
            }
            if let unchangedTop = unchangedTop, let unchangedBottom = unchangedBottom, unchangedBottom > unchangedTop {
                return .bottom(oldHeight: oldHeight, newHeight: newHeight)
            }
            return .top
        }
        if let unchangedTop = unchangedTop, click <= unchangedTop {
            return TableRowResizeAnchor(from: click, to: click)
        }
        if let unchangedBottom = unchangedBottom, click >= oldHeight - unchangedBottom {
            return TableRowResizeAnchor(from: click, to: click + delta)
        }
        if click < oldHeight / 2 {
            return TableRowResizeAnchor(from: click, to: min(click, newHeight))
        }
        return TableRowResizeAnchor(from: click, to: max(click + delta, 0))
    }

    public static func pointer(from: CGFloat, to: CGFloat, oldHeight: CGFloat, newHeight: CGFloat) -> TableRowResizeAnchor {
        let shift = to - from
        let delta = newHeight - oldHeight
        if abs(shift - delta) <= 1.5 {
            return TableRowResizeAnchor(from: from, to: from + delta)
        }
        if abs(shift) <= 1.5 {
            return TableRowResizeAnchor(from: from, to: from)
        }
        return TableRowResizeAnchor(from: from, to: to)
    }

    public var contentShift: CGFloat {
        return from - to
    }

    public func pin(_ view: NSView, transition: ContainedViewLayoutTransition) {
        guard let layer = view.layer else {
            return
        }
        guard case let .animated(duration, curve) = transition else {
            layer.removeAnimation(forKey: TableRowResizeAnchor.pinKey)
            return
        }
        let shift = view.superview?.isFlipped == false ? -contentShift : contentShift
        if case .spring = curve {
            layer.animatePosition(from: NSMakePoint(0, shift), to: .zero, duration: duration, timingFunction: curve.timingFunction, additive: true)
            return
        }
        let inflight = TableRowResizeAnchor.inflightOffset(layer.animation(forKey: TableRowResizeAnchor.pinKey), now: layer.convertTime(CACurrentMediaTime(), from: nil))
        guard abs(shift + inflight) > 0.25 else {
            layer.removeAnimation(forKey: TableRowResizeAnchor.pinKey)
            return
        }
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: NSMakePoint(0, shift + inflight))
        animation.toValue = NSValue(point: .zero)
        animation.isAdditive = true
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: curve.timingFunction)
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: TableRowResizeAnchor.pinKey)
    }

    private static let pinKey = "tableRowResizeAnchor.pin"

    static func inflightOffset(_ animation: CAAnimation?, now: CFTimeInterval) -> CGFloat {
        guard let animation = animation as? CABasicAnimation, let from = (animation.fromValue as? NSValue)?.pointValue else {
            return 0
        }
        guard animation.beginTime > 0, animation.duration > 0 else {
            return from.y
        }
        let progress = min(max((now - animation.beginTime) / animation.duration, 0), 1)
        return from.y * (1 - eased(progress, animation.timingFunction))
    }

    static func eased(_ progress: Double, _ function: CAMediaTimingFunction?) -> CGFloat {
        guard let function = function else {
            return CGFloat(progress)
        }
        var p1: [Float] = [0, 0]
        var p2: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &p1)
        function.getControlPoint(at: 2, values: &p2)
        let x1 = Double(p1[0]), y1 = Double(p1[1]), x2 = Double(p2[0]), y2 = Double(p2[1])
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var low = 0.0
        var high = 1.0
        var t = progress
        for _ in 0 ..< 40 {
            let x = bezier(t, x1, x2)
            if abs(x - progress) < 1e-6 {
                break
            }
            if x < progress {
                low = t
            } else {
                high = t
            }
            t = (low + high) / 2
        }
        return CGFloat(bezier(t, y1, y2))
    }

    public static func offset(anchor: TableRowResizeAnchor, oldRect: CGRect, newRect: CGRect, offset: CGFloat, viewport: CGFloat, flipped: Bool, range: ClosedRange<CGFloat>) -> CGFloat {
        let shift: CGFloat
        if oldRect.maxY <= offset {
            shift = newRect.maxY - oldRect.maxY
        } else if oldRect.minY >= offset + viewport {
            shift = newRect.minY - oldRect.minY
        } else if flipped {
            shift = (newRect.minY + anchor.to) - (oldRect.minY + anchor.from)
        } else {
            shift = (newRect.maxY - anchor.to) - (oldRect.maxY - anchor.from)
        }
        return min(max(offset + shift, range.lowerBound), range.upperBound)
    }
}

public struct TableRowResizePacing {
    public static let continuousGap: CFTimeInterval = 0.1
    public static let minimumAnimatedDelta: CGFloat = 16
    private var lastChange: CFTimeInterval = 0
    private var animatingUntil: CFTimeInterval = 0

    public init() {
    }

    public mutating func animates(delta: CGFloat, allowed: Bool, now: CFTimeInterval, duration: CFTimeInterval = 0.2) -> Bool {
        let continuous = now - lastChange < TableRowResizePacing.continuousGap
        lastChange = now
        let animated = allowed && !continuous && (now < animatingUntil || abs(delta) > TableRowResizePacing.minimumAnimatedDelta)
        if animated {
            animatingUntil = now + duration
        }
        return animated
    }
}
