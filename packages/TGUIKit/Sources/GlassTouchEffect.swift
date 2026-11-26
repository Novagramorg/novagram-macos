import Cocoa

public final class GlassTouchEffect {

    public struct SpringParameters {
        public var mass: CGFloat
        public var stiffness: CGFloat
        public var damping: CGFloat
        public var initialVelocity: CGFloat

        public init(mass: CGFloat, stiffness: CGFloat, damping: CGFloat, initialVelocity: CGFloat) {
            self.mass = mass
            self.stiffness = stiffness
            self.damping = damping
            self.initialVelocity = initialVelocity
        }
    }

    public struct Parameters {
        public var liftOn: SpringParameters
        public var liftOff: SpringParameters
        public var pressedSizeIncrease: CGFloat
        public var maxOffset: CGFloat

        public init(
            liftOn: SpringParameters = SpringParameters(mass: 1.36, stiffness: 568.0, damping: 39.7, initialVelocity: 0.0),
            liftOff: SpringParameters = SpringParameters(mass: 2.0, stiffness: 460.0, damping: 21.8, initialVelocity: 0.0),
            pressedSizeIncrease: CGFloat = 4.0,
            maxOffset: CGFloat = 24.0
        ) {
            self.liftOn = liftOn
            self.liftOff = liftOff
            self.pressedSizeIncrease = pressedSizeIncrease
            self.maxOffset = maxOffset
        }
    }

    private struct State: Equatable {
        var isTracking: Bool
        var stretchVector: CGPoint
    }

    private weak var transformView: NSView?
    private weak var referenceView: NSView?
    private var state = State(isTracking: false, stretchVector: .zero)
    private var appliedState: State?
    public var parameters = Parameters()

    /// Cache of CASDFElementLayer shadow layers per NSGlassEffectView descendant.
    /// Held only for the duration of a single press: walking the layer tree on
    /// every mouse-move would be wasteful, but holding cached refs across press
    /// cycles is unsafe — AppKit can recycle shadow layers between glass
    /// surfaces, leaving a stale ref pointing at a layer that now serves a
    /// different surface. So the cache is flushed each time a press begins.
    private var cachedShadowLayers: [ObjectIdentifier: [CALayer]] = [:]
    private static let sdfElementLayerClass: AnyClass? = NSClassFromString("CASDFElementLayer")

    /// Optional extra view (typically a ghost glass placed inside
    /// NSGlassEffectContainerView's contentView) whose NSGlassEffectView
    /// descendants should also receive the shadow-layer transform.
    public weak var additionalGlassEffectView: NSView?

    public init(transformView: NSView, referenceView: NSView? = nil) {
        self.transformView = transformView
        self.referenceView = referenceView ?? transformView
    }

    private func currentTransform(for state: State, view: NSView) -> CATransform3D {
        let viewWidth = max(1.0, view.bounds.width)
        let viewHeight = max(1.0, view.bounds.height)
        let aspectRatio = viewWidth / viewHeight

        let baseScale: CGFloat
        if state.isTracking {
            if viewWidth < viewHeight {
                baseScale = 1.0 + parameters.pressedSizeIncrease / viewHeight
            } else {
                baseScale = 1.0 + parameters.pressedSizeIncrease / viewWidth
            }
        } else {
            baseScale = 1.0
        }

        guard state.isTracking else {
            return CATransform3DScale(CATransform3DIdentity, baseScale, baseScale, 1.0)
        }

        let stretchVector = state.stretchVector
        let adjustedX = stretchVector.x / aspectRatio
        let length = sqrt(pow(adjustedX, 2) + pow(stretchVector.y, 2))

        guard length != 0.0 else {
            return CATransform3DScale(CATransform3DIdentity, baseScale, baseScale, 1.0)
        }

        let normal = CGPoint(x: adjustedX / length, y: stretchVector.y / length)
        let k: CGFloat = -1.0 / ((length / viewHeight) / (5.0 * aspectRatio) + 1.0) + 1.0
        let additionalMaxScale = (viewHeight + 16.0 / aspectRatio) / viewHeight - 1.0
        let t = additionalMaxScale * k * aspectRatio
        let maxOffset = parameters.maxOffset

        var transform = CATransform3DIdentity
        if abs(normal.x) > abs(normal.y) {
            let diff = abs(normal.x) - abs(normal.y)
            transform.m11 = baseScale * (1.0 + t * diff)
            transform.m22 = baseScale * (1.0 / (1.0 + t * diff))
        } else {
            let diff = abs(normal.y) - abs(normal.x)
            transform.m11 = baseScale * (1.0 / (1.0 + t * diff))
            transform.m22 = baseScale * (1.0 + t * diff)
        }
        transform.m41 = normal.x * maxOffset * k
        transform.m42 = normal.y * maxOffset * k
        return transform
    }

