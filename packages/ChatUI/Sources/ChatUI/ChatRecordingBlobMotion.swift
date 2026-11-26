import Foundation
import TGUIKit
import SceneEffects

enum ChatRecordingBlobAppearance {
    static let maxLevel: CGFloat = 4.0
    static let levelSmoothing: CGFloat = 0.9
    static let centreScale: Float = 0.45
    static let restingPresence: CGFloat = 0.75
    static let presenceInDuration: Double = 0.35
    static let presenceOutDuration: Double = 0.15
    static let smoothness: Float = {
        let angle = 2.0 * Double.pi / Double(LiquidGlassShapesConstants.radialPointCount)
        return Float(((4.0 / 3.0) * tan(angle / 4.0)) / sin(angle / 2.0) / 2.0)
    }()

    static let goldenRatio: CGFloat = (1.0 + sqrt(5.0)) / 2.0
    static let outerWaveScales: ClosedRange<CGFloat> = (0.57 * 1.1) ... (CGFloat(centreScale) * goldenRatio * goldenRatio)
    static let waveMotion = ChatRecordingBlobMotion.Parameters(minRandomness: 1.0, maxRandomness: 1.0, minSpeed: 0.9, maxSpeed: 4.0)

    static func easing(_ value: CGFloat) -> CGFloat {
        return bezierPoint(0.42, 0.0, 0.58, 1.0, value)
    }

    static func side(centreDiameter: CGFloat) -> CGFloat {
        return centreDiameter / CGFloat(centreScale)
    }

    static func appearance(mode: LiquidGlassRenderMode, isDarkAppearance: Bool) -> LiquidGlassShapesAppearance {
        return LiquidGlassShapesAppearance(
            layers: [
                LiquidGlassLayerStyle(alpha: 0.35, fill: 0.5, saturation: 0.0, matte: 0.0, rim: 0.3, refracts: true, plainAlpha: 0.15),
                LiquidGlassLayerStyle(alpha: 0.55, fill: 0.5, saturation: 0.0, matte: 0.0, rim: 0.3, refracts: true, plainAlpha: 0.30),
                LiquidGlassLayerStyle(alpha: 1.0, fill: 0.0, saturation: 1.0, matte: isDarkAppearance ? 0.82 : 0.685, rim: 0.3, refracts: true, plainAlpha: 1.0)
            ],
            shadowStrength: mode == .glass ? 0.07 : 0.0,
            shadowBlur: 6.0,
            shadowDrop: 2.0,
            rimWidth: 1.0,
            rimDarkAppearanceScale: 0.45,
            glassBand: 20.0,
            glassShift: 10.0
        )
    }

    static func overflow(side: CGFloat) -> CGFloat {
        let appearance = ChatRecordingBlobAppearance.appearance(mode: .glass, isDarkAppearance: false)
        let outlineReach = side * 0.5 * ChatRecordingBlobAppearance.outerWaveScales.upperBound * 1.05
        return ceil(max(0.0, outlineReach - side * 0.5) + CGFloat(appearance.shadowDrop + 3.0 * appearance.shadowBlur + appearance.rimWidth * 0.5))
    }

    static func radialParameters(outer: ChatRecordingBlobMotion?, middle: ChatRecordingBlobMotion?, size: Float, level: CGFloat, presence: CGFloat, easing: (CGFloat) -> CGFloat) -> LiquidGlassRadialParameters {
        let centre = LiquidGlassRadialShape.circle(scale: ChatRecordingBlobAppearance.centreScale)
        let scales = ChatRecordingBlobAppearance.outerWaveScales
        let outerScale = (scales.lowerBound + (scales.upperBound - scales.lowerBound) * level) * presence
        let middleScale = sqrt(CGFloat(ChatRecordingBlobAppearance.centreScale) * outerScale)
        return LiquidGlassRadialParameters(
            shapes: (
                outer?.radialShape(scale: outerScale, easing: easing) ?? centre,
                middle?.radialShape(scale: middleScale, easing: easing) ?? centre,
                centre
            ),
            size: size,
            smoothness: ChatRecordingBlobAppearance.smoothness
        )
    }
}

