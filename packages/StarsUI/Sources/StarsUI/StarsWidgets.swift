import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import LocalAnimations
import TelegramMedia
import SceneEffects
import InlineStickerLayer

public let starsGradient = [NSColor(0xFFAC04), NSColor(0xFFCA35)]

public final class StarsButtonEffectLayer: SimpleLayer {
    fileprivate static let whiteParticle: CGImage = TelegramThemeHooks.shared.image(.starReactionParticle).precomposed(.white)

    public let emitterLayer = CAEmitterLayer()
    
    private var currentColor: CGColor?
    private var currentSize: CGSize?
    public var color: NSColor = NSColor(0xffbe27) {
        didSet { updateEmitterColor() }
    }
    
    public var isPlaying: Bool = true {
        didSet {
            if self.isPlaying != oldValue {
                self.emitterLayer.birthRate = self.isPlaying ? 1.0 : 0.0
            }
        }
    }
    
    public override init() {
        super.init()
        
        self.addSublayer(self.emitterLayer)
        
    }
    
    public override init(layer: Any) {
        super.init(layer: layer)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        
        let emitter = CAEmitterCell()
        emitter.name = "emitter"
        emitter.contents = StarsButtonEffectLayer.whiteParticle
        emitter.birthRate = 20
        emitter.lifetime = 1.5
        emitter.velocity = 10.0
        emitter.velocityRange = 3
        emitter.scale = 0.1
        emitter.scaleRange = 0.08
        emitter.alphaRange = 0.1
        emitter.emissionRange = .pi * 2.0
        emitter.setValue(3.0, forKey: "mass")
        emitter.setValue(2.0, forKey: "massRange")
        
        self.currentColor = nil
        updateEmitterColor(emitter: emitter)
    }

    private func updateEmitterColor(emitter: CAEmitterCell? = nil) {
        let resolvedColor = color.cgColor
        guard currentColor != resolvedColor, let emitter = emitter ?? emitterLayer.emitterCells?.first else { return }
        let clearColor = color.withAlphaComponent(0.0).cgColor
        let behavior = createEmitterBehavior(type: "colorOverLife")
        behavior.setValue([clearColor, resolvedColor, resolvedColor, clearColor], forKey: "colors")
        emitter.setValue([behavior], forKey: "emitterBehaviors")
        emitterLayer.emitterCells = [emitter]
        currentColor = resolvedColor
    }

    public func update(size: CGSize) {
        let needsSetup = self.emitterLayer.emitterCells == nil
        if needsSetup {
            self.setup()
            self.emitterLayer.emitterShape = .circle
            self.emitterLayer.emitterMode = .surface
        } else if color.type != .componentBased {
            updateEmitterColor()
        }
        guard needsSetup || currentSize != size else { return }
        self.emitterLayer.emitterSize = CGSize(width: size.width * 0.7, height: size.height * 0.7)
        self.emitterLayer.frame = CGRect(origin: .zero, size: size)
        self.emitterLayer.emitterPosition = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        currentSize = size
    }
}

public final class BadgeStarsViewEffect: View {
    private static let whiteParticle: CGImage = StarsButtonEffectLayer.whiteParticle

    private let staticEmitterLayer = CAEmitterLayer()
    private let dynamicEmitterLayer = CAEmitterLayer()
    
    private var currentColor: CGColor?
    private var currentLayout: CGRect?
    public var color = NSColor(rgb: 0xffbe27) {
        didSet { updateEmitterColor() }
    }

    
    public required init(frame: CGRect) {
        super.init(frame: frame)
        
        self.layer?.addSublayer(self.staticEmitterLayer)
        self.layer?.addSublayer(self.dynamicEmitterLayer)
    }
    
