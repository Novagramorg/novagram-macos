import Cocoa

public enum StoryStripScrollRoute: Equatable {
    case forward
    case native
    case scrollHorizontally(CGFloat)
    case ignore
}

public struct StoryStripScrollRouter {
    public private(set) var axis: StoryRevealAxis?
    private var nativeUntil: Double = -.greatestFiniteMagnitude
    private var ownsGesture = false

    public static let nativeTail: Double = 0.3
    public static let wheelLineWidth: CGFloat = 10

    public init() {
    }

    public static func wheelOffset(current: CGFloat, delta: CGFloat, limit: CGFloat) -> CGFloat? {
        let target = min(max(0, current - delta * StoryStripScrollRouter.wheelLineWidth), max(0, limit))
        return target == current ? nil : target
    }

    public mutating func route(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, dx: CGFloat, dy: CGFloat, precise: Bool, expanded: Bool, time: Double) -> StoryStripScrollRoute {
        let route = self.decide(phase: phase, momentumPhase: momentumPhase, dx: dx, dy: dy, precise: precise, expanded: expanded, time: time)
        if phase == .ended || phase == .cancelled {
            self.ownsGesture = false
        }
        return route
    }

    private mutating func decide(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, dx: CGFloat, dy: CGFloat, precise: Bool, expanded: Bool, time: Double) -> StoryStripScrollRoute {
        if phase == .began || phase == .mayBegin {
            self.axis = nil
            self.ownsGesture = true
        }
        if self.axis == .horizontal, time > self.nativeUntil {
            self.axis = nil
            self.ownsGesture = false
        }
        if phase == .mayBegin {
            return .forward
        }
        let isWheel = phase == [] && momentumPhase == []
        let axis: StoryRevealAxis
        if isWheel {
            if dx == 0 && dy == 0 {
                return .ignore
            }
            axis = abs(dx) > abs(dy) ? .horizontal : .vertical
            if axis == .vertical, expanded, !precise {
                return .scrollHorizontally(dy)
            }
        } else if let current = self.axis {
            axis = current
        } else if dx == 0 && dy == 0 {
            if phase == .began || phase == .ended || phase == .cancelled || momentumPhase != [] {
                return .forward
            }
            return .ignore
        } else {
            axis = abs(dx) > abs(dy) ? .horizontal : .vertical
            if axis == .horizontal, !self.ownsGesture {
                return .forward
            }
            self.axis = axis
        }
        if axis == .vertical || !expanded {
            return .forward
        }
        self.nativeUntil = time + StoryStripScrollRouter.nativeTail
        return .native
    }
}
