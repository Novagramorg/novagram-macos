import Foundation
import simd

public enum LiquidGlassShapeKind: Int32 {
    case crest = 0
    case radial = 1
}

public enum LiquidGlassRenderMode: Int32 {
    case plain = 0
    case glass = 1
    case flat = 2
}

public struct LiquidGlassLayerStyle: Equatable {
    public var alpha: Float
    public var fill: Float
    public var saturation: Float
    public var matte: Float
    public var rim: Float
    public var refracts: Bool
    public var plainAlpha: Float

    public init(alpha: Float, fill: Float, saturation: Float, matte: Float, rim: Float, refracts: Bool, plainAlpha: Float) {
        self.alpha = alpha
        self.fill = fill
        self.saturation = saturation
        self.matte = matte
        self.rim = rim
        self.refracts = refracts
        self.plainAlpha = plainAlpha
    }
}

public struct LiquidGlassShapesAppearance: Equatable {
    public var layers: [LiquidGlassLayerStyle]
    public var shadowStrength: Float
    public var shadowBlur: Float
    public var shadowDrop: Float
    public var rimWidth: Float
    public var rimDarkAppearanceScale: Float
    public var glassBand: Float
    public var glassShift: Float

    public init(layers: [LiquidGlassLayerStyle], shadowStrength: Float, shadowBlur: Float, shadowDrop: Float, rimWidth: Float, rimDarkAppearanceScale: Float, glassBand: Float, glassShift: Float) {
        precondition(layers.count == 3)
        self.layers = layers
        self.shadowStrength = shadowStrength
        self.shadowBlur = shadowBlur
        self.shadowDrop = shadowDrop
        self.rimWidth = rimWidth
        self.rimDarkAppearanceScale = rimDarkAppearanceScale
        self.glassBand = glassBand
        self.glassShift = glassShift
    }
}

public enum LiquidGlassShapesConstants {
    public static let crestPointCount = 6
    public static let crestSampleCount = 128
    public static let radialPointCount = 8
    public static let radialSampleCount = 256
    public static let displacementAmount: Float = 32.0
}

public typealias LiquidGlassCrestPoints = (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)

public struct LiquidGlassCrestShape {
    public var fromPoints: LiquidGlassCrestPoints
    public var toPoints: LiquidGlassCrestPoints
    public var progress: Float
    public var offset: Float

    public init(fromPoints: LiquidGlassCrestPoints, toPoints: LiquidGlassCrestPoints, progress: Float, offset: Float) {
        self.fromPoints = fromPoints
        self.toPoints = toPoints
        self.progress = progress
        self.offset = offset
    }

    public static var flat: LiquidGlassCrestShape {
        let segment = 1.0 / Float(LiquidGlassShapesConstants.crestPointCount - 1)
        let points: LiquidGlassCrestPoints = (SIMD2(0.0, 0.0), SIMD2(segment, 0.0), SIMD2(segment * 2.0, 0.0), SIMD2(segment * 3.0, 0.0), SIMD2(segment * 4.0, 0.0), SIMD2(1.0, 0.0))
        return LiquidGlassCrestShape(fromPoints: points, toPoints: points, progress: 0.0, offset: 0.0)
    }
}

public struct LiquidGlassCrestParameters {
    public var shapes: (LiquidGlassCrestShape, LiquidGlassCrestShape, LiquidGlassCrestShape)
    public var width: Float
    public var restY: Float
    public var amplitude: Float
    public var smoothness: Float

    public init(shapes: (LiquidGlassCrestShape, LiquidGlassCrestShape, LiquidGlassCrestShape), width: Float, restY: Float, amplitude: Float, smoothness: Float) {
        self.shapes = shapes
        self.width = width
        self.restY = restY
        self.amplitude = amplitude
        self.smoothness = smoothness
    }
}

public typealias LiquidGlassRadialPoints = (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)

public struct LiquidGlassRadialShape {
    public var fromPoints: LiquidGlassRadialPoints
    public var toPoints: LiquidGlassRadialPoints
    public var progress: Float
    public var scale: Float

    public init(fromPoints: LiquidGlassRadialPoints, toPoints: LiquidGlassRadialPoints, progress: Float, scale: Float) {
        self.fromPoints = fromPoints
        self.toPoints = toPoints
        self.progress = progress
        self.scale = scale
    }

