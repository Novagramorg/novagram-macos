import Cocoa
import TGUIKit
import SceneEffects

final class CallStatusBarWavesView: View {
    static let bottomOverflow: CGFloat = {
        let maxRandomness = CallStatusBarWavesView.waveMotions.map(\.maxRandomness).max() ?? 0.0
        let maxOffset = CallStatusBarWavesView.waveMotions.map(\.maxOffset).max() ?? 0.0
        let appearance = CallStatusBarWavesAppearance.appearance
        let deepestCrest = Constants.amplitude * maxRandomness * 0.25 * 1.3 + Constants.travel * maxOffset
        let shadowReach = CGFloat(appearance.shadowDrop + 3.0 * appearance.shadowBlur)
        return ceil(deepestCrest + shadowReach + CGFloat(appearance.rimWidth) * 0.5)
    }()

    private enum Constants {
        static let smoothness: CGFloat = 0.5
        static let amplitude: CGFloat = 20.0
        static let travel: CGFloat = 16.0
        static let levelSmoothing: CGFloat = 0.93
        static let maxLevel: CGFloat = 1.5
        static let speedMultiplier: CGFloat = 0.85
    }

    private struct WaveMotion {
        var minRandomness: CGFloat
        var maxRandomness: CGFloat
        var minSpeed: CGFloat
        var maxSpeed: CGFloat
        var minOffset: CGFloat
        var maxOffset: CGFloat
    }

    private static let waveMotions: [WaveMotion] = [
        WaveMotion(minRandomness: 1.2, maxRandomness: 1.7, minSpeed: 1.0, maxSpeed: 5.8, minOffset: 0.1, maxOffset: 1.0),
        WaveMotion(minRandomness: 1.2, maxRandomness: 1.5, minSpeed: 1.0, maxSpeed: 4.4, minOffset: 0.1, maxOffset: 0.55),
        WaveMotion(minRandomness: 1.0, maxRandomness: 1.3, minSpeed: 0.9, maxSpeed: 3.2, minOffset: 0.0, maxOffset: 0.0)
    ]

    private final class Wave {
        let motion: WaveMotion

        private var fromPoints: [CGPoint]
        private var toPoints: [CGPoint]
        private var elapsed: CGFloat = 0.0
        private var duration: CGFloat = 1.0
        private var speedLevel: CGFloat = 0.0

        init(motion: WaveMotion) {
            self.motion = motion
            self.fromPoints = []
            self.toPoints = []

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

        func crestShape(level: CGFloat, inset: CGFloat) -> LiquidGlassCrestShape {
            var offset: CGFloat = 0.0
            if self.motion.minOffset > 0.0 {
                offset = (self.motion.minOffset + (self.motion.maxOffset - self.motion.minOffset) * level) * Constants.travel
            }
            let lift = offset / Constants.amplitude

            func crestPoints(_ points: [CGPoint]) -> LiquidGlassCrestPoints {
                func point(_ index: Int) -> SIMD2<Float> {
                    let isEnd = index == 0 || index == points.count - 1
                    let x = inset + points[index].x * (1.0 - inset * 2.0)
                    let y = isEnd ? points[index].y : points[index].y + lift
                    return SIMD2<Float>(Float(x), Float(y))
                }
                return (point(0), point(1), point(2), point(3), point(4), point(5))
            }

            let progress = bezierPoint(0.42, 0.0, 0.58, 1.0, max(0.0, min(1.0, self.elapsed / self.duration)))
            return LiquidGlassCrestShape(fromPoints: crestPoints(self.fromPoints), toPoints: crestPoints(self.toPoints), progress: Float(progress), offset: 0.0)
        }

        private func startNextShape() {
            self.toPoints = self.generatePoints()
            let speed = (self.motion.minSpeed + (self.motion.maxSpeed - self.motion.minSpeed) * self.speedLevel) * Constants.speedMultiplier
            self.duration = 1.0 / max(speed, 0.05)
            self.speedLevel = 0.0
        }

        private func generatePoints() -> [CGPoint] {
            let randomness = self.motion.minRandomness + (self.motion.maxRandomness - self.motion.minRandomness) * self.speedLevel
            let count = LiquidGlassShapesConstants.crestPointCount
            let segment = 1.0 / CGFloat(count - 1)
            let rangeStart: CGFloat = 1.0 / (1.0 + randomness / 10.0)

            return (0 ..< count).map { index -> CGPoint in
                if index == 0 {
                    return CGPoint(x: 0.0, y: 0.0)
                } else if index == count - 1 {
                    return CGPoint(x: 1.0, y: 0.0)
                }
                let randomPointOffset = (rangeStart + CGFloat.random(in: 0.0 ..< 1.0) * (1.0 - rangeStart)) / 2.0
                let x = segment * CGFloat(index) + segment - segment * randomPointOffset
                let y = (randomness * CGFloat.random(in: 0.0 ..< 1.0) - randomness * 0.5) * randomPointOffset
                return CGPoint(x: x, y: y)
            }
        }
    }

    var isFlat: Bool {
        get {
            return self.shapesLayer.isFlat
        } set {
            self.shapesLayer.isFlat = newValue
        }
    }

    var isAnimating: Bool {
        get {
            return self.shapesLayer.isAnimating
        } set {
            self.shapesLayer.isAnimating = newValue
        }
    }

    var isDarkAppearance: Bool {
        get {
            return self.shapesLayer.isDarkAppearance
        } set {
            self.shapesLayer.isDarkAppearance = newValue
        }
    }

