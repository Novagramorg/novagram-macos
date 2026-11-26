import Cocoa


public final class EdgeEffectView: View {

    public enum Edge {
        case top
        case bottom
    }

    public struct Blur {
        public let rect: NSRect
        public let edgeSize: CGFloat

        public init(rect: NSRect, edgeSize: CGFloat) {
            self.rect = rect
            self.edgeSize = edgeSize
        }
    }

    private static let blurRadius: CGFloat = 1.0
    private static let blurCaptureDensity: CGFloat = 1.5

    private let gradientLayer: SimpleGradientLayer
    private var horizontalMaskLayer: SimpleGradientLayer?
    private var appliedHorizontalMask: (bounds: NSRect, fade: CGFloat)?
    private var blurEffect: VariableBlurEffect?

    public override init() {
        self.gradientLayer = SimpleGradientLayer()
        super.init()
        commonInit()
    }

    public required init(frame frameRect: NSRect) {
        self.gradientLayer = SimpleGradientLayer()
        super.init(frame: frameRect)
        commonInit()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = false
        backgroundColor = .clear

        gradientLayer.type = .axial
        gradientLayer.frame = bounds
        layer?.addSublayer(gradientLayer)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBlurScale()
    }

    private struct AppliedGradient {
        let color: NSColor
        let alpha: CGFloat
        let edge: Edge
        let edgeSize: CGFloat
        let height: CGFloat
    }
    private var appliedGradient: AppliedGradient?

    public func update(color: NSColor, blur: Blur? = nil, alpha: CGFloat = 0.75, edge: Edge, edgeSize: CGFloat, rect: NSRect, transition: ContainedViewLayoutTransition, horizontalFade: CGFloat = 0) {
        let bounds = NSRect(origin: .zero, size: rect.size)
        transition.updateFrame(layer: gradientLayer, frame: bounds)
        applyHorizontalMask(bounds: bounds, fade: horizontalFade, transition: transition)
        updateBlur(frame: blur?.rect.offsetBy(dx: -rect.minX, dy: -rect.minY), edge: edge, edgeSize: blur?.edgeSize ?? 0, transition: transition)

        if let applied = appliedGradient, applied.color.isEqual(color), applied.alpha == alpha, applied.edge == edge, applied.edgeSize == edgeSize, applied.height == bounds.height {
            if case .immediate = transition {
                gradientLayer.removeAnimation(forKey: "colors")
                gradientLayer.removeAnimation(forKey: "locations")
            }
            return
        }
        appliedGradient = AppliedGradient(color: color, alpha: alpha, edge: edge, edgeSize: edgeSize, height: bounds.height)

        let solidFraction = max(0, min(1, 1.0 - edgeSize / max(1, bounds.height)))

        let steps = 32
        let solid = color.withAlphaComponent(alpha).cgColor
        var colors: [CGColor] = [solid, solid]
        var locations: [NSNumber] = [0.0, NSNumber(value: Double(solidFraction))]
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let a = alpha * (1.0 - t * t * t * (t * (t * 6 - 15) + 10))
            let loc = solidFraction + (1.0 - solidFraction) * t
            colors.append(color.withAlphaComponent(a).cgColor)
            locations.append(NSNumber(value: Double(loc)))
        }

        switch edge {
        case .bottom:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        case .top:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        }

        let presentation = gradientLayer.presentation()
        let fromColors = (presentation?.colors as? [CGColor]) ?? (gradientLayer.colors as? [CGColor]) ?? colors
        let fromLocations = presentation?.locations ?? gradientLayer.locations ?? locations

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.colors = colors
        gradientLayer.locations = locations
        CATransaction.commit()

