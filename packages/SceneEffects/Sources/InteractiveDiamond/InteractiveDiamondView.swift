import Cocoa
import Metal
import TGUIKit

public final class InteractiveDiamondView: View {
    public enum Appearance: UInt32, CaseIterable, Sendable {
        case blue = 0
        case white = 1
        case cool = 2
    }

    public enum ExpansionStyle {
        case centered
        case downward
        case wallet
    }

    public enum AnimationMode: Equatable {
        case continuous
        case lottie(loop: Bool)
    }

    public struct MotionState {
        public let rotation: CGFloat
        public let time: CFTimeInterval
        public let transferEnergy: CGFloat?
    }

    public struct RefractionGeometry {
        public var center: CGPoint
        public var hull: [CGPoint]
        public let strength: CGFloat
        public let rotation: Float
    }

    public struct RefractionSource: Equatable {
        let texture: MTLTexture
        let uv: SIMD4<Float>
        let rect: CGRect
        let preservesColors: Bool

        public init(texture: MTLTexture, uv: SIMD4<Float>, rect: CGRect, preservesColors: Bool = false) {
            self.texture = texture
            self.uv = uv
            self.rect = rect
            self.preservesColors = preservesColors
        }

        public static func ==(lhs: RefractionSource, rhs: RefractionSource) -> Bool {
            return lhs.texture === rhs.texture && lhs.uv == rhs.uv && lhs.rect == rhs.rect
                && lhs.preservesColors == rhs.preservesColors
        }
    }

    private struct Expansion {
        let start: CFTimeInterval
        let from: CGFloat
        let holding: Bool
    }

    let diamondLayer = InteractiveDiamondLayer(backgroundStars: false)
    private var isHolding = false
    public private(set) var isExpanded = false
    public var onExpansionChanged: ((Bool) -> Void)?
    public var onLanding: ((CGFloat) -> Void)?
    public var onMotionUpdated: ((MotionState?) -> Void)?
    private var landingFeedback: DispatchWorkItem?
    private var restingSize = CGSize.zero
    private var diamondWidth: CGFloat = 0.0
    private var walletScale: CGFloat = 1.0
    private var walletLeftInset: CGFloat = .greatestFiniteMagnitude
    private var expandedSize = CGSize.zero
    private var transferSize = CGSize.zero
    private var completingTransferSize = CGSize.zero
    private var openingSize = CGSize.zero
    private var hitSide: CGFloat = 0.0
    private var dragScale: CGFloat = 0.0
    private var expansionStyle: ExpansionStyle = .centered
    private var expandedCenter: CGPoint?
    private var refractionSource: RefractionSource?
    private var animationMode: AnimationMode = .continuous
    private var expansion: Expansion?
    private var grip: CGFloat = 0.0
    private var isTracking = false
    private var initialZoom: Float?
    private var magnification: CGFloat = 0.0
    private var isWalletTransfer = false
    private var openingScale: CGFloat?

    public var isInteractionEnabled = true {
        didSet {
            if !self.isInteractionEnabled { self.cancelInteraction() }
        }
    }

    public var starContainer: CGRect? {
        didSet {
            if self.starContainer != oldValue {
                self.applyExpansion()
            }
        }
    }

    var starCanvasSize: CGSize {
        let base = self.completingTransferSize
        guard let container = self.starContainer else {
            return base
        }
        let position = self.diamondLayer.position
        let width = max(base.width, 2.0 * max(position.x - container.minX, container.maxX - position.x))
        let height = max(base.height, 2.0 * max(position.y - container.minY, container.maxY - position.y))
        return CGSize(width: ceil(width), height: ceil(height))
    }

    public var isRenderingEnabled: Bool {
        get { return self.diamondLayer.isRenderingEnabled }
        set {
            if !newValue { self.cancelInteraction() }
            self.diamondLayer.isRenderingEnabled = newValue
        }
    }

    public var isPlaying: Bool {
        return self.diamondLayer.isPlaying
    }