    public required init(coder: NSCoder) {
        preconditionFailure()
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
        
    private func setupEmitter() {
        
        self.staticEmitterLayer.emitterShape = .circle
        self.staticEmitterLayer.emitterSize = CGSize(width: 10.0, height: 5.0)
        self.staticEmitterLayer.emitterMode = .outline
        self.layer?.addSublayer(self.staticEmitterLayer)
        
        self.dynamicEmitterLayer.birthRate = 0.0
        self.dynamicEmitterLayer.emitterShape = .circle
        self.dynamicEmitterLayer.emitterSize = CGSize(width: 10.0, height: 55.0)
        self.dynamicEmitterLayer.emitterMode = .surface
        self.layer?.addSublayer(self.dynamicEmitterLayer)
        
        let staticEmitter = CAEmitterCell()
        staticEmitter.name = "emitter"
        staticEmitter.contents = BadgeStarsViewEffect.whiteParticle
        staticEmitter.birthRate = 20.0
        staticEmitter.lifetime = 2.7
        staticEmitter.velocity = 30.0
        staticEmitter.velocityRange = 3
        staticEmitter.scale = 0.15
        staticEmitter.scaleRange = 0.08
        staticEmitter.emissionRange = .pi * 2.0
        staticEmitter.setValue(3.0, forKey: "mass")
        staticEmitter.setValue(2.0, forKey: "massRange")
        
        let dynamicEmitter = CAEmitterCell()
        dynamicEmitter.name = "emitter"
        dynamicEmitter.contents = BadgeStarsViewEffect.whiteParticle
        dynamicEmitter.birthRate = 0.0
        dynamicEmitter.lifetime = 2.7
        dynamicEmitter.velocity = 30.0
        dynamicEmitter.velocityRange = 3
        dynamicEmitter.scale = 0.15
        dynamicEmitter.scaleRange = 0.08
        dynamicEmitter.emissionRange = .pi / 3.0
        dynamicEmitter.setValue(3.0, forKey: "mass")
        dynamicEmitter.setValue(2.0, forKey: "massRange")
        
        let attractor = createEmitterBehavior(type: "simpleAttractor")
        attractor.setValue("attractor", forKey: "name")
        attractor.setValue(20, forKey: "falloff")
        attractor.setValue(35, forKey: "radius")
        self.staticEmitterLayer.setValue([attractor], forKey: "emitterBehaviors")
        self.staticEmitterLayer.setValue(4.0, forKeyPath: "emitterBehaviors.attractor.stiffness")
        self.staticEmitterLayer.setValue(false, forKeyPath: "emitterBehaviors.attractor.enabled")
        
        self.currentColor = nil
        updateEmitterColor(staticEmitter: staticEmitter, dynamicEmitter: dynamicEmitter)
    }

    private func updateEmitterColor(staticEmitter: CAEmitterCell? = nil, dynamicEmitter: CAEmitterCell? = nil) {
        let resolvedColor = color.cgColor
        guard currentColor != resolvedColor,
              let staticEmitter = staticEmitter ?? staticEmitterLayer.emitterCells?.first,
              let dynamicEmitter = dynamicEmitter ?? dynamicEmitterLayer.emitterCells?.first else { return }
        let clearColor = color.withAlphaComponent(0.0).cgColor
        let whiteColor = NSColor.white.withAlphaComponent(0.35).cgColor
        let staticColors = [NSColor.white.withAlphaComponent(0.0).cgColor, whiteColor, resolvedColor, resolvedColor, clearColor]
        let dynamicColors = [whiteColor, color.withAlphaComponent(0.85).cgColor, resolvedColor, resolvedColor, clearColor]
        for (layer, emitter, colors) in [(staticEmitterLayer, staticEmitter, staticColors), (dynamicEmitterLayer, dynamicEmitter, dynamicColors)] {
            let behavior = createEmitterBehavior(type: "colorOverLife")
            behavior.setValue(colors, forKey: "colors")
            emitter.setValue([behavior], forKey: "emitterBehaviors")
            layer.emitterCells = [emitter]
        }
        currentColor = resolvedColor
    }

    public func update(speed: Float, delta: Float? = nil) {
        if speed > 0.0 {
            if self.dynamicEmitterLayer.birthRate.isZero {
                self.dynamicEmitterLayer.beginTime = CACurrentMediaTime()
            }
            
            self.dynamicEmitterLayer.setValue(Float(20.0 + speed * 1.4), forKeyPath: "emitterCells.emitter.birthRate")
            self.dynamicEmitterLayer.setValue(2.7 - min(1.1, 1.5 * speed / 120.0), forKeyPath: "emitterCells.emitter.lifetime")
            self.dynamicEmitterLayer.setValue(30.0 + CGFloat(speed / 80.0), forKeyPath: "emitterCells.emitter.velocity")
            
            if let delta, speed > 15.0 {
                self.dynamicEmitterLayer.setValue(delta > 0 ? .pi : 0, forKeyPath: "emitterCells.emitter.emissionLongitude")
                self.dynamicEmitterLayer.setValue(.pi / 2.0, forKeyPath: "emitterCells.emitter.emissionRange")
            } else {
                self.dynamicEmitterLayer.setValue(0.0, forKeyPath: "emitterCells.emitter.emissionLongitude")
                self.dynamicEmitterLayer.setValue(.pi * 2.0, forKeyPath: "emitterCells.emitter.emissionRange")
            }
            self.staticEmitterLayer.setValue(true, forKeyPath: "emitterBehaviors.attractor.enabled")
            
            self.dynamicEmitterLayer.birthRate = 1.0
            self.staticEmitterLayer.birthRate = 0.0
        } else {
            self.dynamicEmitterLayer.birthRate = 0.0
            
            if let staticEmitter = self.staticEmitterLayer.emitterCells?.first {
                staticEmitter.beginTime = CACurrentMediaTime()
            }
            self.staticEmitterLayer.birthRate = 1.0
            self.staticEmitterLayer.setValue(false, forKeyPath: "emitterBehaviors.attractor.enabled")
        }
    }
    
    public func update(size: CGSize, emitterPosition: CGPoint) {
        let needsSetup = self.staticEmitterLayer.emitterCells == nil || self.dynamicEmitterLayer.emitterCells == nil
        if needsSetup {
            self.setupEmitter()
        } else if color.type != .componentBased {
            updateEmitterColor()
        }
        let layout = CGRect(origin: emitterPosition, size: size)
        guard needsSetup || currentLayout != layout else { return }
        self.staticEmitterLayer.frame = CGRect(origin: .zero, size: size)
        self.staticEmitterLayer.emitterPosition = emitterPosition
        self.dynamicEmitterLayer.frame = CGRect(origin: .zero, size: size)
        self.dynamicEmitterLayer.emitterPosition = emitterPosition
        self.staticEmitterLayer.setValue(emitterPosition, forKeyPath: "emitterBehaviors.attractor.position")
        currentLayout = layout
    }
}

public struct Star_SliderAmount: Equatable {
    private let sliderSteps: [Int]
    public let maxRealValue: Int
    public let maxSliderValue: Int
    private let isLogarithmic: Bool
    
