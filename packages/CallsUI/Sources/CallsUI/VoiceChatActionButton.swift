import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import CallVideoLayer

private let white = NSColor(rgb: 0xffffff)
private let greyColor = GroupCallUIHooks.shared.groupCallThemeSpeakDisabledColor()
private let secondaryGreyColor = NSColor(rgb: 0x1c1c1e)
private let mutedStartColor = NSColor(rgb: 0x55b3f8)
private let mutedEndColor = NSColor(rgb: 0x55adfe)
private let unmutedStartColor = NSColor(rgb: 0x33c659)
private let unmutedEndColor = NSColor(rgb: 0x0ba8a5)
private let disabledStartColor = NSColor(rgb: 0x3252ef)
private let disabledEndColor = NSColor(rgb: 0xc64688)
private let mutedBlobColor = NSColor(rgb: 0x397cd8)
private let unmutedBlobColor = NSColor(rgb: 0x33c758)
private let disabledBlobColor = NSColor(rgb: 0x914bad)

private let blobSize = CGSize(width: 142, height: 142)

private let progressLineWidth: CGFloat = 3.0 + 1
private let buttonSize = CGSize(width: 110, height: 110)
private let radius = buttonSize.width / 2.0

public final class VoiceChatActionButtonBackgroundView: View {
    public enum State: Equatable {
        case connecting
        case disabled
        case blob(Bool)
    }

    private var state: State
    private var hasState = false

    private var transition: State?

    public var audioLevel: CGFloat = 0.0  {
        didSet {
            self.updateBlobLevel()
        }
    }

    public var updatedActive: ((Bool) -> Void)?

    private let backgroundCircleLayer = CAShapeLayer()
    private let foregroundCircleLayer = CAShapeLayer()

    private let foregroundLayer = CALayer()
    private let foregroundGradientLayer = CAGradientLayer()

    private let maskLayer = CALayer()
    private let blobLayer: VoiceChatBlobLayer
    private let maskCircleLayer = CAShapeLayer()

    fileprivate let maskProgressLayer = CAShapeLayer()

    private let glassLayer = SimpleLayer()
    private var glassImageSize: CGSize = .zero
    private var glassImageScale: CGFloat = 0.0

