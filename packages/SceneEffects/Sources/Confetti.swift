import Cocoa
import TelegramMediaUtils
import TGUIKit
import CoreGraphics
import QuartzCore
import TelegramCore
import SwiftSignalKit
import TelegramMedia
import TelegramContext
import TelegramUtils
import LocalAnimations
import InlineStickers
import TelegramTheme
import InlineStickerLayer

public func PlayConfetti(for window: Window, playEffect: Bool = false, stars: Bool = false) {
    let contentView = window.contentView!
    
    contentView.addSubview(ConfettiView(frame: contentView.bounds, stars: stars))
    
}


private struct Vector2 {
    public var x: Float
    public var y: Float
}

private final class NullActionClass: NSObject, CAAction {
    @objc public func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable : Any]?) {
    }
}

private let nullAction = NullActionClass()

private final class ParticleLayer: SimpleLayer {
    public let mass: Float
    public var velocity: Vector2
    public var angularVelocity: Float
    public var rotationAngle: Float = 0.0
    
    public init(image: CGImage, size: CGSize, position: CGPoint, mass: Float, velocity: Vector2, angularVelocity: Float) {
        self.mass = mass
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        
        super.init()
        
        self.contents = image
        self.bounds = CGRect(origin: CGPoint(), size: size)
        self.position = position
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func action(forKey event: String) -> CAAction? {
        return nullAction
    }
}

public final class ConfettiView: View {
    private var particles: [ParticleLayer] = []
    private var displayLink: ConstantDisplayLinkAnimator?
    