    public private(set) var realValue: Int
    public private(set) var sliderValue: Int
    
    public var minValue: Int = 1
    
    private static func makeSliderSteps(maxRealValue: Int, isLogarithmic: Bool, minValue: Int = 1) -> [Int] {
        if isLogarithmic {
            var sliderSteps: [Int] = [minValue, 10, 50, 100, 500, 1_000, 2_000, 5_000, 7_500, 10_000 ]
            sliderSteps.removeAll(where: { $0 >= maxRealValue })
            sliderSteps.append(maxRealValue)
            return sliderSteps
        } else {
            return [minValue, maxRealValue]
        }
    }
    
    private static func remapValueToSlider(realValue: Int, maxSliderValue: Int, steps: [Int]) -> Int {
        guard realValue >= steps.first!, realValue <= steps.last! else { return 0 }

        for i in 0 ..< steps.count - 1 {
            if realValue >= steps[i] && realValue <= steps[i + 1] {
                let range = steps[i + 1] - steps[i]
                let relativeValue = realValue - steps[i]
                let stepFraction = Float(relativeValue) / Float(range)
                return Int(Float(i) * Float(maxSliderValue) / Float(steps.count - 1)) + Int(stepFraction * Float(maxSliderValue) / Float(steps.count - 1))
            }
        }
        return maxSliderValue // Return max slider position if value equals the last step
    }

