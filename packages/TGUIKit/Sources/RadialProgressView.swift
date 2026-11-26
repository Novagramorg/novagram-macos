import Cocoa
import SwiftSignalKit

private func progressInteractiveThumb(backgroundColor: NSColor, foregroundColor: NSColor) -> CGImage {
    
    let context = DrawingContext(size: NSMakeSize(40, 40), scale: 1.0, clear: true)
    
    context.withContext { (ctx) in
        
        ctx.round(context.size, context.size.height/2.0)
        ctx.setFillColor(backgroundColor.cgColor)
        
        let image = #imageLiteral(resourceName: "Icon_MessageFile").precomposed(foregroundColor)
        
        ctx.fill(NSMakeRect(0, 0, context.size.width, context.size.height))
        ctx.draw(image, in: NSMakeRect(floorToScreenPixels(System.backingScale, (context.size.width - image.backingSize.width) / 2.0), floorToScreenPixels(System.backingScale, (context.size.height - image.backingSize.height) / 2.0), image.backingSize.width, image.backingSize.height))
        
    }
    
    return context.generateImage()!
    
}

public struct FetchControls {
    public let fetch: () -> Void
    public init(fetch:@escaping()->Void) {
        self.fetch = fetch
    }
}


private class RadialProgressParameters: NSObject {
    let theme: RadialProgressTheme
    let diameter: CGFloat
    let twist: Bool
    let state: RadialProgressState
    let clockwise: Bool
    init(theme: RadialProgressTheme, diameter: CGFloat, state: RadialProgressState, twist: Bool = true) {
        self.theme = theme
        self.diameter = diameter
        self.state = state
        self.twist = twist
        self.clockwise = theme.clockwise
        super.init()
    }
}

public struct RadialProgressTheme : Equatable {
    public let backgroundColor: NSColor
    public let foregroundColor: NSColor
    public let icon: CGImage?
    public let cancelFetchingIcon: CGImage?
    public let iconInset:NSEdgeInsets
    public let diameter:CGFloat?
    public let lineWidth: CGFloat
    public let clockwise: Bool
    public let blendMode: CGBlendMode
    public init(backgroundColor:NSColor, foregroundColor:NSColor, icon:CGImage? = nil, cancelFetchingIcon: CGImage? = nil, iconInset:NSEdgeInsets = NSEdgeInsets(), diameter: CGFloat? = nil, lineWidth: CGFloat = 2, clockwise: Bool = true, blendMode: CGBlendMode = .normal) {
        self.iconInset = iconInset
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.icon = icon
        self.cancelFetchingIcon = cancelFetchingIcon
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.clockwise = clockwise
        self.blendMode = blendMode
    }
}

public func ==(lhs:RadialProgressTheme, rhs:RadialProgressTheme) -> Bool {
    return lhs.backgroundColor == rhs.backgroundColor && lhs.foregroundColor == rhs.foregroundColor && ((lhs.icon == nil) == (rhs.icon == nil)) && lhs.blendMode == rhs.blendMode
}

public enum RadialProgressState: Equatable {
    case None
    case Remote
    case Fetching(progress: Float, force: Bool)
    case ImpossibleFetching(progress: Float, force: Bool)
    case Play
    case Icon(image:CGImage)
    case Success
}

public func ==(lhs:RadialProgressState, rhs:RadialProgressState) -> Bool {
    switch lhs {
    case .None:
        if case .None = rhs {
            return true
        } else {
            return false
        }
    case .Remote:
        if case .Remote = rhs {
            return true
        } else {
            return false
        }
    case .Success:
        if case .Success = rhs {
            return true
        } else {
            return false
        }
    case .Play:
        if case .Play = rhs {
            return true
        } else {
            return false
        }
    case let .Fetching(progress, force):
        if case .Fetching(progress, force) = rhs {
            return true
        } else {
            return false
        }
    case let .ImpossibleFetching(progress, force):
            if case .ImpossibleFetching(progress, force) = rhs {
                return true
            } else {
                return false
        }
    case .Icon:
        if case .Icon = rhs {
            return true
        } else {
            return false
        }
    }
}


struct RadialProgressSegment: Equatable {
    var from: CGPoint
    var to: CGPoint

    func interpolated(to other: RadialProgressSegment, _ t: CGFloat) -> RadialProgressSegment {
        return RadialProgressSegment(from: CGPoint(x: self.from.x + (other.from.x - self.from.x) * t, y: self.from.y + (other.from.y - self.from.y) * t), to: CGPoint(x: self.to.x + (other.to.x - self.to.x) * t, y: self.to.y + (other.to.y - self.to.y) * t))
    }

    var length: CGFloat {
        return hypot(self.to.x - self.from.x, self.to.y - self.from.y)
    }
}

struct RadialProgressGlyphGeometry {
    let stem: RadialProgressSegment
    let first: RadialProgressSegment
    let second: RadialProgressSegment
    let lineWidth: CGFloat