    public override init() {
        self.state = .connecting

        self.blobLayer = VoiceChatBlobLayer(frame: CGRect(origin: .zero, size: blobSize), maxLevel: 1.5)
        self.blobLayer.setColor(mutedBlobColor, animated: false)
        self.blobLayer.isHidden = true

        super.init()

        let circlePath = CGMutablePath()
        circlePath.addRoundedRect(in: CGRect(origin: CGPoint(), size: buttonSize), cornerWidth: buttonSize.width / 2, cornerHeight: buttonSize.height / 2)

        self.backgroundCircleLayer.fillColor = greyColor.cgColor
        self.backgroundCircleLayer.path = circlePath

        let smallerCirclePath = CGMutablePath()
        let smallerRect = CGRect(origin: CGPoint(), size: CGSize(width: buttonSize.width - progressLineWidth, height: buttonSize.height - progressLineWidth))
        smallerCirclePath.addRoundedRect(in: smallerRect, cornerWidth: smallerRect.width / 2, cornerHeight: smallerRect.height / 2)

        self.foregroundCircleLayer.fillColor = greyColor.cgColor
        self.foregroundCircleLayer.path = smallerCirclePath
        self.foregroundCircleLayer.transform = CATransform3DMakeScale(0.0, 0.0, 1)
        self.foregroundCircleLayer.isHidden = true

        self.foregroundGradientLayer.type = .axial
        self.foregroundGradientLayer.colors = [mutedStartColor.cgColor, mutedEndColor.cgColor]
        self.foregroundGradientLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
        self.foregroundGradientLayer.endPoint = CGPoint(x: 1.0, y: 0.0)

        self.maskLayer.backgroundColor = .clear

        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: (buttonSize.width + 6.0) / 2.0, y: (buttonSize.height + 6.0) / 2.0), radius: radius, startAngle: 0.0, endAngle: CGFloat.pi * 2.0, clockwise: true)

        self.maskProgressLayer.strokeColor = white.cgColor
        self.maskProgressLayer.fillColor = NSColor.clear.cgColor
        self.maskProgressLayer.lineWidth = progressLineWidth
        self.maskProgressLayer.lineCap = .round
        self.maskProgressLayer.path = path

        let largerCirclePath = CGMutablePath()
        let largerCircleRect = CGRect(origin: CGPoint(), size: CGSize(width: buttonSize.width + progressLineWidth, height: buttonSize.height + progressLineWidth))
        largerCirclePath.addRoundedRect(in: largerCircleRect, cornerWidth: largerCircleRect.width / 2, cornerHeight: largerCircleRect.height / 2)

        self.maskCircleLayer.fillColor = white.cgColor
        self.maskCircleLayer.path = largerCirclePath
        self.maskCircleLayer.isHidden = true

        self.glassLayer.compositingFilter = "overlayBlendMode"
        self.glassLayer.opacity = 0.8

        self.layer?.addSublayer(self.blobLayer)
        self.layer?.addSublayer(self.backgroundCircleLayer)

        self.layer?.addSublayer(self.foregroundLayer)
        self.layer?.addSublayer(self.foregroundCircleLayer)
        self.layer?.addSublayer(self.glassLayer)

        self.foregroundLayer.addSublayer(self.foregroundGradientLayer)
        self.foregroundLayer.mask = self.maskLayer

        self.maskLayer.addSublayer(self.maskProgressLayer)
        self.maskLayer.addSublayer(self.maskCircleLayer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private let occlusionDisposable = MetaDisposable()
    private var isCurrentlyInHierarchy: Bool = false {
        didSet {
            updateAnimations()
        }
    }

    deinit {
        occlusionDisposable.dispose()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateBlobRenderScale()
        if let window = window as? Window {
            occlusionDisposable.set(window.takeOcclusionState.start(next: { [weak self] value in
                self?.isCurrentlyInHierarchy = value.contains(.visible)
            }))
        } else {
            occlusionDisposable.set(nil)
            isCurrentlyInHierarchy = window != nil
        }
        self.updateGlassImage()
    }

    private func setupProgressAnimations() {
        if let _ = self.maskProgressLayer.animation(forKey: "progressRotation") {
        } else {
            self.maskProgressLayer.isHidden = false

            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
            animation.duration = 1.0
            animation.fromValue = NSNumber(value: Float(0.0))
            animation.toValue = NSNumber(value: Float.pi * 2.0)
            animation.repeatCount = Float.infinity
            animation.beginTime = 0.0
            self.maskProgressLayer.add(animation, forKey: "progressRotation")

            let shrinkAnimation = CABasicAnimation(keyPath: "strokeEnd")
            shrinkAnimation.fromValue = 1.0
            shrinkAnimation.toValue = 0.0
            shrinkAnimation.duration = 1.0
            shrinkAnimation.beginTime = 0.0

            let growthAnimation = CABasicAnimation(keyPath: "strokeEnd")
            growthAnimation.fromValue = 0.0
            growthAnimation.toValue = 1.0
            growthAnimation.duration = 1.0
            growthAnimation.beginTime = 1.0

            let rotateAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotateAnimation.fromValue = 0.0
            rotateAnimation.toValue = CGFloat.pi * 2
            rotateAnimation.isAdditive = true
            rotateAnimation.duration = 1.0
            rotateAnimation.beginTime = 1.0

            let groupAnimation = CAAnimationGroup()
            groupAnimation.repeatCount = Float.infinity
            groupAnimation.animations = [shrinkAnimation, growthAnimation, rotateAnimation]
            groupAnimation.duration = 2.0

            self.maskProgressLayer.add(groupAnimation, forKey: "progressGrowth")
        }
    }

    private func updateStateColors(active: Bool?, animated: Bool) {
        let gradientColors: [CGColor]
        let blobColor: NSColor
        if let active = active {
            if active {
                gradientColors = [unmutedStartColor.cgColor, unmutedEndColor.cgColor]
                blobColor = unmutedBlobColor
            } else {
                gradientColors = [mutedStartColor.cgColor, mutedEndColor.cgColor]
                blobColor = mutedBlobColor
            }
        } else {
            gradientColors = [disabledStartColor.cgColor, disabledEndColor.cgColor]
            blobColor = disabledBlobColor
        }

        let previousColors = self.foregroundGradientLayer.presentation()?.colors ?? self.foregroundGradientLayer.colors

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.foregroundGradientLayer.colors = gradientColors
        if animated, let previousColors = previousColors {
            self.foregroundGradientLayer.animate(from: previousColors as AnyObject, to: gradientColors as AnyObject, keyPath: "colors", timingFunction: .easeInEaseOut, duration: 0.2)
        } else {
            self.foregroundGradientLayer.removeAnimation(forKey: "colors")
        }
        CATransaction.commit()

        self.blobLayer.setColor(blobColor, animated: animated)
    }

    private func updateBlobLevel() {
        if self.state == .blob(true) {
            self.blobLayer.updateLevel(self.audioLevel)
        } else {
            self.blobLayer.updateLevel(0.0)
        }
    }

    public var animatingDisappearance = false
    private func playBlobsDisappearanceAnimation() {
        if self.animatingDisappearance {
            return
        }
        self.animatingDisappearance = true

        self.blobLayer.startAnimating()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else {
                return
            }
            self.animatingDisappearance = false
            if self.state == .connecting {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.blobLayer.isHidden = true
                self.blobLayer.removeAllAnimations()
                self.maskCircleLayer.isHidden = true
                self.updateStateColors(active: false, animated: false)
                CATransaction.commit()
                self.blobLayer.stopAnimating()
            }
        }
        self.blobLayer.animateScale(from: 1.0, to: 0, duration: 0.15, removeOnCompletion: false)
        CATransaction.commit()
    }

    private func setBlobWithoutAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.maskProgressLayer.removeAllAnimations()
        self.maskProgressLayer.isHidden = true
        self.foregroundCircleLayer.removeAllAnimations()
        self.foregroundCircleLayer.isHidden = true
        self.maskCircleLayer.isHidden = false
        self.updateStateColors(active: self.isActive, animated: false)
        self.blobLayer.removeAllAnimations()
        self.blobLayer.isHidden = false
        CATransaction.commit()

        self.blobLayer.startAnimating()
        self.updatedActive?(true)
    }

    private func setConnectingWithoutAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.maskProgressLayer.removeAnimation(forKey: "progressCompletion")
        self.maskProgressLayer.isHidden = false
        self.foregroundCircleLayer.removeAllAnimations()
        self.foregroundCircleLayer.isHidden = true
        self.maskCircleLayer.isHidden = true
        self.updateStateColors(active: false, animated: false)
        self.blobLayer.removeAllAnimations()
        self.blobLayer.isHidden = true
        CATransaction.commit()

        self.blobLayer.stopAnimating()
    }

    private func playConnectionAnimation() {
        CATransaction.begin()
        let initialRotation: CGFloat = CGFloat((self.maskProgressLayer.value(forKeyPath: "presentationLayer.transform.rotation.z") as? NSNumber)?.floatValue ?? 0.0)
        let initialStrokeEnd: CGFloat = CGFloat((self.maskProgressLayer.value(forKeyPath: "presentationLayer.strokeEnd") as? NSNumber)?.floatValue ?? 1.0)

        self.maskProgressLayer.removeAnimation(forKey: "progressGrowth")
        self.maskProgressLayer.removeAnimation(forKey: "progressRotation")

        let duration: Double = (1.0 - Double(initialStrokeEnd)) * 0.3

        let growthAnimation = CABasicAnimation(keyPath: "strokeEnd")
        growthAnimation.fromValue = initialStrokeEnd
        growthAnimation.toValue = 1.0
        growthAnimation.duration = duration
        growthAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeIn)

        let rotateAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotateAnimation.fromValue = initialRotation
        rotateAnimation.toValue = initialRotation + CGFloat.pi * 2
        rotateAnimation.isAdditive = true
        rotateAnimation.duration = duration
        rotateAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeIn)

        let groupAnimation = CAAnimationGroup()
        groupAnimation.animations = [growthAnimation, rotateAnimation]
        groupAnimation.duration = duration

        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.state != .connecting else {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.foregroundCircleLayer.isHidden = false
            self.maskCircleLayer.isHidden = false
            self.maskProgressLayer.isHidden = true
            self.updateStateColors(active: self.isActive, animated: false)
            self.blobLayer.isHidden = false
            CATransaction.commit()

            self.blobLayer.startAnimating()
            self.blobLayer.animateSpring(from: 0.1 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.45)
            self.blobLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)

            self.updatedActive?(true)

            CATransaction.begin()
            let shrinkAnimation = CABasicAnimation(keyPath: "transform.scale")
            shrinkAnimation.fromValue = 1.0
            shrinkAnimation.toValue = 0.0
            shrinkAnimation.duration = 0.15
            shrinkAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeIn)

            CATransaction.setCompletionBlock {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.foregroundCircleLayer.isHidden = true
                CATransaction.commit()
            }

            self.foregroundCircleLayer.add(shrinkAnimation, forKey: "insideShrink")
            CATransaction.commit()
        }

        self.maskProgressLayer.add(groupAnimation, forKey: "progressCompletion")
        CATransaction.commit()
    }

    private func updateConnected(transition: State?) {
        if self.maskProgressLayer.animation(forKey: "progressCompletion") != nil {
            return
        }
        if transition != nil, !self.maskProgressLayer.isHidden {
            self.playConnectionAnimation()
        } else if transition != nil, !self.blobLayer.isHidden {
            self.updateStateColors(active: self.isActive, animated: true)
            self.blobLayer.startAnimating()
            self.updatedActive?(true)
        } else {
            self.setBlobWithoutAnimation()
        }
    }

    public var isActive: Bool? = nil {
        didSet {

        }
    }
    public func updateAnimations() {
        if !self.isCurrentlyInHierarchy {
            self.foregroundGradientLayer.removeAllAnimations()
            self.maskProgressLayer.removeAllAnimations()
            self.blobLayer.stopAnimating()
            return
        }

        let transition = self.transition
        self.transition = nil

        switch self.state {
        case .connecting:
            self.isActive = false
            self.updatedActive?(false)
            if let transition = transition, transition != .connecting, !self.blobLayer.isHidden {
                self.playBlobsDisappearanceAnimation()
            } else {
                self.setConnectingWithoutAnimation()
            }
            self.setupProgressAnimations()
        case let .blob(active):
            self.isActive = active
            self.updateConnected(transition: transition)
        case .disabled:
            self.isActive = nil
            self.updateConnected(transition: transition)
        }
    }

    public var isDark: Bool = false {
        didSet {
            if self.isDark != oldValue {
                self.updateColors()
            }
        }
    }

    public var isSnap: Bool = false {
        didSet {
            if self.isSnap != oldValue {
                self.updateColors()
            }
        }
    }

    public var connectingColor: NSColor = NSColor(rgb: 0xb6b6bb) {
        didSet {
            if self.connectingColor.rgb != oldValue.rgb {
                self.updateColors()
            }
        }
    }

    public func updateColors() {
        let previousColor: CGColor = self.backgroundCircleLayer.fillColor ?? greyColor.cgColor
        let targetColor: CGColor
        if self.isSnap {
            targetColor = self.connectingColor.cgColor
        } else if self.isDark {
            targetColor = secondaryGreyColor.cgColor
        } else {
            targetColor = greyColor.cgColor
        }
        self.backgroundCircleLayer.fillColor = targetColor
        self.foregroundCircleLayer.fillColor = targetColor
        self.backgroundCircleLayer.animate(from: previousColor, to: targetColor, keyPath: "fillColor", timingFunction: .linear, duration: 0.3)
        self.foregroundCircleLayer.animate(from: previousColor, to: targetColor, keyPath: "fillColor", timingFunction: .linear, duration: 0.3)
    }

    public func update(state: State, animated: Bool) {
        var animated = animated
        var hadState = true
        if !self.hasState {
            hadState = false
            self.hasState = true
            animated = false
        }

        if state != self.state || !hadState {
            if animated {
                self.transition = self.state
            }
            self.state = state

            self.updateBlobLevel()
            self.updateAnimations()
        }
    }

    public override func layout() {
        super.layout()

        let center = CGPoint(x: self.bounds.width / 2.0, y: self.bounds.height / 2.0)
        let circleFrame = CGRect(origin: CGPoint(x: (self.bounds.width - buttonSize.width) / 2.0, y: (self.bounds.height - buttonSize.height) / 2.0), size: buttonSize)
        self.backgroundCircleLayer.frame = circleFrame
        self.foregroundCircleLayer.position = center
        self.foregroundCircleLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: circleFrame.width - progressLineWidth, height: circleFrame.height - progressLineWidth))
        self.maskCircleLayer.frame = circleFrame.insetBy(dx: -progressLineWidth / 2.0, dy: -progressLineWidth / 2.0)
        self.maskProgressLayer.frame = circleFrame.insetBy(dx: -3.0, dy: -3.0)
        self.foregroundLayer.frame = self.bounds
        self.foregroundGradientLayer.frame = self.maskCircleLayer.frame
        self.maskLayer.frame = self.bounds

        self.blobLayer.frame = CGRect(origin: CGPoint(x: center.x - blobSize.width / 2.0, y: center.y - blobSize.height / 2.0), size: blobSize)

        self.glassLayer.frame = self.maskCircleLayer.frame
        self.updateGlassImage()
        self.updateBlobRenderScale()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        self.updateGlassImage()
        self.updateBlobRenderScale()
    }

    private func updateBlobRenderScale() {
        let backingScale = self.window?.backingScaleFactor ?? System.backingScale
        let displayScale = abs(self.layer?.sublayerTransform.m11 ?? 1.0)
        self.blobLayer.updateRenderScale(displayScale * backingScale * 2.0)
    }

    private func updateGlassImage() {
        let backingScale = self.window?.backingScaleFactor ?? System.backingScale
        let displayScale = abs(self.layer?.sublayerTransform.m11 ?? 1.0)
        let pixelDiameter = ceil(self.glassLayer.bounds.width * displayScale * backingScale)
        let size = CGSize(width: pixelDiameter / backingScale, height: pixelDiameter / backingScale)
        if size == self.glassImageSize && backingScale == self.glassImageScale {
            return
        }
        self.glassImageSize = size
        self.glassImageScale = backingScale
        self.glassLayer.contents = generateGlassOverlayImage(size: size, scale: backingScale)
    }
}