    private func ensureCenterAnchor() {
        guard let view = transformView, let layer = view.layer else { return }
        let target = CGPoint(x: 0.5, y: 0.5)
        if layer.anchorPoint == target { return }
        let bounds = layer.bounds
        let oldAnchor = layer.anchorPoint
        var pos = layer.position
        pos.x += (target.x - oldAnchor.x) * bounds.width
        pos.y += (target.y - oldAnchor.y) * bounds.height
        layer.anchorPoint = target
        layer.position = pos
    }

    private func currentSpringParameters(from previousState: State?, to state: State) -> SpringParameters {
        guard let previousState, previousState != state else {
            return state.isTracking ? parameters.liftOn : parameters.liftOff
        }
        if !previousState.isTracking && state.isTracking {
            return parameters.liftOn
        }
        return parameters.liftOff
    }

    private func applyCurrentTransform(animated: Bool = true) {
        guard let transformView = transformView, let layer = transformView.layer,
              let reference = referenceView else { return }

        ensureCenterAnchor()
        let targetTransform = currentTransform(for: state, view: reference)
        let spring = animated ? currentSpringParameters(from: appliedState, to: state) : nil

        applyTransform(targetTransform, to: layer, animated: animated, spring: spring, centerAnchor: false)
        applyToShadowLayers(targetTransform, animated: animated, spring: spring)
        applyToFallbackEffectViews(targetTransform, animated: animated, spring: spring)
        appliedState = state
    }

    /// Older macOS (no SDF compositor) renders the glass via the wrapper's
    /// `effectView` — an `NSVisualEffectView` or solid fill. When the ghost
    /// is reparented into a `GlassContainerView` it leaves the button's
    /// subtree, so the button's `layer.transform` no longer cascades to it
    /// and the press squish/stretch doesn't reach the blur. Walk the
    /// `additionalGlassEffectView` for any `LiquidGlassView` whose
    /// `effectView` is NOT an `NSGlassEffectView` and apply the composed
    /// transform directly to its layer.
    ///
    /// The Y-translation in `target` is computed in the source view's coord
    /// space (the button, typically a flipped TGUIKit `View`). Plain
    /// `NSVisualEffectView` is unflipped, so the SAME translation moves it
    /// in the OPPOSITE direction on screen — visible as the press stretching
    /// the glass downward while the content stretches upward. Flip the Y
    /// component when the destination view's flip differs from the source's.
    private func applyToFallbackEffectViews(_ target: CATransform3D, animated: Bool, spring: SpringParameters?) {
        guard let additional = additionalGlassEffectView else { return }
        let sourceFlipped = transformView?.isFlipped ?? false
        let apply: (NSView) -> Void = { [weak self] view in
            guard let self = self, let layer = view.layer else { return }
            var t = target
            if sourceFlipped != view.isFlipped {
                t.m42 = -t.m42
            }
            self.applyCenterComposedTransform(t, to: layer, animated: animated, spring: spring)
        }
        forEachFallbackEffectView(in: additional, apply)
    }