    private let shapesLayer: LiquidGlassShapesLayer
    private let shapeMask = SimpleLayer()
    private let barMask = SimpleShapeLayer()
    private let overflowMask = SimpleGradientLayer()
    private let waves: [Wave]
    private var colors: (NSColor, NSColor) = (.white, .white)
    private var audioLevel: CGFloat = 0.0
    private var presentationAudioLevel: CGFloat = 0.0
    private var barHeight: CGFloat = 0.0

    override init() {
        self.shapesLayer = LiquidGlassShapesLayer(colors: (.white, .white))
        self.waves = CallStatusBarWavesView.waveMotions.map(Wave.init(motion:))

        super.init()

        self.isEventLess = true
        self.backgroundColor = .clear
        self.shapesLayer.glassMapScale = CGSize(width: 1.0, height: System.backingScale)
        self.shapesLayer.source = self
        self.shapesLayer.releasesSurfacesWhenHidden = true
        self.layer?.addSublayer(self.shapesLayer)

        self.barMask.fillColor = NSColor.white.cgColor
        self.overflowMask.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor, NSColor.clear.cgColor]
        self.overflowMask.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.overflowMask.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.shapeMask.addSublayer(self.barMask)
        self.shapeMask.addSublayer(self.overflowMask)
        self.layer?.mask = self.shapeMask
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(barHeight: CGFloat) {
        self.barHeight = barHeight
        self.shapesLayer.frame = CGRect(origin: CGPoint(), size: self.bounds.size)
        self.shapesLayer.gradientLength = self.bounds.width * 2.0
        self.shapesLayer.updateLayout()
        self.updateShapeMask()
    }

    func updateAudioLevel(_ level: CGFloat) {
        let normalizedLevel = min(1.0, max(level / Constants.maxLevel, 0.0))
        for wave in self.waves {
            wave.updateSpeedLevel(normalizedLevel)
        }
        self.audioLevel = normalizedLevel
    }

    func updateColors(_ colors: (NSColor, NSColor), animated: Bool) {
        self.colors = colors
        self.shapesLayer.updateColors(self.windowColors(colors), animated: animated)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.shapesLayer.isInWindow = self.window != nil
        self.shapesLayer.updateColors(self.windowColors(self.colors), animated: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        self.shapesLayer.updateColors(self.windowColors(self.colors), animated: false)
    }

    private func windowColors(_ colors: (NSColor, NSColor)) -> (NSColor, NSColor) {
        guard let colorSpace = self.window?.colorSpace ?? self.window?.screen?.colorSpace, colorSpace.colorSpaceModel == .rgb else {
            return colors
        }
        func convert(_ color: NSColor) -> NSColor {
            guard let converted = color.usingColorSpace(colorSpace) else {
                return color
            }
            var red: CGFloat = 0.0
            var green: CGFloat = 0.0
            var blue: CGFloat = 0.0
            var alpha: CGFloat = 0.0
            converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
        return (convert(colors.0), convert(colors.1))
    }

    private func updateShapeMask() {
        let size = self.bounds.size
        self.shapeMask.frame = CGRect(origin: CGPoint(), size: size)
        guard size.width > 0.0, self.barHeight > 0.0 else {
            self.barMask.path = nil
            self.overflowMask.frame = CGRect()
            return
        }
        let cornerRadius = min(self.barHeight, size.width) / 2.0
        self.barMask.frame = CGRect(origin: CGPoint(), size: size)
        self.barMask.path = CGPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: size.width, height: self.barHeight), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        self.overflowMask.frame = CGRect(x: 0.0, y: self.barHeight, width: size.width, height: max(0.0, size.height - self.barHeight))
        let edge = Double(CallStatusBarWavesView.edgeInset(barHeight: self.barHeight, width: size.width))
        self.overflowMask.locations = [0.0, edge * 0.5, edge, 1.0 - edge, 1.0 - edge * 0.5, 1.0].map { NSNumber(value: $0) }
    }

    private static func edgeInset(barHeight: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0.0 else {
            return 0.0
        }
        let cornerRadius = min(barHeight, width) / 2.0
        return min(cornerRadius / width, 0.25)
    }
}

extension CallStatusBarWavesView: LiquidGlassShapesSource {
    func liquidGlassShapesAdvance(by deltaTime: CGFloat) {
        let smoothing = pow(Constants.levelSmoothing, deltaTime * 60.0)
        self.presentationAudioLevel = self.presentationAudioLevel * smoothing + self.audioLevel * (1.0 - smoothing)
        for wave in self.waves {
            wave.advance(by: deltaTime)
        }
    }

    func liquidGlassShapes(size: CGSize, isFlat: Bool) -> LiquidGlassShapeSet? {
        if self.barHeight <= 0.0 {
            return nil
        }
        var parameters = LiquidGlassCrestParameters(
            shapes: (.flat, .flat, .flat),
            width: Float(size.width),
            restY: Float(self.barHeight),
            amplitude: Float(Constants.amplitude),
            smoothness: Float(Constants.smoothness)
        )
        if !isFlat {
            let inset = CallStatusBarWavesView.edgeInset(barHeight: self.barHeight, width: size.width)
            parameters.shapes = (
                self.waves[0].crestShape(level: self.presentationAudioLevel, inset: inset),
                self.waves[1].crestShape(level: self.presentationAudioLevel, inset: inset),
                self.waves[2].crestShape(level: self.presentationAudioLevel, inset: inset)
            )
        }
        return .crest(parameters)
    }

    func liquidGlassAppearance(mode: LiquidGlassRenderMode, isDarkAppearance: Bool) -> LiquidGlassShapesAppearance {
        return CallStatusBarWavesAppearance.appearance
    }
}