private func generateGlassOverlayImage(size: CGSize, scale: CGFloat) -> CGImage? {
    return generateImage(size, scale: scale, rotatedContext: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)

        let maxColor = NSColor.white.withAlphaComponent(0.9).cgColor
        let minColor = NSColor.white.withAlphaComponent(0.0).cgColor
        let lineWidth: CGFloat = 0.66
        let innerShadowBlur: CGFloat = 24.0
        let rimRect = bounds.insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)

        let innerShades: [(CGSize, NSColor)] = [
            (CGSize(width: 10.0, height: -10.0), NSColor.black.withAlphaComponent(0.035)),
            (CGSize(width: -10.0, height: 10.0), NSColor.white.withAlphaComponent(0.035))
        ]
        for (offset, color) in innerShades {
            context.saveGState()
            context.addEllipse(in: rimRect)
            context.clip()
            context.addRect(bounds.insetBy(dx: -100.0, dy: -100.0))
            context.addEllipse(in: bounds)
            context.setFillColor(NSColor.black.cgColor)
            context.setShadow(offset: offset, blur: innerShadowBlur, color: color.cgColor)
            context.fillPath(using: .evenOdd)
            context.restoreGState()
        }

        context.setLineWidth(lineWidth)

        let rimHalves: [(CGRect, [CGFloat], [CGColor])] = [
            (CGRect(x: 0.0, y: 0.0, width: size.width * 0.5, height: size.height), [0.0, 0.5, 0.5 + 0.2, 1.0 - 0.1, 1.0], [maxColor, maxColor, minColor, minColor, maxColor]),
            (CGRect(x: size.width - size.width * 0.5, y: 0.0, width: size.width * 0.5, height: size.height), [0.0, 0.1, 0.5 - 0.2, 0.5, 1.0], [maxColor, minColor, minColor, maxColor, maxColor])
        ]
        for (half, locations, colors) in rimHalves {
            context.saveGState()
            context.addRect(half)
            context.clip()
            context.addEllipse(in: rimRect)
            context.replacePathWithStrokedPath()
            context.clip()
            var locations = locations
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: &locations) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())
            }
            context.restoreGState()
        }
    })
}





