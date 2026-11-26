import Cocoa
import Metal
import MetalEngine
import TGUIKit

struct DiamondStyle: Equatable {
    typealias Appearance = InteractiveDiamondView.Appearance
    var appearance: Appearance = .blue
    var tint: SIMD4<Float> = .zero
    enum AnimationMode: String, CaseIterable, Sendable {
        case continuous
        case reference
        case entrance
    }
    var animationMode: AnimationMode = .entrance
    var referenceAnimationLoops: Bool = true
    var animateOnAppear: Bool = false
    var rotationSpeed: Float = 2 * .pi / 18 * 1.70775
    var isRotating: Bool = true
    var sparkles: Bool = true
    var mainSparkleOnRotation: Bool = false
    var backgroundStars: Bool = true
    var widthCompensation: Bool = true
    var refraction: Float = 0.72
    var brightness: Float = 1
    var zoom: Float = 0.72
    var whiten: Float = 0
    var swayScale: Float = 0
    var floatAmplitude: Float = 0
    var floatPeriod: Float = 3.2
    var tilt: Float = 0
    var lean: Float = 0
    var releaseDecay: Float = 0
    var releaseTilt: Float = 0
    var tapToSpin: Bool = false
    var dragGrow: Float = 1
    var growShift: Float = 0
    var verticalOffset: Float = 0
    var growDamping: Float = 0.42
    var widthPoints: Float = 0
    var starOpacity: Float = 1
    var starZoom: Float = 1
    var starReferenceSize: Float = 0
    var starEmission: Float = 1
    var rightwardStars: Bool = false
    var burstSize: Float = 1
    var burstFadeInDuration: Float = 0.5
    var steadyStars: Bool = true
    init() {}
}

struct DiamondPose {
    let yaw: Float
    let pitch: Float
    let grow: Float
    let shift: Float
}

public final class InteractiveDiamondLayer: MetalEngineSubjectLayer, MetalEngineSubject {
    private final class CompositeState: RenderToLayerState {
        let pipelineState: MTLRenderPipelineState
        private let device: MTLDevice
        private let descriptor: MTLRenderPipelineDescriptor
        private lazy var hdrPipelineState: MTLRenderPipelineState? = {
            let descriptor = self.descriptor.copy() as! MTLRenderPipelineDescriptor
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            return try? self.device.makeRenderPipelineState(descriptor: descriptor)
        }()

        func pipelineState(for pixelFormat: RenderLayerSpec.PixelFormat) -> MTLRenderPipelineState? {
            return pixelFormat == .rgba16Float ? self.hdrPipelineState : self.pipelineState
        }

        required init?(device: MTLDevice) {
            guard let library = gramDiamondMetalLibrary(device: device),
                  let vertex = library.makeFunction(name: "gramDiamondCompositeVertex"),
                  let fragment = library.makeFunction(name: "gramDiamondCompositeFragment") else {
                return nil
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
                return nil
            }
            self.pipelineState = pipelineState
            self.device = device
            self.descriptor = descriptor
        }
    }

    private final class RenderTargets {
        let size: RenderSize
        let color: MTLTexture
        let multisampleColor: MTLTexture?
        let depth: MTLTexture

        init?(device: MTLDevice, size: RenderSize, sampleCount: Int, pixelFormat: MTLPixelFormat) {
            self.size = size
            let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: size.width, height: size.height, mipmapped: false)
            colorDescriptor.storageMode = .private
            colorDescriptor.usage = [.renderTarget, .shaderRead]
            guard let color = device.makeTexture(descriptor: colorDescriptor) else {
                return nil
            }
            self.color = color