        switch transition {
        case .immediate:
            gradientLayer.removeAnimation(forKey: "colors")
            gradientLayer.removeAnimation(forKey: "locations")
        case let .animated(duration, curve):
            let timing = CAMediaTimingFunction(name: curve.timingFunction)

            let colorAnim = CABasicAnimation(keyPath: "colors")
            colorAnim.fromValue = fromColors
            colorAnim.toValue = colors
            colorAnim.duration = duration
            colorAnim.timingFunction = timing
            colorAnim.fillMode = .forwards
            colorAnim.isRemovedOnCompletion = true
            gradientLayer.add(colorAnim, forKey: "colors")

            let locAnim = CABasicAnimation(keyPath: "locations")
            locAnim.fromValue = fromLocations
            locAnim.toValue = locations
            locAnim.duration = duration
            locAnim.timingFunction = timing
            locAnim.fillMode = .forwards
            locAnim.isRemovedOnCompletion = true
            gradientLayer.add(locAnim, forKey: "locations")
        }
    }

    private func updateBlur(frame: NSRect?, edge: Edge, edgeSize: CGFloat, transition: ContainedViewLayoutTransition) {
        guard let frame = frame else {
            if let blurEffect = self.blurEffect {
                blurEffect.layer.removeFromSuperlayer()
                self.blurEffect = nil
            }
            return
        }

        var blurTransition = transition
        let blurEffect: VariableBlurEffect
        if let current = self.blurEffect {
            blurEffect = current
        } else {
            guard let created = VariableBlurEffect(maxBlurRadius: EdgeEffectView.blurRadius) else {
                return
            }
            blurEffect = created
            self.blurEffect = created
            layer?.insertSublayer(created.layer, below: gradientLayer)
            updateBlurScale()
            blurTransition = .immediate
        }
        blurEffect.update(frame: frame, gradientHeight: min(frame.height, max(1.0, edgeSize)), position: edge == .bottom ? .top : .bottom, transition: blurTransition)
    }

    private func updateBlurScale() {
        guard let blurEffect = self.blurEffect else {
            return
        }
        let scale = window?.backingScaleFactor ?? System.backingScale
        blurEffect.backdropScale = min(1.0, EdgeEffectView.blurCaptureDensity / scale)
        blurEffect.maskScale = scale
    }

    /// Applies (or removes) a horizontal alpha mask on `gradientLayer` so the
    /// shadow tapers off at the left/right edges. `fade` is the fraction of
    /// the total width that fades to transparent on each side (0…0.5).
    /// `0` removes the mask entirely.
    private func applyHorizontalMask(bounds: NSRect, fade: CGFloat, transition: ContainedViewLayoutTransition) {
        let clamped = max(0, min(0.5, fade))
        guard clamped > 0 else {
            if horizontalMaskLayer != nil {
                gradientLayer.mask = nil
                horizontalMaskLayer = nil
                appliedHorizontalMask = nil
            }
            return
        }
        if horizontalMaskLayer != nil, let applied = appliedHorizontalMask, applied.bounds == bounds, applied.fade == clamped {
            return
        }
        appliedHorizontalMask = (bounds, clamped)
        let mask: SimpleGradientLayer
        if let existing = horizontalMaskLayer {
            mask = existing
        } else {
            mask = SimpleGradientLayer()
            mask.type = .axial
            mask.startPoint = CGPoint(x: 0, y: 0.5)
            mask.endPoint = CGPoint(x: 1, y: 0.5)
            horizontalMaskLayer = mask
            gradientLayer.mask = mask
        }

        let clear = NSColor.white.withAlphaComponent(0).cgColor
        let solid = NSColor.white.cgColor

        // Smootherstep ramp on each side instead of two-stop linear so the
        // taper matches the visual softness of the vertical gradient above.
        let steps = 12
        var colors: [CGColor] = []
        var locations: [NSNumber] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let smooth = t * t * t * (t * (t * 6 - 15) + 10)
            let alpha = smooth
            colors.append(NSColor.white.withAlphaComponent(alpha).cgColor)
            locations.append(NSNumber(value: Double(clamped * t)))
        }
        colors.append(solid)
        locations.append(NSNumber(value: Double(1 - clamped)))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let smooth = t * t * t * (t * (t * 6 - 15) + 10)
            let alpha = 1 - smooth
            colors.append(NSColor.white.withAlphaComponent(alpha).cgColor)
            locations.append(NSNumber(value: Double(1 - clamped + clamped * t)))
        }
        _ = clear

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.colors = colors
        mask.locations = locations
        CATransaction.commit()
    }
}