    private var localTime: Float = 0.0
    
    
    public required init(frame: CGRect, stars: Bool) {
        super.init(frame: frame)
        
        self.isEventLess = true
        
        let colors: [NSColor] = ([
            0x56CE6B,
            0xCD89D0,
            0x1E9AFF,
            0xFF8724
            ] as [UInt32]).map(NSColor.init(rgb:))
        let imageSize = CGSize(width: 8.0, height: 8.0)
        var images: [(CGImage, CGSize)] = []
        for imageType in 0 ..< 2 {
            for color in colors {
                if imageType == 0 {
                    if stars {
                        images.append((TelegramThemeHooks.shared.image(.iconPeerPremium).precomposed(color), NSMakeSize(12, 12)))
                    } else {
                        images.append((generateFilledCircleImage(diameter: imageSize.width, color: color), imageSize))
                    }
                } else {
                    let spriteSize = CGSize(width: 2.0, height: 6.0)
                    images.append((generateImage(spriteSize, opaque: false, rotatedContext: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(color.cgColor)
                        context.fillEllipse(in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: size.width, height: size.width)))
                        context.fillEllipse(in: CGRect(origin: CGPoint(x: 0.0, y: size.height - size.width), size: CGSize(width: size.width, height: size.width)))
                        context.fill(CGRect(origin: CGPoint(x: 0.0, y: size.width / 2.0), size: CGSize(width: size.width, height: size.height - size.width)))
                    })!, spriteSize))
                }
            }
        }
        let imageCount = images.count
        
        let originXRange = 0 ..< Int(frame.width)
        let originYRange = Int(-frame.height) ..< Int(0)
        let topMassRange: Range<Float> = 40.0 ..< 50.0
        let velocityYRange = Float(3.0) ..< Float(5.0)
        let angularVelocityRange = Float(1.0) ..< Float(6.0)
        let sizeVariation = Float(0.8) ..< Float(1.6)
        
        for i in 0 ..< 70 {
            let (image, size) = images[i % imageCount]
            let sizeScale = CGFloat(Float.random(in: sizeVariation))
            let particle = ParticleLayer(image: image, size: CGSize(width: size.width * sizeScale, height: size.height * sizeScale), position: CGPoint(x: CGFloat(Int.random(in: originXRange)), y: CGFloat(Int.random(in: originYRange))), mass: Float.random(in: topMassRange), velocity: Vector2(x: 0.0, y: Float.random(in: velocityYRange)), angularVelocity: Float.random(in: angularVelocityRange))
            self.particles.append(particle)
            self.layer?.addSublayer(particle)
        }
        
        let sideMassRange: Range<Float> = 100.0 ..< 110.0
        let sideOriginYBase: Float = Float(frame.size.height * 8.5 / 10.0)
        let sideOriginYVariation: Float = Float(frame.size.height / 12.0)
        let sideOriginYRange = Float(sideOriginYBase - sideOriginYVariation) ..< Float(sideOriginYBase + sideOriginYVariation)
        let sideOriginXRange = Float(0.0) ..< Float(100.0)
        let sideOriginVelocityValueRange = Float(1.1) ..< Float(1.6)
        let sideOriginVelocityValueScaling: Float = 1200.0
        let sideOriginVelocityBase: Float = Float.pi / 2.0 + atanf(Float(CGFloat(sideOriginYBase) / (frame.size.width * 0.8)))
        let sideOriginVelocityVariation: Float = 0.2
        let sideOriginVelocityAngleRange = Float(sideOriginVelocityBase - sideOriginVelocityVariation) ..< Float(sideOriginVelocityBase + sideOriginVelocityVariation)
        
        for sideIndex in 0 ..< 2 {
            let sideSign: Float = sideIndex == 0 ? 1.0 : -1.0
            let originX: CGFloat = sideIndex == 0 ? -5.0 : (frame.width + 5.0)
            for i in 0 ..< 40 {
                let offsetX = CGFloat(Float.random(in: sideOriginXRange) * (-sideSign))
                let velocityValue = Float.random(in: sideOriginVelocityValueRange) * sideOriginVelocityValueScaling
                let velocityAngle = Float.random(in: sideOriginVelocityAngleRange)
                let velocityX = sideSign * velocityValue * sinf(velocityAngle)
                let velocityY = velocityValue * cosf(velocityAngle)
                let (image, size) = images[i % imageCount]
                let sizeScale = CGFloat(Float.random(in: sizeVariation))
                let particle = ParticleLayer(image: image, size: CGSize(width: size.width * sizeScale, height: size.height * sizeScale), position: CGPoint(x: originX + offsetX, y: CGFloat(Float.random(in: sideOriginYRange))), mass: Float.random(in: sideMassRange), velocity: Vector2(x: velocityX, y: velocityY), angularVelocity: Float.random(in: angularVelocityRange))
                self.particles.append(particle)
                self.layer?.addSublayer(particle)
            }
        }
        
        self.displayLink = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] duration in
            self?.step(duration)
        })
        
        self.displayLink?.isPaused = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    private func step(_ duration: CGFloat) {
        var haveParticlesAboveGround = false
        let minPositionY: CGFloat = 0.0
        let maxPositionY = self.bounds.height + 30.0
        let currentTime = self.localTime
        let dt = Float(duration)
        let frames = Float(FrameStep.scale(duration))
        let slowdownDt: Float
        let slowdownStart: Float = 0.27
        let slowdownDuration: Float = 0.9
        let damping: Float
        if currentTime >= slowdownStart && currentTime <= slowdownStart + slowdownDuration {
            let slowdownTimestamp: Float = currentTime - slowdownStart
            
            let slowdownRampInDuration: Float = 0.15
            let slowdownRampOutDuration: Float = 0.5
            let slowdownTransition: Float
            if slowdownTimestamp < slowdownRampInDuration {
                slowdownTransition = slowdownTimestamp / slowdownRampInDuration
            } else if slowdownTimestamp >= slowdownDuration - slowdownRampOutDuration {
                let reverseTransition = (slowdownTimestamp - (slowdownDuration - slowdownRampOutDuration)) / slowdownRampOutDuration
                slowdownTransition = 1.0 - reverseTransition
            } else {
                slowdownTransition = 1.0
            }
            
            let slowdownFactor: Float = 0.3 * slowdownTransition + 1.0 * (1.0 - slowdownTransition)
            slowdownDt = dt * slowdownFactor
            let dampingFactor: Float = 0.94 * slowdownTransition + 1.0 * (1.0 - slowdownTransition)
            damping = dampingFactor
        } else {
            slowdownDt = dt
            damping = 1.0
        }
        self.localTime += dt
        
        let g: Vector2 = Vector2(x: 0.0, y: 9.8)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var turbulenceVariation: [Float] = []
        for _ in 0 ..< 20 {
            turbulenceVariation.append(Float.random(in: -9.0 ..< 9.0))
        }
        let turbulenceVariationCount = turbulenceVariation.count
        var index = 0
        for particle in self.particles {
            var position = particle.position
            
            let localDt: Float = slowdownDt
            
            position.x += CGFloat(particle.velocity.x * localDt)
            position.y += CGFloat(particle.velocity.y * localDt)
            particle.position = position
            
            particle.rotationAngle += particle.angularVelocity * localDt
            particle.transform = CATransform3DMakeRotation(CGFloat(particle.rotationAngle), 0.0, 0.0, 1.0)
            
            let acceleration = g
            
            var velocity = particle.velocity
            velocity.x += acceleration.x * particle.mass * localDt
            velocity.y += acceleration.y * particle.mass * localDt
            velocity.x += turbulenceVariation[index % turbulenceVariationCount] * frames.squareRoot()
            if position.y > minPositionY {
                velocity.x *= pow(damping, frames)
                velocity.y *= pow(damping, frames)
            }
            particle.velocity = velocity
            
            index += 1
            
            if position.y < maxPositionY {
                haveParticlesAboveGround = true
            }
        }
        CATransaction.commit()
        if !haveParticlesAboveGround {
            self.displayLink?.isPaused = true
            self.removeFromSuperview()
        }
    }
}