    private func forEachFallbackEffectView(in view: NSView, _ body: (NSView) -> Void) {
        if let liquid = view as? LiquidGlassView, let effectView = liquid.effectView {
            var isGlass = false
            if #available(macOS 26.0, *), effectView is NSGlassEffectView {
                isGlass = true
            }
            if !isGlass {
                body(effectView)
            }
        }
        for sub in view.subviews {
            forEachFallbackEffectView(in: sub, body)
        }
    }

    private func applyToShadowLayers(_ target: CATransform3D, animated: Bool, spring: SpringParameters?) {
        guard #available(macOS 26.0, *), let transformView = transformView else { return }
        let apply: (NSView) -> Void = { [weak self] glass in
            guard let self = self else { return }
            for shadow in self.shadowLayers(for: glass) {
                self.applyCenterComposedTransform(target, to: shadow, animated: animated, spring: spring)
            }
        }
        forEachGlassEffectView(in: transformView, apply)
        if let additional = additionalGlassEffectView {
            forEachGlassEffectView(in: additional, apply)
        }
    }

    /// Apply the press transform composed around the layer's bounds center.
    /// Apple's CATransform3D uses row-vector convention, so the composition
    /// order is T(-c) · S · T(c) — translate to origin, scale, translate back.
    /// Leaves layer.anchorPoint and layer.position alone so AppKit can re-frame
    /// the layer freely without our state leaking out.
    private func applyCenterComposedTransform(_ target: CATransform3D, to layer: CALayer, animated: Bool, spring: SpringParameters?) {
        let cx = layer.bounds.midX
        let cy = layer.bounds.midY
        var composed = CATransform3DMakeTranslation(-cx, -cy, 0)
        composed = CATransform3DConcat(composed, target)
        composed = CATransform3DConcat(composed, CATransform3DMakeTranslation(cx, cy, 0))

        guard animated, let spring else {
            layer.removeAnimation(forKey: "transform")
            layer.transform = composed
            return
        }
        let animation = CASpringAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
        animation.toValue = NSValue(caTransform3D: composed)
        animation.mass = spring.mass
        animation.stiffness = spring.stiffness
        animation.damping = spring.damping
        animation.initialVelocity = spring.initialVelocity
        animation.duration = animation.settlingDuration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        layer.transform = composed
        layer.add(animation, forKey: "transform")
    }

    private func applyTransform(_ target: CATransform3D, to layer: CALayer, animated: Bool, spring: SpringParameters?, centerAnchor: Bool) {
        if centerAnchor {
            ensureCenterAnchor(of: layer)
        }
        guard animated, let spring else {
            layer.removeAnimation(forKey: "transform")
            layer.transform = target
            return
        }
        let animation = CASpringAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
        animation.toValue = NSValue(caTransform3D: target)
        animation.mass = spring.mass
        animation.stiffness = spring.stiffness
        animation.damping = spring.damping
        animation.initialVelocity = spring.initialVelocity
        animation.duration = animation.settlingDuration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = true
        layer.transform = target
        layer.add(animation, forKey: "transform")
    }

    @available(macOS 26.0, *)
    private func forEachGlassEffectView(in view: NSView, _ body: (NSView) -> Void) {
        if view is NSGlassEffectView {
            body(view)
        }
        // After GlassContainerView.addGhost reparents a LiquidGlassView's
        // `effectView` (the NSGlassEffectView) to be a SIBLING in glassContent,
        // the wrapper itself no longer has it as a descendant — walking only
        // its subviews would miss it. Visit the wrapper's known effectView
        // property explicitly so the shadow-layer transform reaches the
        // glass during stretch even when it's been reparented.
        if let liquid = view as? LiquidGlassView {
            if let glass = liquid.effectView, glass is NSGlassEffectView {
                body(glass)
            }
        }
        for sub in view.subviews {
            forEachGlassEffectView(in: sub, body)
        }
    }

    private func shadowLayers(for glass: NSView) -> [CALayer] {
        let key = ObjectIdentifier(glass)
        if let cached = cachedShadowLayers[key], cached.allSatisfy({ $0.superlayer != nil }) {
            return cached
        }
        cachedShadowLayers.removeValue(forKey: key)
        guard #available(macOS 26.0, *),
              let contentView = glass.window?.contentView,
              let root = contentView.layer else {
            return []
        }
        // Match by frame in window-content coords. CASDFElementLayer frames in
        // their own parent-layer coord system can collide between two
        // containers (each container has surfaces with the same local rect),
        // but their absolute window position is always unique to the visible
        // glass surface. Convert both the target rect and the candidate
        // layer's frame into the same window-relative space.
        let target = contentView.convert(glass.bounds, from: glass)
        guard target.width > 0, target.height > 0 else { return [] }
        let result = collectSDFElementLayers(in: root, matchingWindowFrame: target, rootLayer: root)
        if !result.isEmpty {
            cachedShadowLayers[key] = result
        }
        return result
    }

    private func collectSDFElementLayers(in layer: CALayer, matchingWindowFrame target: NSRect, rootLayer: CALayer, tolerance: CGFloat = 1.0) -> [CALayer] {
        var result: [CALayer] = []
        guard let sdfElementLayerClass = GlassTouchEffect.sdfElementLayerClass else { return result }
        walk(layer) { node in
            guard object_getClass(node) == sdfElementLayerClass else { return }
            let f = node.convert(node.bounds, to: rootLayer)
            if abs(f.origin.x - target.origin.x) < tolerance,
               abs(f.origin.y - target.origin.y) < tolerance,
               abs(f.size.width - target.size.width) < tolerance,
               abs(f.size.height - target.size.height) < tolerance {
                result.append(node)
            }
        }
        return result
    }

    private func walk(_ layer: CALayer, _ visit: (CALayer) -> Void) {
        visit(layer)
        for sub in layer.sublayers ?? [] {
            walk(sub, visit)
        }
    }

    private func ensureCenterAnchor(of layer: CALayer) {
        let target = CGPoint(x: 0.5, y: 0.5)
        guard layer.anchorPoint != target else { return }
        var pos = layer.position
        pos.x += (target.x - layer.anchorPoint.x) * layer.bounds.width
        pos.y += (target.y - layer.anchorPoint.y) * layer.bounds.height
        layer.anchorPoint = target
        layer.position = pos
    }

    public func setIsTracking(_ value: Bool, animated: Bool = true) {
        let next = State(isTracking: value, stretchVector: value ? state.stretchVector : .zero)
        guard state != next else { return }
        if value {
            cachedShadowLayers.removeAll()
        }
        state = next
        applyCurrentTransform(animated: animated)
    }

    public func setStretchVector(_ vector: CGPoint, animated: Bool = false) {
        let next = State(isTracking: state.isTracking, stretchVector: vector)
        guard state != next else { return }
        state = next
        applyCurrentTransform(animated: animated)
    }

    public func reset(animated: Bool = false) {
        let next = State(isTracking: false, stretchVector: .zero)
        state = next
        applyCurrentTransform(animated: animated)
        cachedShadowLayers.removeAll()
    }
}