final class ChatRecordingBlobMotion {
    struct Parameters {
        var minRandomness: CGFloat
        var maxRandomness: CGFloat
        var minSpeed: CGFloat
        var maxSpeed: CGFloat
    }

    let parameters: Parameters
    private let random: () -> CGFloat

    private(set) var fromPoints: [SIMD2<Float>] = []
    private(set) var toPoints: [SIMD2<Float>] = []
    private(set) var duration: CGFloat = 1.0
    private var elapsed: CGFloat = 0.0
    private var speedLevel: CGFloat = 0.0

    init(parameters: Parameters, random: @escaping () -> CGFloat = { CGFloat.random(in: 0.0 ..< 1.0) }) {
        self.parameters = parameters
        self.random = random

        self.fromPoints = self.generatePoints()
        self.startNextShape()
    }

    func updateSpeedLevel(_ level: CGFloat) {
        self.speedLevel = max(self.speedLevel, level)
    }

    func advance(by deltaTime: CGFloat) {
        self.elapsed += deltaTime
        while self.elapsed >= self.duration {
            self.elapsed -= self.duration
            self.fromPoints = self.toPoints
            self.startNextShape()
        }
    }

    func radialShape(scale: CGFloat, easing: (CGFloat) -> CGFloat) -> LiquidGlassRadialShape {
        func radialPoints(_ points: [SIMD2<Float>]) -> LiquidGlassRadialPoints {
            return (points[0], points[1], points[2], points[3], points[4], points[5], points[6], points[7])
        }
        let progress = easing(max(0.0, min(1.0, self.elapsed / self.duration)))
        return LiquidGlassRadialShape(fromPoints: radialPoints(self.fromPoints), toPoints: radialPoints(self.toPoints), progress: Float(progress), scale: Float(scale))
    }

    private func startNextShape() {
        self.toPoints = self.generatePoints()
        let speed = self.parameters.minSpeed + (self.parameters.maxSpeed - self.parameters.minSpeed) * self.speedLevel
        self.duration = 1.0 / max(speed, 0.05)
        self.speedLevel = 0.0
    }

    private func generatePoints() -> [SIMD2<Float>] {
        let randomness = self.parameters.minRandomness + (self.parameters.maxRandomness - self.parameters.minRandomness) * self.speedLevel
        let count = LiquidGlassShapesConstants.radialPointCount
        let angle = 2.0 * CGFloat.pi / CGFloat(count)
        let rangeStart = 1.0 / (1.0 + randomness / 10.0)
        let startAngle = angle * self.random()
        return (0 ..< count).map { index -> SIMD2<Float> in
            let radius = (rangeStart + self.random() * (1.0 - rangeStart)) / 2.0
            let angleRandomness = angle * 0.1
            let pointAngle = angle + angle * (angleRandomness * self.random() - angleRandomness * 0.5)
            let pointAngleFromStart = startAngle + CGFloat(index) * pointAngle
            return SIMD2<Float>(Float(sin(pointAngleFromStart) * radius), Float(cos(pointAngleFromStart) * radius))
        }
    }
}

struct ChatRecordingBlobPresence {
    private(set) var value: CGFloat
    private var from: CGFloat
    private var target: CGFloat
    private var elapsed: Double = 0.0
    private var duration: Double = 0.0
    private let easing: (CGFloat) -> CGFloat

    init(value: CGFloat, easing: @escaping (CGFloat) -> CGFloat) {
        self.value = value
        self.from = value
        self.target = value
        self.easing = easing
    }

    var isSettled: Bool {
        return self.elapsed >= self.duration
    }

    mutating func animate(to target: CGFloat, duration: Double, canAdvance: Bool = true) {
        if !canAdvance {
            self.settle(at: target)
            return
        }
        self.from = self.value
        self.target = target
        self.elapsed = 0.0
        self.duration = duration
    }

    mutating func settle(at value: CGFloat) {
        self.value = value
        self.from = value
        self.target = value
        self.elapsed = 0.0
        self.duration = 0.0
    }

    mutating func advance(by deltaTime: Double) {
        if self.isSettled {
            return
        }
        self.elapsed = min(self.duration, self.elapsed + deltaTime)
        self.value = self.from + (self.target - self.from) * self.easing(CGFloat(self.elapsed / self.duration))
    }
}