    static func arrow(diameter: CGFloat) -> RadialProgressGlyphGeometry {
        let factor = diameter / 50.0
        let arrowHeadSize: CGFloat = 15.0 * factor
        let arrowLength: CGFloat = 18.0 * factor
        let arrowHeadOffset: CGFloat = 1.0 * factor
        let tip = CGPoint(x: diameter / 2.0, y: diameter / 2.0 + arrowLength / 2.0 + arrowHeadOffset)
        return RadialProgressGlyphGeometry(
            stem: RadialProgressSegment(from: CGPoint(x: diameter / 2.0, y: diameter / 2.0 - arrowLength / 2.0 + arrowHeadOffset), to: CGPoint(x: diameter / 2.0, y: diameter / 2.0 + arrowLength / 2.0 - 1.0 + arrowHeadOffset)),
            first: RadialProgressSegment(from: CGPoint(x: diameter / 2.0 - arrowHeadSize / 2.0, y: diameter / 2.0 + arrowLength / 2.0 - arrowHeadSize / 2.0 + arrowHeadOffset), to: tip),
            second: RadialProgressSegment(from: CGPoint(x: diameter / 2.0 + arrowHeadSize / 2.0, y: diameter / 2.0 + arrowLength / 2.0 - arrowHeadSize / 2.0 + arrowHeadOffset), to: tip),
            lineWidth: diameter < 24.0 ? 1.3 : 2.0)
    }

    static let ringGap: CGFloat = 1.0

    static func ringPathDiameter(diameter: CGFloat, lineWidth: CGFloat, twist: Bool) -> CGFloat {
        return twist ? diameter - lineWidth - lineWidth * lineWidth : diameter - lineWidth
    }

    static func ringInnerRadius(diameter: CGFloat, lineWidth: CGFloat, twist: Bool) -> CGFloat {
        return ringPathDiameter(diameter: diameter, lineWidth: lineWidth, twist: twist) / 2.0 - lineWidth / 2.0
    }

    static func cross(diameter: CGFloat, ringInnerRadius: CGFloat) -> RadialProgressGlyphGeometry {
        let lineWidth: CGFloat = 2.0
        let crossSize: CGFloat = min(diameter < 40 ? 9 : 14.0, max(0, ringInnerRadius - lineWidth / 2.0 - ringGap) * sqrt(2.0))
        let center = CGPoint(x: diameter / 2.0, y: diameter / 2.0)
        return RadialProgressGlyphGeometry(
            stem: RadialProgressSegment(from: center, to: center),
            first: RadialProgressSegment(from: CGPoint(x: center.x - crossSize / 2.0, y: center.y - crossSize / 2.0), to: CGPoint(x: center.x + crossSize / 2.0, y: center.y + crossSize / 2.0)),
            second: RadialProgressSegment(from: CGPoint(x: center.x + crossSize / 2.0, y: center.y - crossSize / 2.0), to: CGPoint(x: center.x - crossSize / 2.0, y: center.y + crossSize / 2.0)),
            lineWidth: lineWidth)
    }

    static func morph(diameter: CGFloat, ringInnerRadius: CGFloat, value: CGFloat) -> RadialProgressGlyphGeometry {
        let arrow = RadialProgressGlyphGeometry.arrow(diameter: diameter)
        let cross = RadialProgressGlyphGeometry.cross(diameter: diameter, ringInnerRadius: ringInnerRadius)
        return RadialProgressGlyphGeometry(
            stem: arrow.stem.interpolated(to: cross.stem, value),
            first: arrow.first.interpolated(to: cross.first, value),
            second: arrow.second.interpolated(to: cross.second, value),
            lineWidth: arrow.lineWidth + (cross.lineWidth - arrow.lineWidth) * value)
    }
}

struct RadialProgressFlowPath {
    let points: [CGPoint]
    let distances: [CGFloat]
    let stemLength: CGFloat
    let entryDistance: CGFloat
    let entryAngle: CGFloat
    let radius: CGFloat
    let arrowLineWidth: CGFloat
    let diameter: CGFloat

    var handoffProgress: CGFloat {
        return self.stemLength / (2.0 * CGFloat.pi * self.radius)
    }

    static func make(diameter: CGFloat, ringCenter: CGPoint, ringRadius: CGFloat) -> RadialProgressFlowPath {
        let factor = diameter / 50.0
        let center = CGPoint(x: diameter / 2.0, y: diameter / 2.0)
        let arrow = RadialProgressGlyphGeometry.arrow(diameter: diameter)
        func design(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: center.x + x * factor, y: center.y + y * factor)
        }
        let tip = arrow.first.to
        let curveStart = design(-18.283, 11.771)
        var lastControl = design(-19.755, 9.240)
        var entry = design(-20.299, 7.769)
        let entryAngle = atan2(entry.y - ringCenter.y, entry.x - ringCenter.x)
        let projected = CGPoint(x: ringCenter.x + cos(entryAngle) * ringRadius, y: ringCenter.y + sin(entryAngle) * ringRadius)
        lastControl = CGPoint(x: lastControl.x + projected.x - entry.x, y: lastControl.y + projected.y - entry.y)
        entry = projected

        var points: [CGPoint] = [arrow.stem.from, arrow.stem.to, tip]
        func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
            let steps = 48
            for step in 1 ... steps {
                let t = CGFloat(step) / CGFloat(steps)
                let u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                points.append(CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y))
            }
        }
        cubic(tip, design(0, 21.719), design(-12.189, 21.021), curveStart)
        cubic(curveStart, design(-19.07, 10.577), lastControl, entry)
        let entryIndex = points.count - 1
        let arcSteps = 180
        for step in 1 ... arcSteps {
            let angle = entryAngle + CGFloat(step) / CGFloat(arcSteps) * 2.0 * CGFloat.pi
            points.append(CGPoint(x: ringCenter.x + cos(angle) * ringRadius, y: ringCenter.y + sin(angle) * ringRadius))
        }
        var distances: [CGFloat] = [0]
        for index in 1 ..< points.count {
            distances.append(distances[index - 1] + hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y))
        }
        return RadialProgressFlowPath(points: points, distances: distances, stemLength: arrow.stem.length, entryDistance: distances[entryIndex], entryAngle: entryAngle, radius: ringRadius, arrowLineWidth: arrow.lineWidth, diameter: diameter)
    }

    func point(at distance: CGFloat) -> CGPoint {
        let distance = min(max(0, distance), self.distances[self.distances.count - 1])
        var low = 0
        var high = self.distances.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if self.distances[middle] <= distance {
                low = middle
            } else {
                high = middle
            }
        }
        let span = self.distances[high] - self.distances[low]
        let t = span > 0 ? (distance - self.distances[low]) / span : 0
        let a = self.points[low], b = self.points[high]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    func segment(from start: CGFloat, to end: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = [self.point(at: start)]
        for index in self.distances.indices where self.distances[index] > start && self.distances[index] < end {
            result.append(self.points[index])
        }
        result.append(self.point(at: end))
        return result
    }

    func travel(_ value: CGFloat) -> CGFloat {
        return value * self.entryDistance
    }
}