    private static func remapSliderToValue(sliderValue: Int, maxSliderValue: Int, steps: [Int]) -> Int {
        guard sliderValue >= 0, sliderValue <= maxSliderValue else { return steps.first! }

        let stepIndex = Int(Float(sliderValue) / Float(maxSliderValue) * Float(steps.count - 1))
        let fraction = Float(sliderValue) / Float(maxSliderValue) * Float(steps.count - 1) - Float(stepIndex)
        
        if stepIndex >= steps.count - 1 {
            return steps.last!
        } else {
            let range = steps[stepIndex + 1] - steps[stepIndex]
            return steps[stepIndex] + Int(fraction * Float(range))
        }
    }
    
    public init(realValue: Int, maxRealValue: Int, maxSliderValue: Int, isLogarithmic: Bool, minValue: Int = 1) {
        self.sliderSteps = Star_SliderAmount.makeSliderSteps(maxRealValue: maxRealValue, isLogarithmic: isLogarithmic, minValue: minValue)
        self.maxRealValue = maxRealValue
        self.maxSliderValue = maxSliderValue
        self.isLogarithmic = isLogarithmic
        self.minValue = minValue
        
        self.realValue = realValue
        self.sliderValue = Star_SliderAmount.remapValueToSlider(realValue: max(self.realValue, minValue), maxSliderValue: self.maxSliderValue, steps: self.sliderSteps)
    }
    
    public init(sliderValue: Int, maxRealValue: Int, maxSliderValue: Int, isLogarithmic: Bool, minValue: Int = 1) {
        self.sliderSteps = Star_SliderAmount.makeSliderSteps(maxRealValue: maxRealValue, isLogarithmic: isLogarithmic, minValue: minValue)
        self.maxRealValue = maxRealValue
        self.maxSliderValue = maxSliderValue
        self.isLogarithmic = isLogarithmic
        self.minValue = minValue
        
        self.sliderValue = sliderValue
        self.realValue = Star_SliderAmount.remapSliderToValue(sliderValue: self.sliderValue, maxSliderValue: self.maxSliderValue, steps: self.sliderSteps)
    }
    
    public func withRealValue(_ realValue: Int) -> Star_SliderAmount {
        return Star_SliderAmount(realValue: max(realValue, self.minValue), maxRealValue: self.maxRealValue, maxSliderValue: self.maxSliderValue, isLogarithmic: self.isLogarithmic, minValue: self.minValue)
    }
    
    public func withSliderValue(_ sliderValue: Int) -> Star_SliderAmount {
        
        let minSliderValue = self.withRealValue(self.minValue).sliderValue
        
        return Star_SliderAmount(sliderValue: max(sliderValue, minSliderValue), maxRealValue: self.maxRealValue, maxSliderValue: self.maxSliderValue, isLogarithmic: self.isLogarithmic, minValue: self.minValue)
    }
}

public final class Star_SliderView : Control {
    
    public let dotLayer = View(frame: NSMakeRect(0, 0, 28, 28))
    private var addCustomView_Dot: ImageView? = nil
    private var addCustomView_Line: ImageButton? = nil

    private let foregroundLayer = SimpleGradientLayer()
    public let emptyLayer = SimpleLayer()

    private let effectLayer = BadgeStarsViewEffect(frame: .zero)
    
    private var progress: CGFloat = 0.0
    
    public var updateProgress:((CGFloat, Bool)->Void)? = nil
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        dotLayer.layer?.cornerRadius = dotLayer.frame.width / 2.0
        
        self.layer?.cornerRadius = 15
        
        self.layer?.addSublayer(emptyLayer)
        self.layer?.addSublayer(foregroundLayer)
        addSubview(effectLayer)
        self.addSubview(dotLayer)
        
        emptyLayer.backgroundColor = theme.colors.listBackground.cgColor
        dotLayer.backgroundColor = theme.colors.background

        
        foregroundLayer.colors = starsGradient.map { $0.cgColor }
        foregroundLayer.startPoint = NSMakePoint(0, 0.5)
        foregroundLayer.endPoint = NSMakePoint(1, 0.2)

        
        foregroundLayer.cornerRadius = frameRect.height / 2
        
        
        var maybeFirst = true
        