    public static func circle(scale: Float) -> LiquidGlassRadialShape {
        func point(_ index: Int) -> SIMD2<Float> {
            let angle = 2.0 * Double.pi * Double(index) / Double(LiquidGlassShapesConstants.radialPointCount)
            return SIMD2<Float>(Float(sin(angle) * 0.5), Float(cos(angle) * 0.5))
        }
        let points: LiquidGlassRadialPoints = (point(0), point(1), point(2), point(3), point(4), point(5), point(6), point(7))
        return LiquidGlassRadialShape(fromPoints: points, toPoints: points, progress: 0.0, scale: scale)
    }
}

public struct LiquidGlassRadialParameters {
    public var shapes: (LiquidGlassRadialShape, LiquidGlassRadialShape, LiquidGlassRadialShape)
    public var size: Float
    public var smoothness: Float

    public init(shapes: (LiquidGlassRadialShape, LiquidGlassRadialShape, LiquidGlassRadialShape), size: Float, smoothness: Float) {
        self.shapes = shapes
        self.size = size
        self.smoothness = smoothness
    }
}

public enum LiquidGlassShapeSet {
    case crest(LiquidGlassCrestParameters)
    case radial(LiquidGlassRadialParameters, center: SIMD2<Float>)

    public init(parameters: LiquidGlassRadialParameters, center: SIMD2<Float>) {
        self = .radial(parameters, center: center)
    }
}

public struct LiquidGlassShapesUniforms {
    public var gradientColor0: SIMD4<Float>
    public var gradientColor1: SIMD4<Float>
    public var layerStyle: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    public var layerRimGlass: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    public var boundsSize: SIMD2<Float>
    public var renderSize: SIMD2<Float>
    public var edgeInset: Float
    public var gradientLength: Float
    public var crestSpacing: Float
    public var shadowStrength: Float
    public var shadowSigma: Float
    public var shadowDrop: Float
    public var rimScale: Float
    public var rimWidth: Float
    public var glassBand: Float
    public var glassShift: Float
    public var glassAmount: Float
    public var mode: Int32
    public var shapeCenter: SIMD2<Float>
    private var alignmentPadding = SIMD2<Float>()

    public init(appearance: LiquidGlassShapesAppearance, colors: (SIMD4<Float>, SIMD4<Float>), boundsSize: CGSize, gradientLength: CGFloat, shapeCenter: SIMD2<Float>, mode: LiquidGlassRenderMode, isDarkAppearance: Bool, edgeInset: Float) {
        func styleVector(_ style: LiquidGlassLayerStyle) -> SIMD4<Float> {
            return SIMD4<Float>(style.alpha, style.fill, style.saturation, style.matte)
        }
        func rimGlassVector(_ style: LiquidGlassLayerStyle) -> SIMD4<Float> {
            return SIMD4<Float>(style.rim, style.refracts ? 1.0 : 0.0, style.plainAlpha, 0.0)
        }
        let layers = appearance.layers
        self.gradientColor0 = colors.0
        self.gradientColor1 = colors.1
        self.layerStyle = (styleVector(layers[0]), styleVector(layers[1]), styleVector(layers[2]))
        self.layerRimGlass = (rimGlassVector(layers[0]), rimGlassVector(layers[1]), rimGlassVector(layers[2]))
        self.boundsSize = SIMD2<Float>(Float(boundsSize.width), Float(boundsSize.height))
        self.renderSize = SIMD2<Float>()
        self.edgeInset = edgeInset
        self.gradientLength = Float(gradientLength)
        self.crestSpacing = Float(boundsSize.width / CGFloat(LiquidGlassShapesConstants.crestSampleCount - 1))
        self.shadowStrength = appearance.shadowStrength
        self.shadowSigma = appearance.shadowBlur
        self.shadowDrop = appearance.shadowDrop
        self.rimScale = isDarkAppearance ? appearance.rimDarkAppearanceScale : 1.0
        self.rimWidth = appearance.rimWidth
        self.glassBand = appearance.glassBand
        self.glassShift = appearance.glassShift
        self.glassAmount = LiquidGlassShapesConstants.displacementAmount
        self.mode = mode.rawValue
        self.shapeCenter = shapeCenter
    }
}