private struct RadialProgressValueAnimation {
    let from: CGFloat
    let to: CGFloat
    let start: CFTimeInterval
    let delay: Double
    let duration: Double
    let curve: (CGFloat) -> CGFloat

    func value(at time: CFTimeInterval) -> CGFloat {
        let t = self.duration <= 0 ? 1 : min(1, max(0, CGFloat((time - self.start - self.delay) / self.duration)))
        return self.from + (self.to - self.from) * self.curve(t)
    }

    func isFinished(at time: CFTimeInterval) -> Bool {
        return time >= self.start + self.delay + self.duration
    }
}

private func radialProgressEaseInOut(_ t: CGFloat) -> CGFloat {
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

private func radialProgressEaseOut(_ t: CGFloat) -> CGFloat {
    return 1 - pow(1 - t, 3)
}

private func radialProgressLinear(_ t: CGFloat) -> CGFloat {
    return t
}

private func radialProgressHermite(startSlope: CGFloat, endSlope: CGFloat) -> (CGFloat) -> CGFloat {
    return { t in
        let t2 = t * t
        let t3 = t2 * t
        return (t3 - 2 * t2 + t) * startSlope + (-2 * t3 + 3 * t2) + (t3 - t2) * endSlope
    }
}

public class RadialProgressView: Control {
    
    static var currentTime: () -> CFTimeInterval = { CACurrentMediaTime() }
    static var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    
    static let morphDuration: Double = 0.3
    static let swapDuration: Double = 0.22
    static let ringDuration: Double = 0.22
    static let progressDuration: Double = 0.2
    static let flowDuration: Double = 0.4
    static let rotationSpeed: CGFloat = CGFloat.pi
    
    public var fetchControls:FetchControls? {
        didSet {
            self.removeAllHandlers()
            if let fetchControls = fetchControls {
                set(handler: { _ in
                    fetchControls.fetch()
                }, for: .Click)
            }
        }
    }
    
    public var theme:RadialProgressTheme {
        didSet {
            if oldValue.blendMode != self.theme.blendMode {
                self.updateRotation(self.ringAlpha > 0)
                self.updateAnimator()
            }
            self.setNeedsDisplay()
        }
    }
    
    private var ringInnerRadius: CGFloat {
        return RadialProgressGlyphGeometry.ringInnerRadius(diameter: NSWidth(self.frame), lineWidth: self.theme.lineWidth, twist: self.twist)
    }
    
    private var isCutout: Bool {
        return self.theme.blendMode == .clear
    }
    
    private var rotationStart: CFTimeInterval?
    private var rotationPhase: CGFloat = 0
    private let twist: Bool
    private var parameters:RadialProgressParameters {
        return RadialProgressParameters(theme: self.theme, diameter: NSWidth(self.frame), state: self.state, twist: self.twist)
    }
    
    
    public var badge: CGRect? {
        didSet {
            _layer.setNeedsDisplay()
            arcLayer.setNeedsDisplay()
        }
    }
    
    public override var accessibilityDefaultLabel: String? {
        switch state {
        case .Fetching, .ImpossibleFetching:
            return localizedString(hasHandlers ? "VoiceOver.Common.CancelDownload" : "VoiceOver.Common.Loading")
        case .Remote:
            return localizedString("VoiceOver.Common.Download")
        case .Play:
            return localizedString("VoiceOver.Common.Play")
        default:
            return nil
        }
    }

    public override func isAccessibilityElement() -> Bool {
        guard TGUIKitAccessibility.isEnabled, !isAccessibilityDecorative, !isHidden else {
            return false
        }
        if case .ImpossibleFetching = state {
            return true
        }
        return super.isAccessibilityElement()
    }

    public override func accessibilityRole() -> NSAccessibility.Role? {
        if TGUIKitAccessibility.isEnabled, !hasHandlers, isAccessibilityElement() {
            return .progressIndicator
        }
        return super.accessibilityRole()
    }

    public override func accessibilityValue() -> Any? {
        if let value = super.accessibilityValue() {
            return value
        }
        guard TGUIKitAccessibility.isEnabled else {
            return nil
        }
        switch state {
        case let .Fetching(progress, _), let .ImpossibleFetching(progress, _):
            return "\(Int((progress * 100).rounded()))%"
        default:
            return nil
        }
    }

    public var state: RadialProgressState {
        get {
            return self.currentState
        }
        set {
            self.setState(newValue, animated: false)
        }
    }
    
    private var currentState: RadialProgressState = .None
    
    private var targetProgress: CGFloat = 0
    private var displayedProgress: CGFloat = 0
    private var progressAnimation: RadialProgressValueAnimation?
    
    private var ringAlpha: CGFloat = 0
    private var ringAnimation: RadialProgressValueAnimation?
    
    private var morph: CGFloat = 0
    private var morphAnimation: RadialProgressValueAnimation?
    
    private var swapFrom: RadialProgressState?
    private var swapFromMorph: CGFloat?
    private var swapAnimation: RadialProgressValueAnimation?
    
    private var flowValue: CGFloat = 0
    private var flowAnimation: RadialProgressValueAnimation?
    private var cachedFlowPath: RadialProgressFlowPath?
    
    private var animator: ConstantDisplayLinkAnimator?
    
    private static let rotationAnimationKey = "radialProgressRotation"
    
    private func isFetching(_ state: RadialProgressState) -> Bool {
        switch state {
        case .Fetching, .ImpossibleFetching:
            return true
        default:
            return false
        }
    }
    
    private func morphValue(_ state: RadialProgressState) -> CGFloat? {
        guard self.theme.cancelFetchingIcon == nil else {
            return nil
        }
        switch state {
        case .Remote:
            return 0
        case .Fetching:
            return 1
        default:
            return nil
        }
    }
    
    private var flowPath: RadialProgressFlowPath {
        let diameter = NSWidth(self.frame)
        let radius = RadialProgressGlyphGeometry.ringPathDiameter(diameter: diameter, lineWidth: self.theme.lineWidth, twist: self.twist) / 2.0
        if let path = self.cachedFlowPath, path.diameter == diameter, path.radius == radius {
            return path
        }
        let path = RadialProgressFlowPath.make(diameter: diameter, ringCenter: self.ringCenter, ringRadius: radius)
        self.cachedFlowPath = path
        return path
    }
    
    private var ringCenter: CGPoint {
        let diameter = NSWidth(self.frame)
        return CGPoint(x: diameter / 2.0, y: floorToScreenPixels(System.backingScale, diameter / 2.0))
    }
    
    private var canFlow: Bool {
        return NSWidth(self.frame) >= 24 && self.theme.cancelFetchingIcon == nil && self.theme.clockwise
    }
    
    private var isFlowing: Bool {
        return self.flowAnimation != nil || self.flowValue > 0
    }
    
    private var isFlowingIn: Bool {
        if let animation = self.flowAnimation {
            return animation.to >= 1
        }
        return false
    }
    
    public func setState(_ state: RadialProgressState, animated: Bool) {
        let previous = self.currentState
        self.currentState = state
        let time = RadialProgressView.currentTime()
        self.advance(to: time)
        
        let kindChanged = !isSameKind(previous, state)
        let animated = animated && kindChanged
        let reduceMotion = animated && RadialProgressView.reduceMotion()
        
        var restingArrow = false
        if case .Remote = previous, self.morphAnimation == nil, self.swapAnimation == nil, self.morph == 0, self.ringAlpha == 0 {
            restingArrow = true
        }
        if animated, !reduceMotion, self.canFlow, case .Fetching = state, self.isFlowing || restingArrow {
            let remaining = 1 - self.flowValue
            let path = self.flowPath
            let endSlope = RadialProgressView.rotationSpeed * path.radius * CGFloat(RadialProgressView.flowDuration) / max(1, path.entryDistance)
            let curve: (CGFloat) -> CGFloat = self.flowValue == 0 ? radialProgressHermite(startSlope: 1.2, endSlope: min(2, endSlope)) : radialProgressEaseOut
            self.flowAnimation = RadialProgressValueAnimation(from: self.flowValue, to: 1, start: time, delay: 0, duration: RadialProgressView.flowDuration * Double(max(0.35, remaining)), curve: curve)
        } else if animated, !reduceMotion, self.isFlowing, case .Remote = state {
            self.flowAnimation = RadialProgressValueAnimation(from: self.flowValue, to: 0, start: time, delay: 0, duration: RadialProgressView.flowDuration * Double(max(0.35, self.flowValue)), curve: radialProgressEaseOut)
        } else if kindChanged {
            self.flowAnimation = nil
            self.flowValue = 0
        }
        
        if animated, !reduceMotion, self.swapAnimation == nil, morphValue(previous) != nil, let to = morphValue(state) {
            let distance = abs(to - self.morph)
            self.morphAnimation = RadialProgressValueAnimation(from: self.morph, to: to, start: time, delay: 0, duration: RadialProgressView.morphDuration * Double(max(0.35, distance)), curve: radialProgressEaseOut)
        } else if animated {
            self.swapFromMorph = morphValue(previous) != nil && self.swapAnimation == nil ? self.morph : nil
            self.morphAnimation = nil
            self.morph = morphValue(state) ?? (isFetching(state) ? 1 : 0)
            self.swapFrom = previous
            self.swapAnimation = RadialProgressValueAnimation(from: 0, to: 1, start: time, delay: 0, duration: RadialProgressView.swapDuration, curve: radialProgressEaseOut)
        } else if kindChanged {
            self.morphAnimation = nil
            self.swapFrom = nil
            self.swapFromMorph = nil
            self.swapAnimation = nil
            self.morph = morphValue(state) ?? (isFetching(state) ? 1 : 0)
        }
        
        switch state {
        case let .Fetching(progress, _) where self.isFlowingIn:
            self.targetProgress = self.twist ? max(CGFloat(progress), 0.05) : CGFloat(progress)
        case let .Fetching(progress, force), let .ImpossibleFetching(progress, force):
            let target = self.twist ? max(CGFloat(progress), 0.05) : CGFloat(progress)
            let entering = !isFetching(previous)
            if entering && !animated {
                self.displayedProgress = 0
                self.progressAnimation = nil
            }
            if force {
                self.displayedProgress = target
                self.progressAnimation = nil
            }
            let difference = target - self.displayedProgress
            let clockwise = self.theme.clockwise
            if (clockwise && difference > 0) || (!clockwise && difference != 0) {
                self.progressAnimation = RadialProgressValueAnimation(from: self.displayedProgress, to: target, start: time, delay: 0, duration: RadialProgressView.progressDuration, curve: radialProgressLinear)
            } else {
                self.progressAnimation = nil
                self.displayedProgress = target
            }
            self.targetProgress = target
            if animated && self.ringAlpha < 1 {
                self.ringAnimation = RadialProgressValueAnimation(from: self.ringAlpha, to: 1, start: time, delay: 0, duration: RadialProgressView.ringDuration, curve: radialProgressEaseOut)
            } else {
                self.ringAnimation = nil
                self.ringAlpha = 1
            }
            self.updateRotation(true)
        default:
            self.targetProgress = 0
            if animated && self.ringAlpha > 0 {
                if case .Remote = state {
                    self.progressAnimation = RadialProgressValueAnimation(from: self.displayedProgress, to: 0, start: time, delay: 0, duration: RadialProgressView.morphDuration, curve: radialProgressEaseOut)
                    self.ringAnimation = RadialProgressValueAnimation(from: self.ringAlpha, to: 0, start: time, delay: 0.08, duration: RadialProgressView.ringDuration, curve: radialProgressEaseInOut)
                } else {
                    self.progressAnimation = RadialProgressValueAnimation(from: self.displayedProgress, to: 1, start: time, delay: 0, duration: RadialProgressView.progressDuration, curve: radialProgressEaseOut)
                    self.ringAnimation = RadialProgressValueAnimation(from: self.ringAlpha, to: 0, start: time, delay: RadialProgressView.progressDuration * 0.6, duration: RadialProgressView.ringDuration, curve: radialProgressEaseInOut)
                }
            } else {
                self.progressAnimation = nil
                self.ringAnimation = nil
                self.displayedProgress = 0
                self.ringAlpha = 0
                self.updateRotation(false)
            }
        }
        self.updateAnimator()
        self.setNeedsDisplay()
    }
    
    private func isSameKind(_ lhs: RadialProgressState, _ rhs: RadialProgressState) -> Bool {
        switch (lhs, rhs) {
        case (.Fetching, .Fetching), (.ImpossibleFetching, .ImpossibleFetching), (.None, .None), (.Remote, .Remote), (.Play, .Play), (.Success, .Success):
            return true
        case let (.Icon(lhsImage), .Icon(rhsImage)):
            return lhsImage === rhsImage
        default:
            return false
        }
    }
    
    private var isAnimating: Bool {
        return self.progressAnimation != nil || self.ringAnimation != nil || self.morphAnimation != nil || self.swapAnimation != nil || self.flowAnimation != nil || (self.isCutout && self.twist && self.ringAlpha > 0 && self.window != nil)
    }
    
    private func completeFlow(at time: CFTimeInterval) {
        let path = self.flowPath
        self.flowValue = 0
        self.ringAnimation = nil
        self.ringAlpha = 1
        self.displayedProgress = path.handoffProgress
        if abs(self.targetProgress - path.handoffProgress) > 0.001 {
            self.progressAnimation = RadialProgressValueAnimation(from: path.handoffProgress, to: self.targetProgress, start: time, delay: 0, duration: 0.3, curve: radialProgressEaseOut)
        } else {
            self.progressAnimation = nil
            self.displayedProgress = self.targetProgress
        }
        self.updateRotation(false)
        self.rotationPhase = path.entryAngle + CGFloat.pi / 2.0
        self.updateRotation(true, at: time)
    }
    
    private func advance(to time: CFTimeInterval) {
        if let animation = self.flowAnimation {
            self.flowValue = animation.value(at: time)
            if animation.isFinished(at: time) {
                self.flowAnimation = nil
                if animation.to >= 1 {
                    if case .Fetching = self.currentState {
                        self.completeFlow(at: animation.start + animation.delay + animation.duration)
                    } else {
                        self.flowValue = 0
                    }
                } else {
                    self.flowValue = 0
                }
            }
        }
        if let animation = self.progressAnimation {
            self.displayedProgress = animation.value(at: time)
            if animation.isFinished(at: time) {
                self.progressAnimation = nil
            }
        }
        if let animation = self.ringAnimation {
            self.ringAlpha = animation.value(at: time)
            if animation.isFinished(at: time) {
                self.ringAnimation = nil
                if self.ringAlpha <= 0 {
                    self.displayedProgress = 0
                    self.progressAnimation = nil
                    self.updateRotation(false)
                }
            }
        }
        if let animation = self.morphAnimation {
            self.morph = animation.value(at: time)
            if animation.isFinished(at: time) {
                self.morphAnimation = nil
            }
        }
        if let animation = self.swapAnimation, animation.isFinished(at: time) {
            self.swapAnimation = nil
            self.swapFrom = nil
            self.swapFromMorph = nil
        }
    }
    
    private func updateAnimator() {
        if self.isAnimating {
            if self.animator == nil {
                let animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] _ in
                    self?.tick()
                })
                self.animator = animator
            }
            self.animator?.isPaused = false
        } else {
            self.animator?.isPaused = true
            self.animator = nil
        }
    }
    
    private func tick() {
        self.advance(to: RadialProgressView.currentTime())
        self.setNeedsDisplay()
        if !self.isAnimating {
            self.updateAnimator()
        }
    }
    
    func advanceForTesting(to time: CFTimeInterval) {
        self.advance(to: time)
        if !self.isAnimating {
            self.updateAnimator()
        }
    }
    
    var displayedValuesForTesting: (progress: CGFloat, ring: CGFloat, morph: CGFloat, swap: CGFloat?) {
        let time = RadialProgressView.currentTime()
        return (self.displayedProgress, self.ringAlpha, self.morph, self.swapAnimation?.value(at: time))
    }
    
    var flowValueForTesting: CGFloat? {
        return self.isFlowing ? self.flowValue : nil
    }
    
    var flowPathForTesting: RadialProgressFlowPath {
        return self.flowPath
    }
    
    var rotationForTesting: (phase: CGFloat, start: CFTimeInterval?, animationFrom: CGFloat?) {
        let animation = self.arcLayer.animation(forKey: Self.rotationAnimationKey) as? CABasicAnimation
        return (self.rotationPhase, self.rotationStart, animation?.fromValue as? CGFloat)
    }
    
    private func updateRotation(_ animate: Bool, at time: CFTimeInterval? = nil) {
        let layer = self.arcLayer
        if animate {
            if self.rotationStart == nil {
                self.rotationStart = time ?? RadialProgressView.currentTime()
            }
        } else {
            self.rotationStart = nil
            self.rotationPhase = 0
        }
        if animate, self.twist, self.superview != nil, !self.isCutout {
            guard layer.animation(forKey: Self.rotationAnimationKey) == nil else {
                return
            }
            var fromValue: CGFloat = self.rotationPhase
            if time == nil, let presentation = layer.presentation(), let value = presentation.value(forKeyPath: "transform.rotation.z") as? CGFloat {
                fromValue += value
            }
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = fromValue
            animation.toValue = fromValue + CGFloat.pi * 2.0
            animation.duration = Double(2.0 * CGFloat.pi / RadialProgressView.rotationSpeed)
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(animation, forKey: Self.rotationAnimationKey)
        } else if !animate || self.isCutout {
            layer.removeAnimation(forKey: Self.rotationAnimationKey)
        }
    }
    
    public override func setNeedsDisplay() {
        super.setNeedsDisplay()
        _layer.setNeedsDisplay()
        arcLayer.setNeedsDisplay()
    }
    
    public override func viewDidMoveToSuperview() {
        self.updateRotation(superview != nil && self.ringAlpha > 0)
    }
    
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override public var frame: CGRect {
        get {
            return super.frame
        } set (value) {
            let redraw = value.size != self.frame.size
            super.frame = value
            
            if redraw {
                self.setNeedsDisplay()
                self._layer.frame = CGRect(origin: CGPoint(), size: value.size)
                self.arcLayer.frame = CGRect(origin: CGPoint(), size: value.size)
            }
        }
    }
    private let _layer = SimpleLayer()
    private let arcLayer = SimpleLayer()
    
    public init(theme: RadialProgressTheme = RadialProgressTheme(backgroundColor: .blackTransparent, foregroundColor: .white, icon: nil), twist: Bool = true, size: NSSize = NSMakeSize(40, 40)) {
        self.theme = theme
        self.twist = twist
        super.init()
        self.frame = NSMakeRect(0, 0, size.width, size.height)
        self.layer?.addSublayer(_layer)
        self.layer?.addSublayer(arcLayer)
        
        layer?.masksToBounds = false
        _layer.masksToBounds = false
        arcLayer.masksToBounds = false
        
        _layer.frame = self.bounds
        arcLayer.frame = self.bounds
        _layer.onDraw = { [weak self] _, ctx in
            self?.draw(context: ctx)
        }
        arcLayer.onDraw = { [weak self] _, ctx in
            self?.drawArc(context: ctx)
        }
        _layer.setNeedsDisplay()
        arcLayer.setNeedsDisplay()
    }
    
    private func fadingBlendMode(_ alpha: CGFloat) -> CGBlendMode {
        let blendMode = self.parameters.theme.blendMode
        if alpha < 1, blendMode == .clear {
            return .destinationOut
        }
        return blendMode
    }

    private func drawArc(context: CGContext) {
        guard self.ringAlpha > 0.001, !self.isCutout else {
            return
        }
        self.strokeRing(context: context)
        if let badge = badge {
            context.saveGState()
            let path = CGMutablePath()
            path.addEllipse(in: badge)
            context.addPath(path)
            context.clip()
            context.clear(badge)
            context.restoreGState()
        }
    }
    
    private func strokeRing(context: CGContext) {
        let parameters = self.parameters
        let alpha = min(1, self.ringAlpha)
        context.saveGState()
        context.setBlendMode(fadingBlendMode(alpha))
        context.setAlpha(alpha)
        context.setStrokeColor(parameters.theme.foregroundColor.cgColor)
        let diameter = parameters.diameter
        if self.isCutout, self.twist, let rotationStart = self.rotationStart {
            let angle = self.rotationPhase + CGFloat(RadialProgressView.currentTime() - rotationStart) * RadialProgressView.rotationSpeed
            let center = CGPoint(x: diameter / 2.0, y: floorToScreenPixels(System.backingScale, diameter / 2.0))
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angle)
            context.translateBy(x: -center.x, y: -center.y)
        }
        let startAngle = 2.0 * (CGFloat.pi) * self.displayedProgress - CGFloat.pi / 2
        let endAngle = -(CGFloat.pi / 2)
        
        let pathDiameter = RadialProgressGlyphGeometry.ringPathDiameter(diameter: diameter, lineWidth: parameters.theme.lineWidth, twist: self.twist)
        context.addArc(center: NSMakePoint(diameter / 2.0, floorToScreenPixels(System.backingScale, diameter / 2.0)), radius: pathDiameter / 2.0, startAngle: startAngle, endAngle: endAngle, clockwise: parameters.clockwise)
        
        context.setLineWidth(parameters.theme.lineWidth)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateAnimator()
    }
    
    private func drawFlow(context: CGContext) {
        let path = self.flowPath
        let back = path.travel(self.flowValue)
        let points = path.segment(from: back, to: back + path.stemLength)
        context.saveGState()
        context.setBlendMode(fadingBlendMode(1))
        context.setStrokeColor(self.parameters.theme.foregroundColor.cgColor)
        context.setLineWidth(path.arrowLineWidth + (self.theme.lineWidth - path.arrowLineWidth) * self.flowValue)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addLines(between: points)
        context.strokePath()
        context.restoreGState()
    }
    
    private func drawMorph(context: CGContext, value: CGFloat, alpha: CGFloat = 1, scale: CGFloat = 1, includeStem: Bool = true) {
        guard alpha > 0.001 else {
            return
        }
        let parameters = self.parameters
        let geometry = RadialProgressGlyphGeometry.morph(diameter: parameters.diameter, ringInnerRadius: self.ringInnerRadius, value: value)
        context.saveGState()
        if alpha < 1 {
            context.setAlpha(alpha)
        }
        if scale != 1 {
            let center = CGPoint(x: parameters.diameter / 2.0, y: parameters.diameter / 2.0)
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -center.x, y: -center.y)
        }
        context.setBlendMode(fadingBlendMode(alpha))
        context.setStrokeColor(parameters.theme.foregroundColor.cgColor)
        context.setLineWidth(geometry.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if includeStem, geometry.stem.length > 0.5 {
            context.move(to: geometry.stem.from)
            context.addLine(to: geometry.stem.to)
            context.strokePath()
        }
        context.move(to: geometry.first.from)
        context.addLine(to: geometry.first.to)
        context.move(to: geometry.second.to)
        context.addLine(to: geometry.second.from)
        context.strokePath()
        context.restoreGState()
    }
        
    func draw(context: CGContext) {
        context.setFillColor(parameters.theme.backgroundColor.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(), size: CGSize(width: parameters.diameter, height: parameters.diameter)))
        
        if let swapFrom = self.swapFrom, let animation = self.swapAnimation {
            let t = animation.value(at: RadialProgressView.currentTime())
            let reduceMotion = RadialProgressView.reduceMotion()
            if let morph = self.swapFromMorph {
                drawMorph(context: context, value: morph, alpha: 1 - t, scale: reduceMotion ? 1 : 1 - 0.4 * t)
            } else {
                drawGlyph(context: context, state: swapFrom, alpha: 1 - t, scale: reduceMotion ? 1 : 1 - 0.4 * t)
            }
            drawGlyph(context: context, state: self.currentState, alpha: t, scale: reduceMotion ? 1 : 0.6 + 0.4 * t)
        } else if self.isFlowing {
            drawMorph(context: context, value: self.morph, includeStem: false)
            drawFlow(context: context)
        } else if self.morphAnimation != nil {
            drawMorph(context: context, value: self.morph)
        } else {
            drawGlyph(context: context, state: self.currentState, alpha: 1, scale: 1)
        }
        
        if self.isCutout, self.ringAlpha > 0.001 {
            self.strokeRing(context: context)
        }

        if let badge = badge {
            context.saveGState()
            let rect = badge
            let path = CGMutablePath()
            path.addEllipse(in: rect)
            context.addPath(path)
            context.clip()
            context.clear(rect)
            context.restoreGState()
        }
    }
    
    private func drawGlyph(context: CGContext, state: RadialProgressState, alpha: CGFloat, scale: CGFloat) {
        guard alpha > 0.001 else {
            return
        }
        let parameters = self.parameters
        let blendMode = fadingBlendMode(alpha)
        context.saveGState()
        if alpha < 1 {
            context.setAlpha(alpha)
        }
        if scale != 1 {
            let center = CGPoint(x: parameters.diameter / 2.0, y: parameters.diameter / 2.0)
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -center.x, y: -center.y)
        }
        
        switch state {
        case .None:
            break
        case .Success:
            let diameter = bounds.size.width
            
            let progress: CGFloat = 1.0
            
            var pathLineWidth: CGFloat = 2.0
            
            if (abs(diameter - 37.0) < 0.1) {
                pathLineWidth = 2.5
            } else if (abs(diameter - 32.0) < 0.1) {
                pathLineWidth = 2.0
            } else {
                pathLineWidth = 2.5
            }
            
            let center = CGPoint(x: diameter / 2.0, y: diameter / 2.0)
            
            context.setBlendMode(blendMode)
            
            context.setStrokeColor(parameters.theme.foregroundColor.cgColor)
            context.setLineWidth(pathLineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setMiterLimit(10.0)
            
            let firstSegment: CGFloat = max(0.0, min(1.0, progress * 3.0))
            
            var s = CGPoint(x: center.x - 10.0, y: center.y + 1.0)
            var p1 = CGPoint(x: 7.0, y: 7.0)
            var p2 = CGPoint(x: 15.0, y: -16.0)
            
            if diameter < 36.0 {
                s = CGPoint(x: center.x - 7.0, y: center.y + 1.0)
                p1 = CGPoint(x: 4.5, y: 4.5)
                p2 = CGPoint(x: 10.0, y: -11.0)
            }
            
            if !firstSegment.isZero {
                if firstSegment < 1.0 {
                    context.move(to: CGPoint(x: s.x + p1.x * firstSegment, y: s.y + p1.y * firstSegment))
                    context.addLine(to: s)
                } else {
                    let secondSegment = (progress - 0.33) * 1.5
                    context.move(to: CGPoint(x: s.x + p1.x + p2.x * secondSegment, y: s.y + p1.y + p2.y * secondSegment))
                    context.addLine(to: CGPoint(x: s.x + p1.x, y: s.y + p1.y))
                    context.addLine(to: s)
                }
            }
            context.strokePath()
        case .Fetching:
            if let icon = parameters.theme.cancelFetchingIcon {
                var f = focus(icon.backingSize)
                f.origin.x += parameters.theme.iconInset.left
                f.origin.x -= parameters.theme.iconInset.right
                f.origin.y += parameters.theme.iconInset.top
                f.origin.y -= parameters.theme.iconInset.bottom
                if blendMode == .clear {
                    context.clip(to: f, mask: icon)
                    context.clear(f)
                } else {
                    context.setBlendMode(blendMode)
                    context.draw(icon, in: f)
                }
                
            } else {
                
                context.setBlendMode(blendMode)

                let cross = RadialProgressGlyphGeometry.cross(diameter: parameters.diameter, ringInnerRadius: self.ringInnerRadius)
                
                context.setStrokeColor(parameters.theme.foregroundColor.cgColor)
                context.setLineWidth(cross.lineWidth)
                context.setLineCap(.round)
                
                context.move(to: cross.first.from)
                context.addLine(to: cross.first.to)
                context.strokePath()
                context.move(to: cross.second.from)
                context.addLine(to: cross.second.to)
                context.strokePath()
                

            }
           
        case .Remote:
            let color = parameters.theme.foregroundColor
            let diameter = _layer.frame.height
            
            context.saveGState()
            
            context.setBlendMode(blendMode)

            
            context.setStrokeColor(color.cgColor)
            var lineWidth: CGFloat = 2.0
            if diameter < 24.0 {
                lineWidth = 1.3
            }
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            let factor = diameter / 50.0
            
            let arrowHeadSize: CGFloat = 15.0 * factor
            let arrowLength: CGFloat = 18.0 * factor
            let arrowHeadOffset: CGFloat = 1.0 * factor
            
            context.move(to: CGPoint(x: diameter / 2.0, y: diameter / 2.0 - arrowLength / 2.0 + arrowHeadOffset))
            context.addLine(to: CGPoint(x: diameter / 2.0, y: diameter / 2.0 + arrowLength / 2.0 - 1.0 + arrowHeadOffset))
            context.strokePath()
            
            context.move(to: CGPoint(x: diameter / 2.0 - arrowHeadSize / 2.0, y: diameter / 2.0 + arrowLength / 2.0 - arrowHeadSize / 2.0 + arrowHeadOffset))
            context.addLine(to: CGPoint(x: diameter / 2.0, y: diameter / 2.0 + arrowLength / 2.0 + arrowHeadOffset))
            context.addLine(to: CGPoint(x: diameter / 2.0 + arrowHeadSize / 2.0, y: diameter / 2.0 + arrowLength / 2.0 - arrowHeadSize / 2.0 + arrowHeadOffset))
            context.strokePath()
            
            context.restoreGState()
               
        case .Play:
            let color = parameters.theme.foregroundColor
            let diameter = _layer.frame.height
            context.setFillColor(color.cgColor)
            
            context.setBlendMode(blendMode)

            let factor = diameter / 50.0
            
            let size = CGSize(width: 15.0, height: 18.0)
            context.translateBy(x: (diameter - size.width) / 2.0 + 1.5, y: (diameter - size.height) / 2.0)
            if (diameter < 40.0) {
                context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
                context.scaleBy(x: factor, y: factor)
                context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
            }
            let _ = try? drawSvgPath(context, path: "M1.71891969,0.209353049 C0.769586558,-0.350676705 0,0.0908839327 0,1.18800046 L0,16.8564753 C0,17.9569971 0.750549162,18.357187 1.67393713,17.7519379 L14.1073836,9.60224049 C15.0318735,8.99626906 15.0094718,8.04970371 14.062401,7.49100858 L1.71891969,0.209353049 ")
            context.fillPath()
            if (diameter < 40.0) {
                context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
                context.scaleBy(x: 1.0 / 0.8, y: 1.0 / 0.8)
                context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
            }
            context.translateBy(x: -(diameter - size.width) / 2.0 - 1.5, y: -(diameter - size.height) / 2.0)
        case .ImpossibleFetching:
            break
        case let .Icon(icon):
            var f = focus(icon.backingSize)
            f.origin.x += parameters.theme.iconInset.left
            f.origin.x -= parameters.theme.iconInset.right
            f.origin.y += parameters.theme.iconInset.top
            f.origin.y -= parameters.theme.iconInset.bottom
            
            
            if blendMode == .clear {
                context.clip(to: f, mask: icon)
                context.clear(f)
            } else if blendMode == .destinationOut {
                context.clip(to: f, mask: icon)
                context.setBlendMode(blendMode)
                context.setFillColor(NSColor.black.cgColor)
                context.fill(f)
            } else {
                context.setBlendMode(blendMode)
                context.draw(icon, in: f)
            }
            
        }
        context.restoreGState()
    }
    
    public override func copy() -> Any {
        let view = NSView()
        view.wantsLayer = true
        view.frame = self.frame
        view.layer?.contents = progressInteractiveThumb(backgroundColor: parameters.theme.backgroundColor, foregroundColor: parameters.theme.foregroundColor)
        return view
    }
    
    public override func apply(state: ControlState) {
        
    }
 
}