private let _ee2_backdropLayerClass: CALayer.Type? = NSClassFromString(("CA" as NSString).appendingFormat("BackdropLayer") as String) as? CALayer.Type

public func ee2_createBackdropLayer() -> CALayer? {
    return _ee2_backdropLayerClass?.init()
}

private let _ee2_caFilterClass: AnyClass? = NSClassFromString("CAFilter")

/// Dynamic class-method dispatch for the private `CAFilter` factory. Tries
/// `filterWithType:` first (used by the iOS MaskedVariableBlurView snippet),
/// then falls back to `filterWithName:` (used by the iOS UIKitUtils path).
/// Both exist on different macOS versions.
private func _ee2_makeFilter(named name: String) -> NSObject? {
    guard let cls = _ee2_caFilterClass else {
        #if DEBUG
        NSLog("[EE2/_ee2_makeFilter] CAFilter class not found")
        #endif
        return nil
    }
    guard let filterClass = cls as AnyObject as? NSObjectProtocol else {
        #if DEBUG
        NSLog("[EE2/_ee2_makeFilter] CAFilter class doesn't conform to NSObjectProtocol")
        #endif
        return nil
    }

    let typeSelector = Selector(("filterWithType:"))
    if filterClass.responds(to: typeSelector) {
        if let result = filterClass.perform(typeSelector, with: name)?.takeUnretainedValue() as? NSObject {
            return result
        }
    }

    let nameSelector = NSSelectorFromString("filterWithName:")
    if filterClass.responds(to: nameSelector) {
        if let result = filterClass.perform(nameSelector, with: name)?.takeUnretainedValue() as? NSObject {
            return result
        }
    }

    #if DEBUG
    NSLog("[EE2/_ee2_makeFilter] neither filterWithType: nor filterWithName: responded for '\(name)'")
    #endif
    return nil
}

/// Private `CAFilter(name: "variableBlur")` — same private CoreAnimation filter that iOS
/// uses. Returns nil if the OS lacks the symbol.
public func ee2_makeVariableBlurFilter() -> NSObject? {
    return _ee2_makeFilter(named: "variableBlur")
}

/// Private `CAFilter(name: "gaussianBlur")`.
public func ee2_makeBlurFilter() -> NSObject? {
    return _ee2_makeFilter(named: "gaussianBlur")
}

private final class _EE2SimpleLayerDelegate: NSObject, CALayerDelegate {
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return NSNull()
    }
}

private let _ee2_edgeGradientAlphas: [CGFloat] = [
    0.8470588235294118, 0.8431372549019608, 0.8392156862745098, 0.8352941176470589,
    0.8313725490196078, 0.8274509803921568, 0.8235294117647058, 0.8196078431372549,
    0.8156862745098039, 0.8117647058823529, 0.807843137254902, 0.803921568627451,
    0.8, 0.7960784313725491, 0.792156862745098, 0.788235294117647,
    0.7843137254901961, 0.7803921568627451, 0.7764705882352941, 0.7725490196078432,
    0.7686274509803921, 0.7647058823529411, 0.7607843137254902, 0.7568627450980392,
    0.7529411764705882, 0.7490196078431373, 0.7450980392156863, 0.7411764705882353,
    0.7372549019607844, 0.7333333333333334, 0.7294117647058824, 0.7254901960784313,
    0.7215686274509804, 0.7176470588235294, 0.7137254901960784, 0.7098039215686274,
    0.7019607843137254, 0.6941176470588235, 0.6862745098039216, 0.6784313725490196,
    0.6705882352941177, 0.6588235294117647, 0.6509803921568628, 0.6431372549019607,
    0.6313725490196078, 0.6235294117647059, 0.615686274509804, 0.603921568627451,
    0.596078431372549, 0.5882352941176471, 0.5764705882352941, 0.5647058823529412,
    0.5529411764705883, 0.5411764705882354, 0.5294117647058824, 0.5176470588235293,
    0.5058823529411764, 0.49411764705882355, 0.4862745098039216, 0.4745098039215686,
    0.4627450980392157, 0.4549019607843138, 0.44313725490196076, 0.43137254901960786,
    0.41960784313725485, 0.4117647058823529, 0.4, 0.388235294117647,
    0.3764705882352941, 0.3647058823529412, 0.3529411764705882, 0.3411764705882353,
    0.3294117647058824, 0.3176470588235294, 0.3058823529411765, 0.2941176470588235,
    0.2823529411764706, 0.2705882352941177, 0.2588235294117647, 0.2431372549019608,
    0.2313725490196078, 0.21568627450980393, 0.19999999999999996, 0.18039215686274512,
    0.16078431372549018, 0.14117647058823535, 0.11764705882352944, 0.09019607843137256,
    0.04705882352941182, 0.0
]