private final class ParticleReactionLayer: SimpleLayer {
    public let mass: Float
    public var velocity: Vector2
    public var angularVelocity: Float
    public var rotationAngle: Float = 0.0
    
    public init(sublayer: CALayer, size: CGSize, position: CGPoint, mass: Float, velocity: Vector2, angularVelocity: Float) {
        self.mass = mass
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        
        super.init()
        
        self.addSublayer(sublayer)
        self.bounds = CGRect(origin: CGPoint(), size: size)
        self.position = position
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func action(forKey event: String) -> CAAction? {
        return nullAction
    }
}

public final class CustomReactionEffectView: View {
    public enum Style {
        case particles
        case inlinePattern(mirrored: Bool)
    }
    
    private var particles: [ParticleReactionLayer] = []
    private var displayLink: ConstantDisplayLinkAnimator?
    
    private var localTime: Float = 0.0
    
    public var triggerOnFinish:()->Void = {}
    private let backgroundView: LottiePlayerView
    
    private let disposable = MetaDisposable()
    private let context: (any AccountContextProtocol)
    
    private let style: Style
    
    public required init(frame: CGRect, context: (any AccountContextProtocol), fileId: Int64, file: TelegramMediaFile? = nil, style: Style = .particles) {
        self.context = context
        self.style = style
        self.backgroundView = LottiePlayerView(frame: NSMakeRect(0, 0, floor(frame.width / 2), floor(frame.height / 2)))
        super.init(frame: frame)
        addSubview(backgroundView)
        
        backgroundView.center()
        let size = backgroundView.frame.size
        
        let signal: Signal<LottieAnimation?, NoError> = context.engine.stickers.loadedStickerPack(reference: .emojiGenericAnimations, forceActualized: false) |> map { pack -> StickerPackItem? in
            switch pack {
            case let .result(_, items, _):
                for item in items {
                    _ = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .init(file: item.file._parse()), reference: .standalone(resource: item.file._parse().resource), ranges: nil).start()
                }
                return items.randomElement()
            default:
                return nil
            }
        } |> mapToSignal { item -> Signal<Data?, NoError> in
            if let item = item {
                return context.account.postbox.mediaBox.resourceData(item.file._parse().resource) |> take(1) |> map { resource in
                    if resource.complete {
                        return try? Data(contentsOf: URL(fileURLWithPath: resource.path))
                    } else {
                        return nil
                    }
                }
            } else {
                return .single(nil)
            }
        } |> map { data in
            let data = data ?? LocalAnimatedSticker.custom_reaction.data
            if let data = data {
                return LottieAnimation(compressed: data, key: .init(key: .bundle("custom_\(arc4random64())"), size: size, backingScale: Int(System.backingScale), fitzModifier: nil), cachePurpose: .none, playPolicy: .onceEnd)
            } else {
                return nil
            }
        } |> deliverOnMainQueue
                
        let fileSignal: Signal<(TelegramMediaFile?, LottieAnimation?), NoError> = context.inlinePacksContext.load(fileId: fileId) |> mapToSignal { file in
            if let file = file, let emoji = file.customEmojiText {
                return context.reactions.stateValue
                |> take(1) |> mapToSignal { value in
                    if let reaction = value?.reactions.first(where: { $0.value == .builtin(emoji) }) {
                        if let animation = reaction.aroundAnimation?._parse() {
                            return context.account.postbox.mediaBox.resourceData(animation.resource)
                            |> take(1)
                            |> map { data in
                                if data.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                                    return (file, LottieAnimation(compressed: data, key: .init(key: .bundle("_status_effect_\(animation.fileId.id)"), size: size, backingScale: Int(System.backingScale), mirror: false), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd))
                                } else {
                                    return (file, nil)
                                }
                            }
                        }
                    }
                    return .single((file, nil))
                }
            } else {
                return .single((file, nil))
            }
        }
        
        let combined = combineLatest(signal, fileSignal)
                                     |> deliverOnMainQueue
        
        
        //
        