    public func playOnce() {
        guard self.animationMode == .lottie(loop: false) else { return }
        self.diamondLayer.resetAnimation()
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
        self.diamondLayer.isRenderingEnabled = false
        var style = DiamondStyle()
        style.animationMode = .continuous
        style.rotationSpeed = 2 * .pi / 26
        style.swayScale = 1
        style.backgroundStars = false
        style.mainSparkleOnRotation = true
        style.releaseTilt = 2.6
        self.diamondLayer.update(style: style)
        self.layer?.addSublayer(self.diamondLayer)
        self.diamondLayer.onHold = { [weak self] holding in
            self?.setHolding(holding)
        }
        self.diamondLayer.onPoseUpdated = { [weak self] pose in
            guard let self else { return }
            if self.expansionStyle != .centered {
                self.applyExpansion()
            } else {
                self.updateExpansion(at: CACurrentMediaTime())
            }
            if let onMotionUpdated = self.onMotionUpdated {
                if let state = self.diamondLayer.animationState {
                    onMotionUpdated(MotionState(
                        rotation: CGFloat(pose.yaw),
                        time: CFTimeInterval(state.time),
                        transferEnergy: state.transferEnergy.map { CGFloat($0) }
                    ))
                } else {
                    onMotionUpdated(nil)
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.reduceMotionChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.applicationWillResignActive), name: NSApplication.willResignActiveNotification, object: nil)
        self.reduceMotionChanged()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.landingFeedback?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reduceMotionChanged() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.diamondLayer.setReduceMotion(reduceMotion)
        if reduceMotion {
            self.expansion = nil
            self.grip = self.isHolding ? 1.0 : 0.0
            self.diamondLayer.resetGrowth()
            self.applyExpansion()
        }
    }

    @objc private func applicationWillResignActive() {
        self.cancelInteraction()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.diamondLayer.isInHierarchy = self.window != nil
        if self.window == nil { self.cancelInteraction() }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard self.isInteractionEnabled, self.animationMode == .continuous, !self.isHidden, let superview = self.superview else {
            return nil
        }
        let local = self.convert(point, from: superview)
        if self.expansionStyle == .wallet {
            let radius = self.restingSize.width * (30.0 * 0.9 / 96.0) * self.walletScale
            return hypot(local.x - self.diamondLayer.position.x, local.y - self.diamondLayer.position.y) <= radius ? self : nil
        }
        let area = CGRect(x: self.bounds.midX - self.hitSide / 2.0, y: self.bounds.midY - self.hitSide / 2.0, width: self.hitSide, height: self.hitSide)
        return area.contains(local) ? self : nil
    }

    public override func mouseDown(with event: NSEvent) {
        guard let window = self.window, !self.isTracking else { return }
        self.isTracking = true
        var previous = self.convert(event.locationInWindow, from: nil)
        let pressStart = (position: previous, time: CACurrentMediaTime())
        var samples: [(x: CGFloat, time: CFTimeInterval)] = [(previous.x, pressStart.time)]
        self.cancelLandingFeedback()
        self.diamondLayer.updateDrag(state: .began)
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .pressure]) {
            guard self.isTracking else { break }
            if next.type == .pressure { continue }
            let wasHolding = self.isHolding
            let releasePower = CGFloat(self.diamondLayer.refractionStrength)
            let now = CACurrentMediaTime()
            let position = self.convert(next.locationInWindow, from: nil)
            samples.append((position.x, now))
            while samples.count > 2 && samples[0].time < now - 0.08 {
                samples.removeFirst()
            }
            let interval = CGFloat(max(now - samples[0].time, 1.0 / 240.0))
            let velocity = CGPoint(x: (position.x - samples[0].x) / interval, y: 0.0)
            let translation = CGPoint(x: position.x - previous.x, y: position.y - previous.y)
            previous = position
            let state: NSGestureRecognizer.State = next.type == .leftMouseUp ? .ended : .changed
            let tapDirection: Float?
            if state == .ended, self.diamondLayer.diamondStyle.tapToSpin, now - pressStart.time < 0.25,
               hypot(position.x - pressStart.position.x, position.y - pressStart.position.y) < 10.0 {
                let centerX = self.expansionStyle == .wallet ? self.diamondLayer.position.x : self.bounds.midX
                tapDirection = position.x < centerX ? -1.0 : 1.0
            } else {
                tapDirection = nil
            }
            self.diamondLayer.updateDrag(
                state: state, translation: translation, velocity: velocity,
                scale: self.expansionStyle == .wallet ? min(self.restingSize.width, self.restingSize.height) : self.dragScale,
                releaseImpulse: self.expansionStyle == .wallet ? nil : 3.0 * 6.5,
                allowsFlingBurst: self.expansionStyle == .wallet, tapSpinDirection: tapDirection
            )
            if state == .ended {
                if wasHolding, self.expansionStyle != .wallet {
                    self.scheduleLandingFeedback(power: releasePower)
                }
                break
            }
        }
        self.isTracking = false
    }

    func scheduleLandingFeedback(power: CGFloat) {
        self.cancelLandingFeedback()
        guard power > 0.0, self.onLanding != nil, !self.isHolding else { return }
        let landing = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.landingFeedback = nil
            guard self.window != nil, self.isRenderingEnabled, self.isInteractionEnabled,
                  !self.isHolding, NSApp.isActive else { return }
            self.onLanding?(min(1.0, power))
        }
        self.landingFeedback = landing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: landing)
    }

    private func cancelLandingFeedback() {
        self.landingFeedback?.cancel()
        self.landingFeedback = nil
    }

    public override func magnify(with event: NSEvent) {
        if !self.updateMagnification(phase: event.phase, delta: event.magnification) {
            super.magnify(with: event)
        }
    }

    func updateMagnification(phase: NSEvent.Phase, delta: CGFloat) -> Bool {
        guard self.expansionStyle == .wallet, self.isInteractionEnabled, self.animationMode == .continuous else {
            return false
        }
        switch phase {
        case .began:
            self.initialZoom = self.diamondLayer.zoom
            self.magnification = 0.0
        case .ended, .cancelled:
            self.initialZoom = nil
            return true
        default:
            break
        }
        guard let initialZoom = self.initialZoom else { return true }
        self.magnification += delta
        self.diamondLayer.zoom = initialZoom * Float(1.0 + self.magnification)
        return true
    }

    private func setHolding(_ holding: Bool) {
        guard self.isHolding != holding else { return }
        let now = CACurrentMediaTime()
        self.updateExpansion(at: now)
        self.isHolding = holding
        if self.expansionStyle != .centered {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.diamondLayer.resetGrowth()
            }
            self.applyExpansion()
            return
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.expansion = nil
            self.grip = holding ? 1.0 : 0.0
        } else {
            self.expansion = Expansion(start: now, from: self.grip, holding: holding)
        }
        self.applyExpansion()
    }

    private func updateExpansion(at time: CFTimeInterval) {
        guard let expansion = self.expansion else { return }
        let elapsed = max(0.0, time - expansion.start)
        if expansion.holding {
            let t = min(1.0, elapsed / 0.46)
            let u = t * t * (3.0 - 2.0 * t)
            let settle = 1.0 - exp(-5.6 * u) * (cos(6.2 * u) + 5.6 / 6.2 * sin(6.2 * u))
            self.grip = expansion.from + (1.0 - expansion.from) * CGFloat(settle)
            if t == 1.0 {
                self.grip = 1.0
                self.expansion = nil
            }
        } else {
            self.grip = expansion.from * CGFloat(exp(-4.2 * elapsed) * cos(7.0 * elapsed))
            if elapsed >= 1.96 {
                self.grip = 0.0
                self.expansion = nil
            }
        }
        self.applyExpansion()
    }

    private func applyExpansion() {
        if self.isWalletTransfer {
            self.diamondLayer.usesHighFrameRate = true
            self.diamondLayer.interactionScale = 1.0
            self.diamondLayer.refractionStrength = 0.0
            self.diamondLayer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            self.diamondLayer.renderSize = CGSize(width: 150.0, height: 150.0)
            return
        }
        let expanded = self.isHolding || self.expansion != nil || self.diamondLayer.isGrowthAnimating
        self.diamondLayer.usesHighFrameRate = expanded || self.openingScale != nil || self.diamondLayer.hasTransferAnimation
        self.diamondLayer.interactionScale = (self.expansionStyle != .centered ? 1.0 : Float(1.0 + 2.75 * self.grip)) * Float(self.openingScale ?? 1.0)
        let style = self.diamondLayer.diamondStyle
        let refractionStrength = self.expansionStyle != .centered && style.dragGrow != 1.0
            ? (self.diamondLayer.pose.grow - 1.0) / (style.dragGrow - 1.0)
            : Float(self.grip)
        self.diamondLayer.refractionStrength = min(1.0, max(0.0, refractionStrength))
        let restingCenter = CGPoint(x: self.restingSize.width * 0.5, y: self.restingSize.height * 0.5)
        let expandedCenter = self.expandedCenter ?? restingCenter
        self.diamondLayer.position = CGPoint(
            x: restingCenter.x + (expandedCenter.x - restingCenter.x) * CGFloat(refractionStrength),
            y: restingCenter.y + (expandedCenter.y - restingCenter.y) * CGFloat(refractionStrength)
        )
        if self.expansionStyle == .wallet {
            let halfWidth = self.diamondWidth * CGFloat(self.diamondLayer.pose.grow * self.diamondLayer.zoom) * self.walletScale * 0.55
            self.diamondLayer.position.x = restingCenter.x + max(0.0, halfWidth - self.walletLeftInset)
        }
        self.updateRefractionPosition()
        if self.openingScale != nil {
            self.diamondLayer.renderSize = self.openingSize
        } else if self.diamondLayer.isCompletingTransfer || self.diamondLayer.hasStarBursts {
            self.diamondLayer.renderSize = self.starCanvasSize
        } else if expanded {
            self.diamondLayer.renderSize = self.expandedSize
        } else if self.diamondLayer.hasTransferAnimation {
            self.diamondLayer.renderSize = self.transferSize
        } else {
            self.diamondLayer.renderSize = self.restingSize
        }
        self.diamondLayer.setNeedsUpdate()
        if self.isExpanded != expanded {
            self.isExpanded = expanded
            self.onExpansionChanged?(expanded)
        }
    }

    public func cancelInteraction() {
        self.initialZoom = nil
        self.cancelLandingFeedback()
        self.diamondLayer.cancelTapSpin()
        guard self.isHolding || self.expansion != nil || self.isTracking || self.diamondLayer.isGrowthAnimating else {
            self.applyExpansion()
            return
        }
        if self.isHolding { self.diamondLayer.updateDrag(state: .cancelled) }
        self.isTracking = false
        self.isHolding = false
        self.expansion = nil
        self.grip = 0.0
        self.diamondLayer.resetGrowth()
        self.applyExpansion()
    }

    public func updateWalletTilt(pitch: CGFloat, roll: CGFloat, scale: CGFloat, leftInset: CGFloat) {
        guard self.expansionStyle == .wallet else { return }
        self.walletScale = scale
        self.walletLeftInset = leftInset
        var style = self.diamondLayer.diamondStyle
        style.tilt = Float(-pitch * 2.8)
        style.lean = Float(roll * 2.6)
        style.widthPoints = Float(self.diamondWidth * scale)
        self.diamondLayer.update(style: style)
        self.applyExpansion()
    }

    public func updateOpeningScale(_ scale: CGFloat?) {
        guard self.openingScale != scale else { return }
        self.openingScale = scale
        self.applyExpansion()
    }

    public func spin(_ velocity: Float, decay: Float) {
        self.diamondLayer.spin(velocity, decay: decay)
    }

    public func prepareForWalletTransfer() {
        self.cancelInteraction()
        self.isWalletTransfer = true
        self.openingScale = nil
        self.isInteractionEnabled = false
        self.onExpansionChanged = nil
        self.onLanding = nil
        self.onMotionUpdated = nil
        self.updateRefractionSource(nil)
        self.frame = CGRect(x: self.frame.midX - 75.0, y: self.frame.midY - 75.0, width: 150.0, height: 150.0)
        self.applyExpansion()
    }

    public func setTint(_ color: NSColor?, amount: CGFloat) {
        var style = self.diamondLayer.diamondStyle
        if let color, amount > 0.001, let converted = color.usingColorSpace(self.window?.colorSpace ?? .sRGB) {
            style.tint = SIMD4(Float(converted.redComponent), Float(converted.greenComponent), Float(converted.blueComponent), Float(min(1.0, amount)))
        } else {
            style.tint = .zero
        }
        guard style != self.diamondLayer.diamondStyle else {
            return
        }
        self.diamondLayer.update(style: style)
    }

    public func updateWalletTransfer(width: CGFloat, rotationSpeed: Float, completion: Bool, isDark: Bool, appearance: Appearance = .blue) {
        self.diamondLayer.lightBackground = !isDark
        var style = self.diamondLayer.diamondStyle
        let startsCompletion = completion && !style.backgroundStars
        style.animationMode = .continuous
        style.appearance = appearance
        style.widthPoints = Float(width)
        style.rotationSpeed = rotationSpeed
        style.swayScale = 2.4
        style.floatAmplitude = 0.0
        style.backgroundStars = completion
        style.steadyStars = false
        style.starZoom = 0.55
        style.starEmission = 0.3
        style.burstSize = 0.7
        style.burstFadeInDuration = 0.0
        self.diamondLayer.update(style: style, preservingMotion: true)
        if startsCompletion {
            self.spin(12.0, decay: 0.7)
            self.diamondLayer.emitStarBurst()
        }
        self.applyExpansion()
    }

    public func pushFromBelow(strength: Float = 1.0) {
        self.diamondLayer.pushFromBelow(strength: strength)
    }

    public func updateTransferState(isSending: Bool, animateCompletion: Bool) {
        self.diamondLayer.updateTransferState(isSending: isSending, animateCompletion: animateCompletion)
    }

    public func beginReceivingTransfer(at startTime: CFTimeInterval, completionDelay: Double) {
        self.diamondLayer.beginReceivingTransfer(at: startTime, completionDelay: Float(completionDelay))
    }

    public func endReceivingTransfer() {
        self.diamondLayer.endReceivingTransfer()
    }

    public func updateRefractionSource(_ source: RefractionSource?) {
        guard self.refractionSource != source else { return }
        self.refractionSource = source
        self.updateRefractionPosition()
        self.diamondLayer.setNeedsUpdate()
    }

    private func updateRefractionPosition() {
        guard let source = self.refractionSource else {
            self.diamondLayer.refractionSource = nil
            return
        }
        self.diamondLayer.refractionSource = RefractionSource(
            texture: source.texture,
            uv: source.uv,
            rect: source.rect.offsetBy(
                dx: self.restingSize.width * 0.5 - self.diamondLayer.position.x,
                dy: self.restingSize.height * 0.5 - self.diamondLayer.position.y
            ),
            preservesColors: source.preservesColors
        )
    }

    public func update(size: CGSize, diamondWidth: CGFloat, isVisible: Bool, lightBackground: Bool, appearance: Appearance = .blue, expansionStyle: ExpansionStyle = .centered, expandedCenter: CGPoint? = nil, animationMode: AnimationMode = .continuous, animateOnAppear: Bool = false, tapToSpin: Bool = false, metricsScale: CGFloat = 1.0) {
        let returningFromFlight = self.isWalletTransfer
        self.isWalletTransfer = false
        if self.animationMode != animationMode {
            self.cancelInteraction()
            self.animationMode = animationMode
        }
        if self.expansionStyle != expansionStyle {
            self.cancelInteraction()
            self.expansionStyle = expansionStyle
        }
        let isInteractive = animationMode == .continuous
        let downward = expansionStyle == .downward
        let wallet = expansionStyle == .wallet
        let scale = metricsScale
        self.restingSize = size
        self.diamondWidth = diamondWidth
        self.expandedCenter = expandedCenter
        self.expandedSize = CGSize(width: 220.0 * scale, height: 220.0 * scale)
        self.transferSize = CGSize(width: 96.0 * scale, height: 96.0 * scale)
        self.completingTransferSize = CGSize(width: 240.0 * scale, height: 240.0 * scale)
        self.openingSize = CGSize(width: 320.0 * scale, height: 320.0 * scale)
        self.hitSide = 64.0 * scale
        self.dragScale = 220.0 * scale
        var style = self.diamondLayer.diamondStyle
        if returningFromFlight {
            style.rotationSpeed = 2.0 * .pi / 26.0
            let defaults = DiamondStyle()
            style.backgroundStars = false
            style.steadyStars = defaults.steadyStars
            style.starZoom = defaults.starZoom
            style.starEmission = defaults.starEmission
            style.burstSize = defaults.burstSize
            style.burstFadeInDuration = defaults.burstFadeInDuration
        }
        style.animateOnAppear = animateOnAppear
        switch animationMode {
        case .continuous:
            style.animationMode = .continuous
            style.referenceAnimationLoops = true
        case let .lottie(loop):
            style.animationMode = .reference
            style.referenceAnimationLoops = loop
        }
        style.swayScale = isInteractive ? 1.0 : 0.0
        style.floatAmplitude = isInteractive && downward ? Float(1.5 * scale) : 0.0
        style.floatPeriod = 3.2
        self.diamondLayer.highlightBoost = isInteractive ? 0.4 : 0.0
        style.mainSparkleOnRotation = isInteractive
        style.widthPoints = Float(diamondWidth * (wallet ? self.walletScale : 1.0))
        style.appearance = appearance
        style.widthCompensation = !wallet
        style.dragGrow = wallet ? 2.6 : (downward ? 3.0 : 1.0)
        style.growShift = downward && expandedCenter == nil ? 12.0 : 0.0
        style.growDamping = expansionStyle != .centered ? 0.62 : 0.42
        style.releaseDecay = expansionStyle != .centered ? 1.1 : 0.0
        style.releaseTilt = expansionStyle != .centered ? 0.0 : 2.6
        style.tapToSpin = isInteractive && tapToSpin
        style.starOpacity = wallet ? 0.0 : 1.0
        style.rightwardStars = wallet
        style.starReferenceSize = wallet ? 240.0 : 0.0
        if !wallet {
            style.tilt = 0.0
            style.lean = 0.0
        }
        self.diamondLayer.update(style: style)
        self.diamondLayer.lightBackground = expansionStyle == .centered && lightBackground
        self.isRenderingEnabled = isVisible
        self.applyExpansion()
    }
}