private let _ee2_edgeGradientLocations: [CGFloat] = [
    0.0, 0.020905923344947737, 0.059233449477351915, 0.08710801393728224,
    0.10801393728222997, 0.12195121951219512, 0.13240418118466898, 0.14285714285714285,
    0.15331010452961671, 0.1602787456445993, 0.17073170731707318, 0.18118466898954705,
    0.1916376306620209, 0.20209059233449478, 0.20905923344947736, 0.21254355400696864,
    0.21951219512195122, 0.2264808362369338, 0.23344947735191637, 0.23693379790940766,
    0.24390243902439024, 0.24738675958188153, 0.25435540069686413, 0.2578397212543554,
    0.2613240418118467, 0.2682926829268293, 0.27177700348432055, 0.27526132404181186,
    0.28222996515679444, 0.2857142857142857, 0.289198606271777, 0.2926829268292683,
    0.2961672473867596, 0.29965156794425085, 0.30313588850174217, 0.30662020905923343,
    0.313588850174216, 0.3205574912891986, 0.32752613240418116, 0.3344947735191638,
    0.34146341463414637, 0.34843205574912894, 0.3554006968641115, 0.3623693379790941,
    0.3693379790940767, 0.37630662020905925, 0.3797909407665505, 0.3867595818815331,
    0.39372822299651566, 0.397212543554007, 0.40418118466898956, 0.41114982578397213,
    0.4181184668989547, 0.4250871080139373, 0.43205574912891986, 0.43902439024390244,
    0.445993031358885, 0.4529616724738676, 0.4564459930313589, 0.4634146341463415,
    0.47038327526132406, 0.4738675958188153, 0.4808362369337979, 0.4878048780487805,
    0.49477351916376305, 0.49825783972125437, 0.5052264808362369, 0.5121951219512195,
    0.519163763066202, 0.5261324041811847, 0.5331010452961672, 0.5400696864111498,
    0.5470383275261324, 0.554006968641115, 0.5609756097560976, 0.5679442508710801,
    0.5749128919860628, 0.5818815331010453, 0.5888501742160279, 0.5993031358885017,
    0.6062717770034843, 0.6167247386759582, 0.627177700348432, 0.6411149825783972,
    0.6585365853658537, 0.6759581881533101, 0.6968641114982579, 0.7282229965156795,
    0.7909407665505227, 1.0
]

private let _ee2_edgeMaskGradient: CGGradient? = {
    let norm = _ee2_edgeGradientAlphas.max() ?? 1.0
    let colors = _ee2_edgeGradientAlphas.map { NSColor(white: 0, alpha: $0 / norm).cgColor } as CFArray
    return CGGradient(colorsSpace: deviceColorSpace, colors: colors, locations: _ee2_edgeGradientLocations)
}()

final class VariableBlurEffect {
    enum Position {
        case top
        case bottom
    }

    private struct MaskKey: Equatable {
        let height: CGFloat
        let gradientHeight: CGFloat
        let position: Position
        let scale: CGFloat
    }

    private static let maskSourceName = "mask_source"
    private static let maxMaskHeight: CGFloat = 2048.0

    let layer: CALayer
    private let maxBlurRadius: CGFloat
    private let maskSourceLayer: CALayer?
    private let layerDelegate = _EE2SimpleLayerDelegate()
    private var maskKey: MaskKey?
    private var maskImage: CGImage?