        self.set(handler: { [weak self] control in
            let point = NSApp.currentEvent?.locationInWindow ?? .zero
            let converted = control.superview?.convert(point, from: nil) ?? .zero
            let isControl = control.superview?.hitTest(converted) == control
            self?.checkAndUpdate(maybeToBalance: isControl)
            maybeFirst = true
        }, for: .Down)
        
        self.set(handler: { [weak self] _ in
            self?.checkAndUpdate(maybeToBalance: maybeFirst)
            maybeFirst = false
        }, for: .MouseDragging)
        
        
        handleScrollEventOnInteractionEnabled = false
        
    }
    
    public func updateColors(_ gradient: [NSColor], effect: NSColor) {
        foregroundLayer.colors = gradient.map { $0.cgColor }
        self.effectLayer.color = effect
    }
    
    public override func scrollWheel(with event: NSEvent) {
        window?.scrollWheel(with: event)
        
        var scrollPoint = NSZeroPoint
        let isInverted: Bool = System.isScrollInverted

        if event.scrollingDeltaY != 0 {
            if isInverted {
                scrollPoint.x += -event.scrollingDeltaY
            } else {
                scrollPoint.x -= event.scrollingDeltaY
            }
        }
        
        if event.scrollingDeltaX != 0 {
            if !isInverted {
                scrollPoint.x -= -event.scrollingDeltaX
            } else {
                scrollPoint.x += event.scrollingDeltaX
            }
        }

        let percent = self.progress + (scrollPoint.x * (1 / 100))

        
        self.updateProgress?(min(max(0, percent), 1), false)
        
    }
    
    public func checkAndUpdate(maybeToBalance: Bool = false) {
        if var current = self.window?.mouseLocationOutsideOfEventStream {
            let width = self.frame.width - dotLayer.frame.width / 2
            current.x -= dotLayer.frame.width / 2
            let newValue = self.convert(current, from: nil)
            let percent = max(0, min(1, newValue.x / width))
                        
            self.updateProgress?(percent, maybeToBalance && self.progress < percent)
        }
    }
    
    public override func layout() {
        super.layout()
        
        
        emptyLayer.frame = bounds
        dotLayer.frame = NSMakeRect(1, 1, 26, 26)
        
        dotLayer.frame = NSMakeRect(max(2, min(2 + floor((frame.width - dotLayer.frame.width - 2) * progress), frame.width - dotLayer.frame.width - 2)), 2, dotLayer.frame.width, dotLayer.frame.height)
        
        foregroundLayer.frame = NSMakeRect(0, 0, dotLayer.frame.maxX + 2, frame.height)
        
        effectLayer.frame = bounds
        effectLayer.update(size: effectLayer.frame.size, emitterPosition: NSMakePoint(dotLayer.frame.midX, dotLayer.frame.midY))
        
        if let addCustomView_Dot {
            addCustomView_Dot.center()
        }
        if let addCustomView_Line {
            addCustomView_Line.centerY(x: frame.width - addCustomView_Line.frame.width - 3)
        }

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public func update(count: Int64, minValue: Int64, maxValue: Int64, addCustom: (()->Void)? = nil) {
        
        
//        if addCustom {
//            let current: ImageView
//            if let view = self.addCustomView_Dot {
//                current = view
//            } else {
//                current = ImageView()
//                dotLayer.addSubview(current)
//                self.addCustomView_Dot = current
//            }
//            current.image = TelegramThemeHooks.shared.image(.iconPremiumPlus).precomposed(self.effectLayer.color)
//            current.sizeToFit()
//        } else if let view = self.addCustomView_Dot {
//            performSubviewRemoval(view, animated: false)
//            self.addCustomView_Dot = nil
//        }
        
        if let addCustom {
            let current: ImageButton
            if let view = self.addCustomView_Line {
                current = view
            } else {
                current = ImageButton()
                current.autohighlight = false
                current.scaleOnClick = true
                current.setAccessibilityLabel(strings().voiceOverCommonAdd)
                addSubview(current)
                self.addCustomView_Line = current
            }
            current.set(image: TelegramThemeHooks.shared.image(.iconPremiumPlus).precomposed(theme.colors.grayIcon), for: .Normal)
            current.sizeToFit()
            current.setSingle(handler: { _ in
                addCustom()
            }, for: .Click)
        } else if let view = self.addCustomView_Line {
            performSubviewRemoval(view, animated: false)
            self.addCustomView_Line = nil
        }
        
        self.progress = CGFloat(max(minValue - 1, min(maxValue, count - 1))) / CGFloat(maxValue - 1)
        
        layout()
    }
}

public final class Star_BadgeView : View {
    private let shapeLayer = SimpleShapeLayer()
    private let foregroundLayer = SimpleGradientLayer()
    private let textView = InteractiveTextView()
    public private(set) var inlineView: InlineStickerView?
    private let container = View()
    private let effectLayer = StarsButtonEffectLayer()
    
    
    public private(set) var tailPosition: CGFloat = 0.0
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        textView.userInteractionEnabled = false
        