public final class VoiceChatBlobLayer: SimpleLayer {
    private let scaleLayer = SimpleLayer()
    private let metalBlobs: CallMicBlobsLayer?
    private let mediumBlob: BlobLayer?
    private let bigBlob: BlobLayer?

    private let maxLevel: CGFloat

    private var displayLinkAnimator: ConstantDisplayLinkAnimator?

    private var audioLevel: CGFloat = 0.0
    public var presentationAudioLevel: CGFloat = 0.0
    private var levelScale: CGFloat = 1.0

    public override init(layer: Any) {
        self.metalBlobs = nil
        self.mediumBlob = nil
        self.bigBlob = nil
        self.maxLevel = 1
        super.init(layer: layer)
    }

    private(set) var isAnimating = false

    public init(frame: CGRect, maxLevel: CGFloat) {
        self.maxLevel = maxLevel

        #if arch(arm64)
        self.metalBlobs = CallMicBlobsLayer()
        self.mediumBlob = nil
        self.bigBlob = nil
        #else
        self.metalBlobs = nil
        self.mediumBlob = BlobLayer(pointsCount: 8, morphSpeed: 3.0, shapeScale: 0.9)
        self.bigBlob = BlobLayer(pointsCount: 8, morphSpeed: 3.0, shapeScale: 1.0)
        #endif

        super.init()

        addSublayer(scaleLayer)
        if let metalBlobs {
            scaleLayer.addSublayer(metalBlobs)
        }
        if let bigBlob {
            scaleLayer.addSublayer(bigBlob)
        }
        if let mediumBlob {
            scaleLayer.addSublayer(mediumBlob)
        }

        self.frame = frame

        displayLinkAnimator = ConstantDisplayLinkAnimator(framesPerSecond: .max) { [weak self] duration in
            guard let strongSelf = self else { return }

            let decay = FrameStep.decay(0.9, duration)
            strongSelf.presentationAudioLevel = strongSelf.presentationAudioLevel * decay + strongSelf.audioLevel * (1 - decay)

            let levelScale = 1.0 + min(strongSelf.presentationAudioLevel * 18.0, 5.0) * 0.1
            if abs(levelScale - strongSelf.levelScale) > 0.0005 {
                strongSelf.levelScale = levelScale
                strongSelf.scaleLayer.transform = CATransform3DMakeScale(levelScale, levelScale, 1.0)
            }
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setColor(_ color: NSColor, animated: Bool) {
        mediumBlob?.setColor(color.withAlphaComponent(0.35), animated: animated)
        bigBlob?.setColor(color.withAlphaComponent(0.35), animated: animated)
        if let metalBlobs {
            let previousColor = metalBlobs.presentation()?.layerTintColor ?? metalBlobs.layerTintColor
            metalBlobs.layerTintColor = color.cgColor
            if animated, let previousColor {
                metalBlobs.animate(from: previousColor, to: color.cgColor, keyPath: "contentsMultiplyColor", timingFunction: .easeInEaseOut, duration: 0.2)
            } else {
                metalBlobs.removeAnimation(forKey: "contentsMultiplyColor")
            }
        }
    }

    public func updateRenderScale(_ scale: CGFloat) {
        metalBlobs?.renderScale = scale
    }

    public func updateLevel(_ level: CGFloat) {
        audioLevel = min(1, max(level / maxLevel, 0))
    }

    public func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true

        updateBlobsState()

        displayLinkAnimator?.isPaused = false
    }

    public func stopAnimating() {
        self.stopAnimating(duration: 0.15)
    }

    public func stopAnimating(duration: Double) {
        guard isAnimating else { return }
        isAnimating = false

        updateBlobsState()

        displayLinkAnimator?.isPaused = true
    }

    private func updateBlobsState() {
        if isAnimating {
            if scaleLayer.bounds.size != .zero {
                mediumBlob?.startAnimating()
                bigBlob?.startAnimating()
                metalBlobs?.isInHierarchy = true
            }
        } else {
            mediumBlob?.stopAnimating()
            bigBlob?.stopAnimating()
            metalBlobs?.isInHierarchy = false
        }
    }

    public override var frame: CGRect {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scaleLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            scaleLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            metalBlobs?.frame = scaleLayer.bounds
            mediumBlob?.frame = scaleLayer.bounds
            bigBlob?.frame = scaleLayer.bounds
            CATransaction.commit()

            if oldValue.size != frame.size {
                updateBlobsState()
            }
        }
    }
}