    var backdropScale: CGFloat = 0 {
        didSet {
            if backdropScale != oldValue {
                layer.setValue(backdropScale, forKey: "scale")
            }
        }
    }
    var maskScale: CGFloat = System.backingScale

    init?(maxBlurRadius: CGFloat) {
        guard let layer = ee2_createBackdropLayer() else {
            return nil
        }
        self.layer = layer
        self.maxBlurRadius = maxBlurRadius
        if #available(macOS 26.0, *) {
            let maskSourceLayer = CALayer()
            maskSourceLayer.name = VariableBlurEffect.maskSourceName
            self.maskSourceLayer = maskSourceLayer
        } else {
            self.maskSourceLayer = nil
        }

        layer.delegate = layerDelegate
        if let maskSourceLayer = self.maskSourceLayer {
            maskSourceLayer.delegate = layerDelegate
            layer.addSublayer(maskSourceLayer)
        }
        applyFilter()
    }

    private func applyFilter() {
        guard let variableBlur = ee2_makeVariableBlurFilter() else {
            return
        }
        variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")
        if maskSourceLayer != nil {
            variableBlur.setValue(VariableBlurEffect.maskSourceName, forKey: "inputSourceSublayerName")
        } else {
            guard let maskImage = self.maskImage else {
                return
            }
            variableBlur.setValue(maskImage, forKey: "inputMaskImage")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.filters = [variableBlur]
        CATransaction.commit()
    }

    func update(frame: CGRect, gradientHeight: CGFloat, position: Position, transition: ContainedViewLayoutTransition) {
        let maskKey = MaskKey(height: frame.height, gradientHeight: gradientHeight, position: position, scale: maskScale)
        if maskKey != self.maskKey {
            self.maskKey = maskKey
            maskImage = VariableBlurEffect.generateMaskImage(height: frame.height, gradientHeight: gradientHeight, position: position, scale: maskScale)
            if let maskSourceLayer = self.maskSourceLayer {
                maskSourceLayer.contents = maskImage
            } else {
                applyFilter()
            }
        }
        transition.updateFrame(layer: layer, frame: frame)
        if let maskSourceLayer = self.maskSourceLayer {
            transition.updateFrame(layer: maskSourceLayer, frame: CGRect(origin: .zero, size: frame.size))
        }
    }

    private static func generateMaskImage(height: CGFloat, gradientHeight: CGFloat, position: Position, scale: CGFloat) -> CGImage? {
        let maskHeight = max(1.0, min(maxMaskHeight, height))
        let verticalScale = maskHeight / max(1.0, height)
        return generateImage(CGSize(width: 1.0, height: maskHeight), scale: scale, rotatedContext: { size, context in
            context.clear(CGRect(origin: .zero, size: size))

            let scaledGradientHeight = min(size.height, max(0.0, gradientHeight * verticalScale))
            let gradientFrame: CGRect
            let solidFrame: CGRect
            switch position {
            case .top:
                gradientFrame = CGRect(x: 0, y: size.height - scaledGradientHeight, width: size.width, height: scaledGradientHeight)
                solidFrame = CGRect(x: 0, y: 0, width: size.width, height: size.height - scaledGradientHeight)
            case .bottom:
                gradientFrame = CGRect(x: 0, y: 0, width: size.width, height: scaledGradientHeight)
                solidFrame = CGRect(x: 0, y: scaledGradientHeight, width: size.width, height: size.height - scaledGradientHeight)
            }

            context.setFillColor(NSColor(white: 0, alpha: 1).cgColor)
            context.fill(solidFrame)

            guard let gradient = _ee2_edgeMaskGradient, gradientFrame.height > 0 else {
                return
            }
            let isInverted = position == .bottom
            context.saveGState()
            context.clip(to: gradientFrame)
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: isInverted ? gradientFrame.maxY : gradientFrame.minY), end: CGPoint(x: 0, y: isInverted ? gradientFrame.minY : gradientFrame.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        })
    }
}