        foregroundLayer.colors = starsGradient.map { $0.cgColor }
        foregroundLayer.startPoint = NSMakePoint(0, 0.5)
        foregroundLayer.endPoint = NSMakePoint(1, 0.2)
        foregroundLayer.mask = shapeLayer
        
        
        self.layer?.masksToBounds = false
        self.foregroundLayer.masksToBounds = false
        
        
        self.layer?.addSublayer(foregroundLayer)


        self.layer?.masksToBounds = false
        
        shapeLayer.fillColor = NSColor.red.cgColor
        shapeLayer.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
        
        container.layer?.addSublayer(effectLayer)

        
        container.addSubview(textView)
        addSubview(container)
        container.layer?.masksToBounds = false
    }
    
    public func updateColors(_ gradient: [NSColor], effect: NSColor) {
        self.foregroundLayer.colors = gradient.map { $0.cgColor }
        self.effectLayer.color = effect
    }
    
    public func update(sliderValue: Int64, realValue: Int64, max maxValue: Int64, context: (any AccountContextProtocol), maxString: String? = nil) -> NSSize {
        
        
        if inlineView == nil {
            let view = InlineStickerView(account: context.account, file: LocalAnimatedSticker.star_currency_new.file, size: NSMakeSize(30, 30), getColors: { _ in
                return [.init(keyPath: "", color: .init(0xffffff))]
            }, playPolicy: .framesCount(1), controlContent: false, synchronyous: true)
            self.inlineView = view
            container.addSubview(view)
        }
        
        let attr = NSMutableAttributedString()
        
        let text: String
        if let maxString, realValue == maxValue {
            text = maxString
        } else {
            text = "\(realValue.formattedWithSeparator)"
        }
        
        attr.append(string: text, color: NSColor.white, font: .avatar(25))
        let textLayout = TextViewLayout(attr)
        textLayout.measure(width: .greatestFiniteMagnitude)
        self.textView.set(text: textLayout, context: context)

        
        container.setFrameSize(NSMakeSize(container.subviewsWidthSize.width + 2, container.subviewsWidthSize.height))
        
        self.tailPosition = max(0, min(1, CGFloat(sliderValue) / CGFloat(maxValue)))
                
        let size = NSMakeSize(max(100, container.frame.width + 30), frame.height)
        
        
        foregroundLayer.frame = size.bounds.insetBy(dx: 0, dy: -10)
        shapeLayer.frame = foregroundLayer.frame.focus(size)
        
        shapeLayer.path = generateRoundedRectWithTailPath(rectSize: size, tailPosition: tailPosition)
        
        return size
        
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: container, frame: container.centerFrameX(y: 1))

        if let inlineView {
            transition.updateFrame(view: inlineView, frame: inlineView.centerFrameY(x: 0, addition: -2))
            transition.updateFrame(view: textView, frame: textView.centerFrameY(x: inlineView.frame.maxX + 2))
        }
        
        effectLayer.frame = size.bounds.insetBy(dx: -20, dy: -20)
        effectLayer.update(size: size)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
     //   shapeLayer.frame = bounds
    }
}