public final class BlobLayer: SimpleShapeLayer {
    public let pointsCount: Int
    public let smoothness: CGFloat

    public let morphSpeed: CGFloat
    public let shapeScale: CGFloat

    private var blobAnimation: DisplayLinkAnimator?

    public override init(layer: Any) {
        self.pointsCount = 0
        self.morphSpeed = 0
        self.shapeScale = 0

        self.smoothness = 0
        super.init(layer: layer)
    }

    private let shapeLayer: SimpleShapeLayer = {
            let layer = SimpleShapeLayer()
            layer.strokeColor = nil
            return layer
        }()

    private var transition: CGFloat = 0 {
        didSet {
            if let currentPoints = self.currentPoints {
                self.shapeLayer.path = .smoothCurve(through: currentPoints, length: self.bounds.width, smoothness: self.smoothness)
            }
        }
    }

    private var fromPoints: [CGPoint]?
    private var toPoints: [CGPoint]?

    private var currentPoints: [CGPoint]? {
        guard let fromPoints = fromPoints, let toPoints = toPoints else { return nil }

        return fromPoints.enumerated().map { offset, fromPoint in
            let toPoint = toPoints[offset]
            return CGPoint(
                x: fromPoint.x + (toPoint.x - fromPoint.x) * transition,
                y: fromPoint.y + (toPoint.y - fromPoint.y) * transition
            )
        }
    }