            if sampleCount > 1 {
                colorDescriptor.textureType = .type2DMultisample
                colorDescriptor.sampleCount = sampleCount
                colorDescriptor.usage = .renderTarget
                guard let multisampleColor = device.makeTexture(descriptor: colorDescriptor) else {
                    return nil
                }
                self.multisampleColor = multisampleColor
            } else {
                self.multisampleColor = nil
            }

            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: size.width, height: size.height, mipmapped: false)
            depthDescriptor.storageMode = .private
            depthDescriptor.usage = .renderTarget
            depthDescriptor.sampleCount = sampleCount
            if sampleCount > 1 {
                depthDescriptor.textureType = .type2DMultisample
            }
            guard let depth = device.makeTexture(descriptor: depthDescriptor) else {
                return nil
            }
            self.depth = depth
        }
    }

    public var internalData: MetalEngineSubjectInternalData?
    var onHold: ((Bool) -> Void)?
    var onPoseUpdated: ((DiamondPose) -> Void)?
    public var lightBackground = false
    var interactionScale: Float = 1
    var starOffset: CGPoint = .zero
    var refractionSource: InteractiveDiamondView.RefractionSource?
    var refractionStrength: Float = 0
    var onRefractionUpdated: ((InteractiveDiamondView.RefractionGeometry?) -> Void)?
    var highlightBoost: Float = 0
    private var appliedHighlightBoost: Float = 0
    private var isHighDynamicRange = false
    var usesHighFrameRate = false {
        didSet {
            guard self.usesHighFrameRate != oldValue else { return }
            self.displayLink?.invalidate()
            self.displayLink = nil
            self.updateAnimationState()
        }
    }

    var renderSize: CGSize? {
        didSet {
            if self.renderSize != oldValue { self.setNeedsUpdate() }
        }
    }

    var isRenderingEnabled = true {
        didSet {
            if self.isRenderingEnabled != oldValue {
                self.updateAnimationState()
            }
        }
    }
    private(set) var diamondStyle = DiamondStyle()
    private var hasCompletedReferenceAnimation: Bool {
        return self.diamondStyle.animationMode == .reference && !self.diamondStyle.referenceAnimationLoops
            && self.elapsed >= DiamondReferenceHighlights.lastFrameTime
    }

    var isPlaying: Bool {
        return self.displayLink != nil && !self.hasCompletedReferenceAnimation
    }
    private var isSendingTransfer = false
    private var transferAnimation: DiamondTransferAnimation?
    private var receivingTransfer: (startTime: CFTimeInterval, completionDelay: Float)?

    var hasTransferAnimation: Bool {
        return !self.reduceMotion && self.transferAnimation != nil
    }

    var isCompletingTransfer: Bool {
        return !self.reduceMotion && self.transferAnimation?.phase == .completion
    }

    var hasStarBursts: Bool {
        return !self.reduceMotion && !self.starBursts.isEmpty
    }

    var animationState: (time: Float, transferEnergy: Float?)? {
        guard self.isInHierarchy, self.isRenderingEnabled, !self.reduceMotion else {
            return nil
        }
        return (self.elapsed, self.transferAnimation?.presentation(at: self.elapsed).energy)
    }

    private var effectiveStyle: DiamondStyle {
        var style = self.diamondStyle
        if !self.reduceMotion && self.starBursts.contains(where: { $0.isFromTap }) {
            style.backgroundStars = true
            style.steadyStars = false
        }
        if !self.reduceMotion, let animation = self.transferAnimation {
            let presentation = animation.presentation(at: self.elapsed)
            style.rotationSpeed *= 1 + 5 * presentation.energy
            style.swayScale *= 1 + 1.4 * presentation.energy
            style.widthPoints *= presentation.scale
            style.growShift *= presentation.scale
            style.verticalOffset += presentation.offset
            if animation.phase == .completion {
                style.backgroundStars = true
                style.steadyStars = false
                style.starZoom = 0.62
                style.starEmission = 0.3
                style.burstSize = 0.8
                style.burstFadeInDuration = 0.03
            }
        }
        return style
    }

    var zoom: Float {
        get { return self.motion.zoom }
        set {
            self.motion.zoom = min(1.6, max(0.6, newValue))
            self.onPoseUpdated?(self.pose)
            self.setNeedsUpdate()
        }
    }

    var pose: DiamondPose {
        return DiamondPose(yaw: self.motion.renderedYaw, pitch: self.motion.pitch,
            grow: self.grow * self.interactionScale, shift: self.diamondStyle.growShift * (self.grow * self.interactionScale - 1))
    }

    private var renderTargets: RenderTargets?
    private var motion = DiamondMotion()
    private var grow: Float = 1
    private var growVelocity: Float = 0
    var isGrowthAnimating: Bool {
        return self.grow != 1 || self.growVelocity != 0
    }

    func resetGrowth() {
        self.grow = self.motion.isDragging ? self.diamondStyle.dragGrow : 1
        self.growVelocity = 0
        self.setNeedsUpdate()
    }

    private var starBursts: [DiamondStarBurst] = []
    private var nextBurstSeed: UInt32 = 1
    private var tapStreak = 0
    private var lastTapTime: CFTimeInterval?
    private var elapsed: Float = 0
    private var lastTime: CFTimeInterval?
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var reduceMotion = false
    private var didAnimateAppearance = false

    public override convenience init() {
        self.init(backgroundStars: true)
    }

    public init(backgroundStars: Bool) {
        var style = DiamondStyle()
        style.backgroundStars = backgroundStars
        self.diamondStyle = style
        super.init()

        self.isOpaque = false
        if self.diamondStyle.backgroundStars && self.diamondStyle.animationMode == .entrance {
            self.starBursts.append(DiamondStarBurst(startTime: 0, seed: 0))
        }
        self.didEnterHierarchy = { [weak self] in
            self?.updateAnimationState()
        }
        self.didExitHierarchy = { [weak self] in
            self?.updateAnimationState()
        }
    }

    public override init(layer: Any) {
        super.init(layer: layer)
        if let layer = layer as? InteractiveDiamondLayer {
            self.diamondStyle = layer.diamondStyle
            self.isSendingTransfer = layer.isSendingTransfer
            self.transferAnimation = layer.transferAnimation
            self.motion = layer.motion
            self.grow = layer.grow
            self.growVelocity = layer.growVelocity
            self.interactionScale = layer.interactionScale
            self.starOffset = layer.starOffset
            self.refractionSource = layer.refractionSource
            self.refractionStrength = layer.refractionStrength
            self.highlightBoost = layer.highlightBoost
            self.appliedHighlightBoost = layer.appliedHighlightBoost
            self.isHighDynamicRange = layer.isHighDynamicRange
            self.usesHighFrameRate = layer.usesHighFrameRate
            self.renderSize = layer.renderSize
            self.isRenderingEnabled = layer.isRenderingEnabled
            self.starBursts = layer.starBursts
            self.nextBurstSeed = layer.nextBurstSeed
            self.tapStreak = layer.tapStreak
            self.lastTapTime = layer.lastTapTime
            self.elapsed = layer.elapsed
            self.lightBackground = layer.lightBackground
            self.reduceMotion = layer.reduceMotion
            self.didAnimateAppearance = layer.didAnimateAppearance
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.displayLink?.invalidate()
    }

    func update(style: DiamondStyle, preservingMotion: Bool = false) {
        guard self.diamondStyle != style else { return }
        if self.lastTime != nil {
            self.updateMotion(at: CACurrentMediaTime())
        }
        let previous = self.diamondStyle
        self.diamondStyle = style
        if !style.tapToSpin {
            self.cancelTapSpin()
        }
        if style.starOpacity <= 0.001 {
            self.starBursts.removeAll()
        } else if !style.backgroundStars && !self.isCompletingTransfer {
            self.starBursts.removeAll(where: { !$0.isFromTap })
        }
        let modeChanged = previous.animationMode != style.animationMode || previous.referenceAnimationLoops != style.referenceAnimationLoops
        if modeChanged && !preservingMotion {
            self.resetAnimation()
        } else {
            self.updateMotionStyle()
            if style.animationMode == .reference && previous.appearance != style.appearance {
                self.motion.changeReferenceAppearance(from: previous.appearance, to: style.appearance, time: self.elapsed)
            }
            self.onPoseUpdated?(self.pose)
            if modeChanged {
                self.updateAnimationState()
            }
            self.setNeedsUpdate()
        }
    }

    private func updateMotionStyle() {
        self.motion.mainSparkleOnRotation = self.diamondStyle.mainSparkleOnRotation
        self.motion.swayScale = self.diamondStyle.swayScale
        self.motion.tilt = self.diamondStyle.tilt
        self.motion.targetLean = self.diamondStyle.lean
        self.motion.releaseDecay = self.diamondStyle.releaseDecay
        self.motion.releaseTilt = self.diamondStyle.releaseTilt
    }

    func resetAnimation() {
        let wasDragging = self.motion.isDragging
        let externalYaw = self.motion.externalYaw
        self.cancelTapSpin()
        self.motion = DiamondMotion()
        self.motion.externalYaw = externalYaw
        self.updateMotionStyle()
        self.grow = 1
        self.growVelocity = 0
        self.elapsed = 0
        self.lastTime = nil
        self.starBursts = self.diamondStyle.backgroundStars && self.diamondStyle.animationMode == .entrance
            ? [DiamondStarBurst(startTime: 0, seed: 0)] : []
        self.nextBurstSeed = 1
        if wasDragging { self.onHold?(false) }
        self.onPoseUpdated?(self.pose)
        self.updateAnimationState()
    }

    func spin(_ velocity: Float, decay: Float = 0.7) {
        guard self.isInHierarchy, self.isRenderingEnabled,
              !self.reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        self.updateMotion(at: CACurrentMediaTime())
        self.motion.spin(velocity, decay: decay)
        self.setNeedsUpdate()
    }

    func pushFromBelow(strength: Float) {
        guard self.isInHierarchy, self.isRenderingEnabled,
              !self.reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        self.updateMotion(at: CACurrentMediaTime())
        self.motion.pushFromBelow(strength: strength)
        self.updateAnimationState()
    }

    func emitStarBurst() {
        guard self.diamondStyle.backgroundStars, self.isInHierarchy, self.isRenderingEnabled,
              !self.reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        self.updateMotion(at: CACurrentMediaTime())
        self.addStarBurst()
        self.setNeedsUpdate()
    }

    func updateTransferState(isSending: Bool, animateCompletion: Bool) {
        guard self.isSendingTransfer != isSending else { return }
        if self.lastTime != nil {
            self.updateMotion(at: CACurrentMediaTime())
        }
        self.cancelTapSpin()
        self.isSendingTransfer = isSending
        self.cancelTransferCompletion()
        if isSending {
            self.transferAnimation = DiamondTransferAnimation(phase: .sending, startTime: self.elapsed)
        } else if animateCompletion && self.isInHierarchy && self.isRenderingEnabled
            && !self.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.transferAnimation = DiamondTransferAnimation(phase: .completion, startTime: self.elapsed)
            self.motion.spin(self.diamondStyle.rotationSpeed < 0 ? -11 : 11, decay: 0.7)
            self.addStarBurst(at: self.elapsed)
            self.addStarBurst(at: self.elapsed + 0.2)
        } else {
            self.transferAnimation = nil
        }
        self.onPoseUpdated?(self.pose)
        self.setNeedsUpdate()
    }

    func beginReceivingTransfer(at startTime: CFTimeInterval, completionDelay: Float) {
        self.cancelTapSpin()
        self.cancelTransferCompletion()
        self.receivingTransfer = (startTime, completionDelay)
        self.updateMotion(at: CACurrentMediaTime())
        self.setNeedsUpdate()
    }

    func endReceivingTransfer() {
        guard let receiving = self.receivingTransfer else { return }
        if CACurrentMediaTime() - receiving.startTime >= Double(receiving.completionDelay + DiamondTransferAnimation.completionDuration) {
            self.receivingTransfer = nil
            self.transferAnimation = nil
            self.starBursts.removeAll(where: { !$0.isFromTap })
        } else {
            self.cancelTransferCompletion()
        }
        self.onPoseUpdated?(self.pose)
        self.setNeedsUpdate()
    }

    private func cancelTransferCompletion() {
        guard self.transferAnimation?.phase == .completion || self.receivingTransfer != nil else { return }
        self.receivingTransfer = nil
        self.transferAnimation = nil
        self.starBursts.removeAll()
        self.motion.stopSpin()
    }

    func setReduceMotion(_ enabled: Bool) {
        guard self.reduceMotion != enabled else { return }
        self.reduceMotion = enabled
        self.motion.step(dt: 0, speed: self.diamondStyle.rotationSpeed, reduceMotion: self.reduceMotion, mode: self.diamondStyle.animationMode, time: self.elapsed, appearance: self.diamondStyle.appearance)
        self.updateAnimationState()
    }

    private func updateAnimationState() {
        let isVisible = self.isInHierarchy && self.isRenderingEnabled
        if isVisible && self.diamondStyle.animateOnAppear && !self.didAnimateAppearance {
            self.didAnimateAppearance = true
            if !self.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.motion.pushFromBelow()
            }
        }
        if isVisible && !self.reduceMotion && (!self.hasCompletedReferenceAnimation || self.motion.isAppearanceImpulseActive) {
            if self.displayLink == nil {
                self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: self.usesHighFrameRate ? .max : .fps(60), { [weak self] _ in
                    guard let self else { return }
                    self.updateMotion(at: CACurrentMediaTime())
                    if self.hasCompletedReferenceAnimation && !self.motion.isAppearanceImpulseActive {
                        self.updateAnimationState()
                    }
                    self.setNeedsUpdate()
                })
            }
        } else {
            self.displayLink?.invalidate()
            self.displayLink = nil
            self.lastTime = nil
            self.cancelTapSpin()
            if !isVisible {
                self.appliedHighlightBoost = 0
                self.updateDynamicRange(highDynamicRange: false)
                if self.renderTargets?.color.pixelFormat == .rgba16Float {
                    self.renderTargets = nil
                }
            }
            self.cancelTransferCompletion()
            if !isVisible && self.motion.isDragging {
                self.motion.end(at: CACurrentMediaTime(), cancelled: true)
                self.motion.step(dt: 0, speed: self.diamondStyle.rotationSpeed, reduceMotion: self.reduceMotion, mode: self.diamondStyle.animationMode, time: self.elapsed, appearance: self.diamondStyle.appearance)
                self.onHold?(false)
            }
            self.onPoseUpdated?(self.pose)
        }
        if isVisible {
            self.setNeedsUpdate()
        }
    }

    private func updateMotion(at time: CFTimeInterval) {
        let dt = Float(self.lastTime.map { min(max(0, time - $0), 0.05) } ?? 0)
        self.lastTime = time
        var animationDt = dt
        if self.diamondStyle.animationMode == .reference && !self.diamondStyle.referenceAnimationLoops {
            animationDt = min(dt, max(0, DiamondReferenceHighlights.lastFrameTime - self.elapsed))
        }
        if !self.reduceMotion {
            self.elapsed += animationDt
        }
        if let receiving = self.receivingTransfer {
            let t = Float(max(0.0, time - receiving.startTime))
            let completionTime = t - receiving.completionDelay
            if completionTime >= DiamondTransferAnimation.completionDuration {
                self.receivingTransfer = nil
                self.transferAnimation = nil
                self.starBursts.removeAll(where: { !$0.isFromTap })
            } else {
                let phase: DiamondTransferAnimation.Phase = completionTime >= 0 ? .completion : .receiving
                let didComplete = phase == .completion && self.transferAnimation?.phase != .completion
                self.transferAnimation = DiamondTransferAnimation(phase: phase, startTime: self.elapsed - (phase == .completion ? completionTime : t))
                if didComplete {
                    self.motion.spin((self.diamondStyle.rotationSpeed < 0 ? -11 : 11) * exp(-completionTime / 0.7), decay: 0.7)
                    self.addStarBurst(at: self.elapsed - completionTime)
                }
            }
        }
        if let animation = self.transferAnimation, animation.phase == .completion,
           self.elapsed - animation.startTime >= DiamondTransferAnimation.completionDuration {
            self.transferAnimation = nil
            self.starBursts.removeAll(where: { !$0.isFromTap })
        }
        self.starBursts.removeAll(where: { self.elapsed - $0.startTime >= DiamondStarBurst.lifetime })
        let style = self.effectiveStyle
        self.motion.swayScale = style.swayScale
        self.motion.tilt = style.tilt
        self.motion.targetLean = style.lean
        self.motion.step(dt: animationDt, speed: style.isRotating ? style.rotationSpeed : 0, reduceMotion: self.reduceMotion, mode: style.animationMode, time: self.elapsed, appearance: style.appearance)
        if dt > animationDt {
            self.motion.step(dt: dt - animationDt, speed: 0, reduceMotion: self.reduceMotion, mode: style.animationMode, time: self.elapsed, appearance: style.appearance)
        }
        if self.reduceMotion {
            self.grow = self.motion.isDragging ? self.diamondStyle.dragGrow : 1
            self.growVelocity = 0
        } else if self.diamondStyle.dragGrow != 1 || self.grow != 1 || self.growVelocity != 0 {
            let target: Float = self.motion.isDragging ? self.diamondStyle.dragGrow : 1
            var remaining = dt
            while remaining > 0 {
                let step = min(remaining, 1 / Float(240))
                self.growVelocity += ((target - self.grow) * 196 - 2 * self.diamondStyle.growDamping * 14 * self.growVelocity) * step
                self.grow += self.growVelocity * step
                remaining = max(0, remaining - step)
            }
            if abs(self.grow - target) < 0.0001 && abs(self.growVelocity) < 0.0001 {
                self.grow = target
                self.growVelocity = 0
            }
        }
        self.onPoseUpdated?(self.pose)
        let boostTarget = self.highlightBoost * self.refractionStrength
        self.appliedHighlightBoost += (boostTarget - self.appliedHighlightBoost) * (1 - exp(-dt / 0.25))
        if abs(self.appliedHighlightBoost - boostTarget) < 0.001 {
            self.appliedHighlightBoost = boostTarget
        }
    }

    @objc public func handleTap(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended, let view = gesture.view,
              self.isInHierarchy, self.isRenderingEnabled, !self.motion.isDragging,
              !self.reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let point = gesture.location(in: view)
        let horizontalOffset = point.x - view.bounds.midX
        guard abs(horizontalOffset) > 20.0 && abs(horizontalOffset) <= 180.0 else { return }

        self.updateMotion(at: CACurrentMediaTime())
        guard let triggersBurst = self.motion.tap(
            direction: horizontalOffset < 0 ? -1 : 1,
            speed: self.diamondStyle.isRotating ? self.diamondStyle.rotationSpeed : 0,
            mode: self.diamondStyle.animationMode,
            time: self.elapsed,
            appearance: self.diamondStyle.appearance
        ) else { return }
        if triggersBurst {
            self.addStarBurst()
        }
        self.setNeedsUpdate()
    }

    private func addStarBurst(at time: Float? = nil, isFromTap: Bool = false) {
        guard self.diamondStyle.starOpacity > 0.001 else { return }
        guard self.diamondStyle.backgroundStars || self.isCompletingTransfer || (isFromTap && self.diamondStyle.tapToSpin) else { return }
        if self.starBursts.count >= 3 {
            self.starBursts.removeFirst()
        }
        self.starBursts.append(DiamondStarBurst(startTime: time ?? self.elapsed, seed: self.nextBurstSeed, isFromTap: isFromTap))
        self.nextBurstSeed = (self.nextBurstSeed + 1) % 65536
    }

    private func tapSpin(direction: Float, at time: CFTimeInterval) {
        let current = self.motion.spinAtPress
        let sign: Float = abs(current) > 0.5 ? (current < 0 ? -1 : 1) : direction
        let top: Float = 16.0
        self.tapStreak = self.lastTapTime.map { time - $0 < 1.0 } == true ? self.tapStreak + 1 : 1
        self.lastTapTime = time
        let streakSpeed = top * Float(self.tapStreak) / 4.0
        let speed = min(top, max(abs(current) + 5.0, streakSpeed))
        let reachedTop = speed >= top * 0.95
        if reachedTop { self.tapStreak = 0 }
        self.motion.setSpin(sign * speed, decay: reachedTop ? 2.5 : max(self.diamondStyle.releaseDecay, 0.05))
        if reachedTop { self.addStarBurst(isFromTap: true) }
    }

    func cancelTapSpin() {
        if self.lastTapTime != nil {
            self.motion.stopSpin()
        }
        self.tapStreak = 0
        self.lastTapTime = nil
        self.starBursts.removeAll(where: { $0.isFromTap })
    }

    @objc public func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard self.isInHierarchy && self.isRenderingEnabled else { return }
        self.updateDrag(
            state: gesture.state,
            translation: gesture.translation(in: gesture.view),
            velocity: gesture.velocity(in: gesture.view),
            scale: min(self.bounds.width, self.bounds.height)
        )
        switch gesture.state {
        case .began, .changed, .ended:
            gesture.setTranslation(.zero, in: gesture.view)
        default:
            break
        }
    }

    func updateDrag(state: NSGestureRecognizer.State, translation: CGPoint = .zero, velocity: CGPoint = .zero, scale: CGFloat = 100.0, releaseImpulse: Float? = nil, allowsFlingBurst: Bool = false, tapSpinDirection: Float? = nil) {
        if state != .cancelled && state != .failed {
            guard self.isInHierarchy && self.isRenderingEnabled else { return }
        }
        let now = CACurrentMediaTime()
        self.updateMotion(at: now)
        switch state {
        case .began:
            self.motion.begin(at: now)
            self.onHold?(true)
        case .changed, .ended:
            guard self.motion.isDragging else { break }
            if translation != .zero {
                self.motion.drag(dx: Float(translation.x), dy: Float(translation.y), scale: Float(scale), at: now)
            }
            if state == .ended {
                self.motion.step(dt: 0, speed: self.diamondStyle.rotationSpeed, reduceMotion: self.reduceMotion, mode: self.diamondStyle.animationMode, time: self.elapsed, appearance: self.diamondStyle.appearance)
                self.motion.end(at: now)
                if let tapSpinDirection, self.diamondStyle.tapToSpin, !self.isSendingTransfer,
                   !self.reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    self.tapSpin(direction: tapSpinDirection, at: now)
                } else if abs(velocity.x) > 600.0 && !self.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    self.motion.fling(direction: velocity.x < 0 ? -1 : 1, impulse: releaseImpulse)
                    self.addStarBurst(isFromTap: allowsFlingBurst)
                }
                self.onHold?(false)
            }
        case .cancelled, .failed:
            if self.motion.isDragging {
                self.motion.end(at: now, cancelled: true)
                self.onHold?(false)
            }
        default:
            break
        }
        self.motion.step(dt: 0, speed: self.diamondStyle.rotationSpeed, reduceMotion: self.reduceMotion, mode: self.diamondStyle.animationMode, time: self.elapsed, appearance: self.diamondStyle.appearance)
        self.onPoseUpdated?(self.pose)
        self.setNeedsUpdate()
    }

    private func updateDynamicRange(highDynamicRange: Bool) {
        guard self.isHighDynamicRange != highDynamicRange else { return }
        self.isHighDynamicRange = highDynamicRange
        if #available(macOS 26.0, *) {
            self.contentsHeadroom = highDynamicRange ? 2.2 : 1.0
            self.preferredDynamicRange = highDynamicRange ? .high : .standard
        } else if #available(macOS 14.0, *) {
            self.wantsExtendedDynamicRangeContent = highDynamicRange
        }
    }

    public func update(context: MetalEngineSubjectContext) {
        let canvasSize = self.renderSize ?? self.bounds.size
        guard self.isInHierarchy, self.isRenderingEnabled, canvasSize.width > 0.0, canvasSize.height > 0.0 else { return }
        let pixelsPerPoint = System.backingScale
        let size = RenderSize(width: Int(ceil(canvasSize.width * pixelsPerPoint)), height: Int(ceil(canvasSize.height * pixelsPerPoint)))
        let motion = self.motion
        let time = self.elapsed
        let starBursts = self.starBursts
        let starOffset = self.starOffset
        let reduceMotion = self.reduceMotion
        let lightBackground = self.lightBackground
        let style = self.effectiveStyle
        let grow = self.grow * self.interactionScale
        let refractionSource = self.refractionSource
        let refractionStrength = self.refractionStrength
        let highlightBoost = reduceMotion ? self.highlightBoost * refractionStrength : self.appliedHighlightBoost
        let highDynamicRange: Bool
        if #available(macOS 10.15, *) {
            highDynamicRange = (NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0) > 1.0
                && (highlightBoost > 0.001 || self.highlightBoost * refractionStrength > 0.001)
        } else {
            highDynamicRange = false
        }
        let pixelFormat: MTLPixelFormat = highDynamicRange ? .rgba16Float : .bgra8Unorm
        self.updateDynamicRange(highDynamicRange: highDynamicRange)

        let frame = context.compute(state: DiamondRenderer.self, commands: { [weak self] commandBuffer, renderer -> MTLTexture? in
            guard let self else { return nil }
            if self.renderTargets?.size != size || self.renderTargets?.color.pixelFormat != pixelFormat {
                self.renderTargets = RenderTargets(device: renderer.device, size: size, sampleCount: renderer.sampleCount, pixelFormat: pixelFormat)
            }
            guard let targets = self.renderTargets else { return nil }

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = targets.multisampleColor ?? targets.color
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            if targets.multisampleColor != nil {
                pass.colorAttachments[0].resolveTexture = targets.color
                pass.colorAttachments[0].storeAction = .multisampleResolve
            } else {
                pass.colorAttachments[0].storeAction = .store
            }
            pass.depthAttachment.texture = targets.depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            pass.depthAttachment.storeAction = .dontCare
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
            renderer.encode(encoder: encoder, size: CGSize(width: CGFloat(size.width), height: CGFloat(size.height)), time: time, starBursts: starBursts, starOffset: starOffset, motion: motion, style: style, grow: grow, pixelsPerPoint: Float(pixelsPerPoint), reduceMotion: reduceMotion, lightBackground: lightBackground, refractionSource: refractionSource, refractionStrength: refractionStrength, highlightBoost: highDynamicRange ? highlightBoost : 0, colorPixelFormat: pixelFormat, refractionUpdated: self.onRefractionUpdated)
            encoder.endEncoding()
            return targets.color
        })

        let edgeInset = 2
        context.renderToLayer(spec: RenderLayerSpec(size: size, edgeInset: edgeInset, pixelFormat: highDynamicRange ? .rgba16Float : .bgra8Unorm), state: CompositeState.self, layer: self, inputs: frame, commands: { [weak self] encoder, placement, texture in
            guard let texture else { return }
            if let self, self.renderSize != nil, self.bounds.size != canvasSize {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.bounds = CGRect(origin: .zero, size: canvasSize)
                CATransaction.commit()
            }
            let effectiveRect = placement.effectiveRect
            let contentRect = effectiveRect.insetBy(
                dx: effectiveRect.width * CGFloat(edgeInset) / CGFloat(size.width + edgeInset * 2),
                dy: effectiveRect.height * CGFloat(edgeInset) / CGFloat(size.height + edgeInset * 2)
            )
            var rect = SIMD4<Float>(Float(contentRect.minX), Float(contentRect.minY), Float(contentRect.width), Float(contentRect.height))
            encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        })
    }
}