        disposable.set(combined.start(next: { [weak self] animation, file in
            if let statusFile = file.0 {
                if let builtinAnimation = file.1, false {
                    builtinAnimation.triggerOn = (.last, { [weak self] in
                        self?.triggerOnFinish()
                    }, {})
                    self?.backgroundView.set(builtinAnimation)
                } else if let style = self?.style, case let .inlinePattern(mirrored) = style {
                    self?.backgroundView.set(animation)
                    self?.playPattern(fileId, statusFile, mirrored: mirrored)
                } else {
                    if !isDefaultStatusesPackId(statusFile.emojiReference) {
                        self?.backgroundView.set(animation)
                    }
                    self?.playStrikeAnimation(fileId, statusFile)
                }
            }
        }))
        self.backgroundView.userInteractionEnabled = false
        self.backgroundView.isEventLess = true
        self.isEventLess = true

    }
    
    private func playPattern(_ fileId: Int64, _ file: TelegramMediaFile?, mirrored: Bool) {
        let unit = min(self.frame.width, self.frame.height) * 0.72 / ReactionBurstPattern.side
        let baseScale: CGFloat = 0.25
        let side = floor(ReactionBurstPattern.emojiSide * unit * baseScale)
        let center = NSMakePoint(self.bounds.midX, self.bounds.midY)
        let direction: CGFloat = mirrored ? -1 : 1
        let count = Int(ceil(ReactionBurstPattern.duration * 120)) + 1
        let duration = ReactionBurstPattern.duration
        let keyTimes = (0 ..< count).map { NSNumber(value: Double($0) / Double(count - 1)) }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for copy in 0 ..< ReactionBurstPattern.copyCount {
            var positions: [NSValue] = []
            var transforms: [NSValue] = []
            var opacities: [NSNumber] = []
            for index in 0 ..< count {
                let frame = ReactionBurstPattern.frameCount * CGFloat(index) / CGFloat(count - 1)
                let sample = ReactionBurstPattern.sample(copy: copy, frame: frame)
                positions.append(NSValue(point: NSMakePoint(center.x + sample.position.x * unit * direction, center.y - sample.position.y * unit)))
                transforms.append(NSValue(caTransform3D: CATransform3DMakeScale(sample.scale.width / baseScale * direction, sample.scale.height / baseScale, 1)))
                opacities.append(NSNumber(value: Float(sample.opacity)))
            }
            let container = SimpleLayer(frame: NSMakeRect(center.x - side / 2, center.y - side / 2, side, side))
            container.opacity = 0
            let sublayer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: file, emoji: ""), size: NSMakeSize(side, side), checkStatus: true)
            sublayer.frame = container.bounds
            sublayer.isPlayable = true
            container.addSublayer(sublayer)
            self.layer?.addSublayer(container)
            
            let begin = container.convertTime(CACurrentMediaTime(), from: nil)
            for (keyPath, values) in [("position", positions as [Any]), ("transform", transforms as [Any]), ("opacity", opacities as [Any])] {
                let animation = CAKeyframeAnimation(keyPath: keyPath)
                animation.values = values
                animation.keyTimes = keyTimes
                animation.duration = duration
                animation.calculationMode = .linear
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.beginTime = begin
                animation.fillMode = .both
                animation.isRemovedOnCompletion = false
                container.add(animation, forKey: "burst.\(keyPath)")
            }
        }
        CATransaction.commit()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.triggerOnFinish()
        }
    }
    
    private func playStrikeAnimation(_ fileId: Int64, _ file: TelegramMediaFile?) {
        
//        let originXRange = Int(frame.width / 2 - 20) ..< Int(frame.width / 2 + 20)
        let topMassRange: Range<Float> = 40.0 ..< 50.0
        let velocityYRange = Float(3.0) ..< Float(5.0)
        let angularVelocityRange = Float(-3) ..< Float(3)
        _ = Float(0.8) ..< Float(1.6)
        
        let count: Int = 7
        
        let r: CGFloat = max(25, frame.width / 8)
        let mid = NSMakePoint(frame.width / 2, frame.height / 2)
        for i in 0 ..< count {
            
            let gotSize = CGFloat.random(in: 20..<28)
            let size = NSMakeSize(gotSize, gotSize)

            let angle = 360.0 / CGFloat(count) * CGFloat(i)
            let point = NSMakePoint(mid.x + r * sin(angle), mid.y + r * cos(angle))
            

            
            let sublayer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: file, emoji: ""), size: size, checkStatus: true)
           
            sublayer.isPlayable = true
            
            let particle = ParticleReactionLayer(sublayer: sublayer, size: CGSize(width: size.width, height: size.height), position: point, mass: Float.random(in: topMassRange), velocity: Vector2(x: 0, y: Float.random(in: velocityYRange)), angularVelocity: Float.random(in: angularVelocityRange))
            self.particles.append(particle)
            self.layer?.addSublayer(particle)
            particle.animateScale(from: 0.1, to: 1, duration: 0.1)
        }
        
        self.displayLink = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] duration in
            self?.step(duration)
        })
        self.step(1.0 / 60.0)
        self.displayLink?.isPaused = false
    }
    
    deinit {
        disposable.dispose()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    private func step(_ duration: CGFloat) {
        
        var haveParticlesAboveGround = false
        let minPositionY: CGFloat = 0.0
        let maxPositionY = self.bounds.height
        let currentTime = self.localTime
        let dt = Float(duration)
        let frames = Float(FrameStep.scale(duration))
        let slowdownDt: Float
        let slowdownStart: Float = 0.05
        let slowdownDuration: Float = 0.2
        let damping: Float
        

        
        if currentTime >= slowdownStart && currentTime <= slowdownStart + slowdownDuration {
            let slowdownTimestamp: Float = currentTime - slowdownStart
            
            let slowdownRampInDuration: Float = 0.15
            let slowdownRampOutDuration: Float = 0.5
            let slowdownTransition: Float
            if slowdownTimestamp < slowdownRampInDuration {
                slowdownTransition = slowdownTimestamp / slowdownRampInDuration
            } else if slowdownTimestamp >= slowdownDuration - slowdownRampOutDuration {
                let reverseTransition = (slowdownTimestamp - (slowdownDuration - slowdownRampOutDuration)) / slowdownRampOutDuration
                slowdownTransition = 1.0 - reverseTransition
            } else {
                slowdownTransition = 1.0
            }
            
            let slowdownFactor: Float = 0.3 * slowdownTransition + 1.0 * (1.0 - slowdownTransition)
            slowdownDt = dt * slowdownFactor
            let dampingFactor: Float = 0.94 * slowdownTransition + 1.0 * (1.0 - slowdownTransition)
            damping = dampingFactor
        } else {
            slowdownDt = dt
            if currentTime < slowdownStart {
                damping = 1.05
            } else {
                damping = 1.0
            }
        }
        self.localTime += dt
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var turbulenceVariation: [Float] = []
        for _ in 0 ..< 20 {
            turbulenceVariation.append(Float.random(in: -1 ..< 1))
        }
        _ = turbulenceVariation.count
        var index = 0
        for particle in self.particles {
            var position = particle.position
            
            let localDt: Float = slowdownDt
            
            position.x += CGFloat(particle.velocity.x * localDt)
            position.y += CGFloat(particle.velocity.y * localDt)
            particle.position = position
            
          //  particle.rotationAngle += particle.angularVelocity * localDt
            
            var g: Vector2 = Vector2(x: 0.0, y: 6)

            
            if currentTime < slowdownStart {
                g.y = -Float.random(in: 40..<50)
                g.x = arc4random64() % 2 == 0 ? -Float.random(in: 5..<10) : Float.random(in: 5..<10)
            }
            
            
            var fr = CATransform3DIdentity
            
            var scale: CGFloat = 1.0
            let oneOfThree = frame.height / 3

            var opacity: CGFloat = 1.0
            if position.y > frame.height / 2, currentTime > slowdownStart + slowdownDuration + 0.35 {
                let rest = (position.y - frame.height / 2)
                scale = 1 - rest / oneOfThree
                opacity = scale
            }
            fr = CATransform3DRotate(fr, CGFloat(particle.rotationAngle), 0.0, 0.0, 1.0)
            fr = CATransform3DScale(fr, scale, scale, scale)
            particle.transform = fr
            particle.opacity = Float(opacity)
            let acceleration = g
            
            var velocity = particle.velocity
            velocity.x += acceleration.x * particle.mass * localDt
            velocity.y += acceleration.y * particle.mass * localDt
//            velocity.x += turbulenceVariation[index % turbulenceVariationCount]
            if position.y > minPositionY {
                velocity.x *= pow(damping, frames)
                velocity.y *= pow(damping, frames)
            }
            particle.velocity = velocity
            
            index += 1
            
            if position.y < maxPositionY {
                haveParticlesAboveGround = true
            }
        }
        CATransaction.commit()
        if !haveParticlesAboveGround {
            self.displayLink?.isPaused = true
            self.triggerOnFinish()
        }
    }
}