    public init(pointsCount: Int, morphSpeed: CGFloat, shapeScale: CGFloat) {
        self.pointsCount = pointsCount
        self.morphSpeed = morphSpeed
        self.shapeScale = shapeScale

        let angle = (CGFloat.pi * 2) / CGFloat(pointsCount)
        self.smoothness = ((4 / 3) * tan(angle / 4)) / sin(angle / 2) / 2

        super.init()

        self.addSublayer(shapeLayer)
        shapeLayer.transform = CATransform3DMakeScale(shapeScale, shapeScale, 1)
    }


    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setColor(_ color: NSColor, animated: Bool) {
        let previousColor = shapeLayer.presentation()?.fillColor ?? shapeLayer.fillColor
        shapeLayer.fillColor = color.cgColor
        if animated, let previousColor = previousColor {
            shapeLayer.animate(from: previousColor, to: color.cgColor, keyPath: "fillColor", timingFunction: .easeInEaseOut, duration: 0.2)
        } else {
            shapeLayer.removeAnimation(forKey: "fillColor")
        }
    }

    public func startAnimating() {
        animateToNewShape()
    }

    public func stopAnimating() {
        fromPoints = currentPoints
        toPoints = nil
        blobAnimation = nil
    }

    private func animateToNewShape() {
        if blobAnimation != nil {
            fromPoints = currentPoints
            toPoints = nil
            blobAnimation = nil
        }

        if fromPoints == nil {
            fromPoints = generateNextBlob(for: bounds.size)
        }
        if toPoints == nil {
            toPoints = generateNextBlob(for: bounds.size)
        }

        let animation = DisplayLinkAnimator(duration: Double(1.0 / morphSpeed), from: 0.0, to: 1.0, timingFunction: CAMediaTimingFunction(name: .linear), update: { [weak self] value in
            self?.transition = value
        }, completion: { [weak self] in
            guard let `self` = self else {
                return
            }
            self.fromPoints = self.currentPoints
            self.toPoints = nil
            self.blobAnimation = nil
            self.animateToNewShape()
        })
        self.blobAnimation = animation
    }

    private func generateNextBlob(for size: CGSize) -> [CGPoint] {
        return (0 ..< pointsCount).map { index -> CGPoint in
            let angle = CGFloat(index) / CGFloat(pointsCount) * CGFloat.pi * 2.0
            let radius = 0.45 + 0.05 * CGFloat.random(in: 0.0 ... 1.0)
            return CGPoint(x: cos(angle) * radius * size.width, y: sin(angle) * radius * size.height)
        }
    }

    public override var frame: CGRect {
        didSet {
            shapeLayer.position = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        }
    }
}
