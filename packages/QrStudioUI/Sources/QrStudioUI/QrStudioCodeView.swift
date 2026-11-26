import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit

func qrStudioRenderFlippedImage(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
    let width = Int(ceil(size.width * scale))
    let height = Int(ceil(size.height * scale))
    guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
        return nil
    }
    context.translateBy(x: 0.0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    draw(context)
    return context.makeImage()
}

func qrStudioDrawFlipped(_ image: CGImage, in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1.0, y: -1.0)
    context.draw(image, in: CGRect(origin: CGPoint(), size: rect.size))
    context.restoreGState()
}

private final class QrStudioCodeShapesLayer: SimpleLayer {
    let bodyLayer = SimpleShapeLayer()
    let framesLayer = SimpleShapeLayer()
    let ballsLayer = SimpleShapeLayer()

    var shapeLayers: [CAShapeLayer] {
        return [self.bodyLayer, self.framesLayer, self.ballsLayer]
    }

    override init() {
        super.init()

        self.framesLayer.fillRule = .evenOdd
        self.addSublayer(self.bodyLayer)
        self.addSublayer(self.framesLayer)
        self.addSublayer(self.ballsLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(paths: QrStudioCodePaths?, color: CGColor, size: CGSize) {
        let frame = CGRect(origin: CGPoint(), size: size)
        self.frame = frame
        for shapeLayer in self.shapeLayers {
            shapeLayer.frame = frame
            shapeLayer.fillColor = color
        }
        self.bodyLayer.path = paths?.body
        self.framesLayer.path = paths?.frames
        self.ballsLayer.path = paths?.balls
    }
}

final class QrStudioAshLayer: SimpleLayer {
    static let margin: CGFloat = 150.0
    private static let tail: Double = 0.9
    private static let steps: Int = 10

    private var startedAt: Double?
    private var isActive = false

    private static func dotImage(color: QrStudioColor) -> CGImage? {
        let side: CGFloat = 12.0
        return qrStudioRenderFlippedImage(size: CGSize(width: side, height: side), scale: System.backingScale, { context in
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: 0.0, y: 0.0, width: side, height: side))
        })
    }

    private static let sparkImage: CGImage? = {
        let side: CGFloat = 34.0
        return qrStudioRenderFlippedImage(size: CGSize(width: side, height: side), scale: System.backingScale, { context in
            let center = CGPoint(x: side * 0.5, y: side * 0.5)
            let core = side * 0.5 / 3.4
            if let space = CGColorSpace(name: CGColorSpace.sRGB), let gradient = CGGradient(colorsSpace: space, colors: [NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.3).cgColor, NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0).cgColor] as CFArray, locations: [0.0, 1.0]) {
                context.drawRadialGradient(gradient, startCenter: center, startRadius: core, endCenter: center, endRadius: side * 0.5, options: [])
            }
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2.0, height: core * 2.0))
        })
    }()

    func start(matrix: QrCodeMatrix, side: CGFloat, ink: QrStudioColor, at time: Double) {
        let size = matrix.size
        guard size > 0, side > 0.0 else {
            return
        }
        let unit = side / CGFloat(max(1, size))
        let margin = QrStudioAshLayer.margin
        let tones: [QrStudioColor] = [QrStudioColor(1.0, 1.0, 1.0), ink.pastel, ink]
        let dotImages = tones.map { QrStudioAshLayer.dotImage(color: $0) }
        let sparkImage = QrStudioAshLayer.sparkImage
        let base = self.convertTime(CACurrentMediaTime(), from: nil) - (QrStudioClock.now - time)
        let steps = QrStudioAshLayer.steps

        var darkCount = 0
        for y in 0 ..< size {
            for x in 0 ..< size where matrix[x, y] {
                darkCount += 1
            }
        }
        let isDense = darkCount > 600

        for y in 0 ..< size {
            let centerY = (CGFloat(y) + 0.5) * unit
            let born = QrStudioSweep.time(at: centerY - QrStudioSweep.depth * 0.5, side: side)
            for x in 0 ..< size where matrix[x, y] {
                let key = Int32(truncatingIfNeeded: y &* 977 &+ x)
                let count = isDense ? 1 : 1 + Int(QrStudioSweep.hash(key, 1) * 1.99)
                for j in 0 ..< count {
                    let seed = Double(y * 977 + x) * 0.37 + Double(j) * 0.618
                    func particleHash(_ salt: Double) -> Double {
                        let value = sin(seed * 12.9898 + salt * 78.233) * 43758.5453
                        return value - floor(value)
                    }
                    let kind = particleHash(10.0)
                    let spark = kind > 0.86
                    let flake = !spark && kind < 0.12
                    let life = spark ? 0.4 + 0.35 * particleHash(3.0) : 0.42 + 0.4 * particleHash(3.0)
                    let delay = particleHash(4.0) * 0.06
                    let startX = (Double(x) + particleHash(5.0)) * Double(unit) + Double(margin)
                    let startY = (Double(y) + particleHash(6.0)) * Double(unit) + Double(margin)
                    let angle = -Double.pi * 0.5 + (particleHash(7.0) - 0.5) * 3.6
                    let speedHash = particleHash(8.0)
                    let speed = spark ? 480.0 + 520.0 * speedHash : (flake ? 120.0 + 160.0 * speedHash : 220.0 + 420.0 * speedHash)
                    let drag = spark ? 2.0 : 2.7
                    let wobblePhase = 6.283 * particleHash(9.0)
                    let sizeHash = particleHash(2.0)
                    let radius = spark ? 0.9 + 0.7 * sizeHash : (flake ? 2.2 + 2.0 * sizeHash : 0.6 + 1.3 * sizeHash)
                    let toneHash = particleHash(11.0)
                    let tone = (spark || toneHash < 0.5) ? 0 : (toneHash < 0.72 ? 1 : 2)
                    let extent = CGFloat(radius * (spark ? 3.4 : 1.0) * 2.0)

                    var positions: [NSValue] = []
                    var opacities: [NSNumber] = []
                    var scales: [NSNumber] = []
                    positions.reserveCapacity(steps + 1)
                    opacities.reserveCapacity(steps + 1)
                    scales.reserveCapacity(steps + 1)
                    for i in 0 ... steps {
                        let k = Double(i) / Double(steps)
                        let tau = k * life
                        let travel = speed * (1.0 - exp(-drag * tau)) / drag
                        let px = startX + cos(angle) * travel + 3.0 * sin(7.0 * tau + wobblePhase) * tau
                        let py = startY + sin(angle) * travel + 34.0 * tau * tau
                        positions.append(NSValue(point: NSPoint(x: px, y: py)))
                        opacities.append(NSNumber(value: pow(1.0 - k, 1.2)))
                        scales.append(NSNumber(value: 1.0 - 0.4 * k))
                    }

                    let particle = SimpleLayer()
                    particle.contents = spark ? sparkImage : dotImages[tone]
                    particle.contentsGravity = .resize
                    particle.bounds = CGRect(x: 0.0, y: 0.0, width: extent, height: extent)
                    particle.position = CGPoint(x: startX, y: startY)
                    particle.opacity = 0.0

                    let position = CAKeyframeAnimation(keyPath: "position")
                    position.values = positions
                    position.duration = life
                    let opacity = CAKeyframeAnimation(keyPath: "opacity")
                    opacity.values = opacities
                    opacity.duration = life
                    let scale = CAKeyframeAnimation(keyPath: "transform.scale")
                    scale.values = scales
                    scale.duration = life

                    let group = CAAnimationGroup()
                    group.animations = [position, opacity, scale]
                    group.duration = life
                    group.beginTime = base + born + delay
                    group.isRemovedOnCompletion = true
                    particle.add(group, forKey: "ash")
                    self.addSublayer(particle)
                }
            }
        }
        self.startedAt = time
        self.isActive = true
    }

    func tick(time: Double) {
        guard self.isActive, let startedAt = self.startedAt else {
            return
        }
        if time - startedAt > QrStudioSweep.transition + QrStudioAshLayer.tail {
            self.isActive = false
            self.sublayers = nil
        }
    }

    var isRunning: Bool {
        return self.isActive
    }
}

private final class QrStudioWeakSticker {
    weak var value: QrStudioExportSticker?

    init(_ value: QrStudioExportSticker) {
        self.value = value
    }
}

private var qrStudioPlaneFrames: [Int: QrStudioWeakSticker] = [:]

final class QrStudioPlaneLayer: SimpleLayer {
    private static let animationKey = "frames"

    private var pixelSide = 0
    private(set) var sticker: QrStudioExportSticker?
    private var disposable: Disposable?

    override init() {
        super.init()

        self.contentsGravity = .resizeAspect
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
    }

    func update(pointSize: CGSize) {
        let pixelSide = Int(floor(min(pointSize.width, pointSize.height) * System.backingScale))
        guard pixelSide != self.pixelSide, pixelSide > 0 else {
            return
        }
        self.pixelSide = pixelSide
        if let sticker = qrStudioPlaneFrames[pixelSide]?.value {
            self.apply(sticker)
            return
        }
        self.disposable?.dispose()
        self.disposable = (Signal<QrStudioExportSticker?, NoError> { subscriber in
            subscriber.putNext(qrStudioDecodeExportPlane(pixelSide: pixelSide))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())
        |> deliverOnMainQueue).start(next: { [weak self] sticker in
            guard let self, let sticker, self.pixelSide == pixelSide else {
                return
            }
            qrStudioPlaneFrames[pixelSide] = QrStudioWeakSticker(sticker)
            self.apply(sticker)
        })
    }

    private func apply(_ sticker: QrStudioExportSticker) {
        self.sticker = sticker
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.contents = sticker.frames.first
        CATransaction.commit()
        self.removeAnimation(forKey: QrStudioPlaneLayer.animationKey)
        guard sticker.isAnimated else {
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = sticker.frames
        animation.duration = sticker.period
        animation.calculationMode = .discrete
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = self.convertTime(CACurrentMediaTime(), from: nil)
        self.add(animation, forKey: QrStudioPlaneLayer.animationKey)
    }
}

private final class QrStudioCodeSweep {
    let startedAt: Double
    let side: CGFloat

    let newMask = SimpleGradientLayer()
    let fillNewMask = SimpleGradientLayer()
    let hotLayer = QrStudioCodeShapesLayer()
    let hotMask = SimpleGradientLayer()
    let oldLayer = QrStudioCodeShapesLayer()
    let oldMask = SimpleShapeLayer()
    let emberContainer = SimpleLayer()
    let emberGradient = SimpleGradientLayer()
    let emberShapes = QrStudioCodeShapesLayer()
    let emberMask = SimpleShapeLayer()
    let glowLayer = SimpleShapeLayer()
    let coreLayer = SimpleShapeLayer()
    let ashLayer = QrStudioAshLayer()

    var layers: [CALayer] {
        return [self.hotLayer, self.oldLayer, self.emberContainer, self.glowLayer, self.coreLayer, self.ashLayer]
    }

    init(startedAt: Double, side: CGFloat, oldPaths: QrStudioCodePaths, oldMatrix: QrCodeMatrix, newPaths: QrStudioCodePaths, ink: QrStudioColor) {
        self.startedAt = startedAt
        self.side = side

        let size = CGSize(width: side, height: side)
        let frame = CGRect(origin: CGPoint(), size: size)
        let pastel = ink.pastel.cgColor

        for mask in [self.newMask, self.fillNewMask] {
            mask.frame = frame
            mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor]
        }

        self.hotLayer.update(paths: newPaths, color: pastel, size: size)
        self.hotMask.frame = frame
        self.hotMask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        self.hotMask.locations = [0.0, 0.35, 1.0]
        self.hotLayer.mask = self.hotMask

        self.oldLayer.update(paths: oldPaths, color: ink.cgColor, size: size)
        self.oldMask.frame = frame
        self.oldLayer.mask = self.oldMask

        self.emberContainer.frame = frame
        self.emberGradient.frame = frame
        self.emberGradient.colors = [NSColor.clear.cgColor, pastel, NSColor.white.cgColor]
        self.emberShapes.update(paths: oldPaths, color: NSColor.black.cgColor, size: size)
        self.emberGradient.mask = self.emberShapes
        self.emberContainer.addSublayer(self.emberGradient)
        self.emberMask.frame = frame
        self.emberContainer.mask = self.emberMask

        self.glowLayer.frame = frame
        self.glowLayer.fillColor = nil
        self.glowLayer.strokeColor = pastel
        self.glowLayer.lineWidth = 9.0
        self.glowLayer.opacity = 0.35
        self.glowLayer.shadowColor = pastel
        self.glowLayer.shadowRadius = 7.0
        self.glowLayer.shadowOpacity = 1.0
        self.glowLayer.shadowOffset = CGSize()

        self.coreLayer.frame = frame
        self.coreLayer.fillColor = nil
        self.coreLayer.strokeColor = NSColor.white.cgColor
        self.coreLayer.lineWidth = 1.6
        self.coreLayer.opacity = 0.9

        let margin = QrStudioAshLayer.margin
        self.ashLayer.frame = frame.insetBy(dx: -margin, dy: -margin)
        self.ashLayer.start(matrix: oldMatrix, side: side, ink: ink, at: startedAt)
    }

    func update(time: Double) {
        let since = time - self.startedAt
        let side = self.side
        let front = QrStudioSweep.front(at: since, side: side)
        let isFrontVisible = since < QrStudioSweep.sweepTime + 0.05

        let steps = 40
        var edgePoints: [CGPoint] = []
        edgePoints.reserveCapacity(steps + 1)
        for i in 0 ... steps {
            let x = side * CGFloat(i) / CGFloat(steps)
            edgePoints.append(CGPoint(x: x, y: QrStudioSweep.edge(x: x, front: front, since: since)))
        }

        let visible = CGMutablePath()
        visible.move(to: CGPoint(x: -2.0, y: -2.0))
        visible.addLine(to: CGPoint(x: side + 2.0, y: -2.0))
        for point in edgePoints.reversed() {
            visible.addLine(to: point)
        }
        visible.closeSubpath()
        self.oldMask.path = visible

        let line = CGMutablePath()
        let ember = CGMutablePath()
        for (i, point) in edgePoints.enumerated() {
            if i == 0 {
                line.move(to: point)
                ember.move(to: point)
            } else {
                line.addLine(to: point)
                ember.addLine(to: point)
            }
        }
        for point in edgePoints.reversed() {
            ember.addLine(to: CGPoint(x: point.x, y: point.y - 9.0))
        }
        ember.closeSubpath()
        self.emberMask.path = ember
        self.emberGradient.startPoint = CGPoint(x: 0.5, y: (front - 9.0) / side)
        self.emberGradient.endPoint = CGPoint(x: 0.5, y: (front + QrStudioSweep.depth) / side)

        self.glowLayer.path = line
        self.coreLayer.path = line
        self.glowLayer.isHidden = !isFrontVisible
        self.coreLayer.isHidden = !isFrontVisible
        self.emberContainer.isHidden = !isFrontVisible

        let top = front + QrStudioSweep.lag
        let bottom = top + QrStudioSweep.fade
        for mask in [self.newMask, self.fillNewMask] {
            mask.startPoint = CGPoint(x: 0.5, y: top / side)
            mask.endPoint = CGPoint(x: 0.5, y: bottom / side)
        }
        self.hotMask.startPoint = CGPoint(x: 0.5, y: top / side)
        self.hotMask.endPoint = CGPoint(x: 0.5, y: (bottom + 22.0) / side)

        self.ashLayer.tick(time: time)
    }

    var isFinished: Bool {
        return !self.ashLayer.isRunning
    }

    func isCodeSettled(at time: Double) -> Bool {
        return time - self.startedAt >= QrStudioSweep.transition
    }
}

final class QrStudioCodeView: View {
    private let codeLayer = QrStudioCodeShapesLayer()
    private let logoBackgroundLayer = SimpleLayer()
    private let planeLayer = QrStudioPlaneLayer()

    let fillHost = SimpleLayer()
    private let fillMask = SimpleLayer()
    private let fillShapes = QrStudioCodeShapesLayer()
    private let fillLogo = SimpleLayer()

    private var matrix: QrCodeMatrix?
    private var pathsSize: CGSize?
    private(set) var paths: QrStudioCodePaths?
    private var ink: QrStudioColor?

    private(set) var logoFrame = CGRect()
    private(set) var planeFrame = CGRect()

    private var sweep: QrStudioCodeSweep?
    private var sweepLink: SharedDisplayLinkDriver.Link?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.isEventLess = true
        self.layer?.masksToBounds = false
        self.layer?.isOpaque = false

        self.fillShapes.update(paths: nil, color: NSColor.black.cgColor, size: CGSize())
        self.fillLogo.backgroundColor = NSColor.black.cgColor
        self.fillMask.addSublayer(self.fillShapes)
        self.fillMask.addSublayer(self.fillLogo)
        self.fillHost.mask = self.fillMask
        self.fillHost.isHidden = true

        self.layer?.addSublayer(self.codeLayer)
        self.layer?.addSublayer(self.logoBackgroundLayer)
        self.layer?.addSublayer(self.fillHost)
        self.layer?.addSublayer(self.planeLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.sweepLink?.invalidate()
    }

    var planeImage: CGImage? {
        return self.planeLayer.sticker?.frames.first
    }

    private func endSweep() {
        guard let sweep = self.sweep else {
            return
        }
        self.sweep = nil
        self.sweepLink?.invalidate()
        self.sweepLink = nil
        self.codeLayer.mask = nil
        self.fillShapes.mask = nil
        for layer in sweep.layers {
            layer.removeFromSuperlayer()
        }
    }

    private func settleSweepCode() {
        guard let sweep = self.sweep else {
            return
        }
        self.codeLayer.mask = nil
        self.fillShapes.mask = nil
        sweep.hotLayer.removeFromSuperlayer()
        sweep.oldLayer.removeFromSuperlayer()
        sweep.emberContainer.removeFromSuperlayer()
        sweep.glowLayer.removeFromSuperlayer()
        sweep.coreLayer.removeFromSuperlayer()
    }

    private func startSweep(oldMatrix: QrCodeMatrix, oldPaths: QrStudioCodePaths, newPaths: QrStudioCodePaths, ink: QrStudioColor, side: CGFloat) {
        self.endSweep()

        let sweep = QrStudioCodeSweep(startedAt: QrStudioClock.now, side: side, oldPaths: oldPaths, oldMatrix: oldMatrix, newPaths: newPaths, ink: ink)
        self.sweep = sweep
        self.codeLayer.mask = sweep.newMask
        self.fillShapes.mask = sweep.fillNewMask
        self.layer?.insertSublayer(sweep.hotLayer, above: self.codeLayer)
        self.layer?.insertSublayer(sweep.oldLayer, above: sweep.hotLayer)
        self.layer?.insertSublayer(sweep.emberContainer, above: sweep.oldLayer)
        self.layer?.insertSublayer(sweep.glowLayer, above: sweep.emberContainer)
        self.layer?.insertSublayer(sweep.coreLayer, above: sweep.glowLayer)
        self.layer?.addSublayer(sweep.ashLayer)
        sweep.update(time: sweep.startedAt)

        self.animateLogoDip()

        self.sweepLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60), { [weak self] _ in
            guard let self, let sweep = self.sweep else {
                return
            }
            let time = QrStudioClock.now
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if sweep.isCodeSettled(at: time) {
                if self.codeLayer.mask != nil {
                    self.settleSweepCode()
                }
                sweep.ashLayer.tick(time: time)
            } else {
                sweep.update(time: time)
            }
            if sweep.isFinished {
                self.endSweep()
            }
            CATransaction.commit()
        })
    }

    private func animateLogoDip() {
        let dip = CABasicAnimation(keyPath: "transform.scale")
        dip.fromValue = 1.0
        dip.toValue = 0.86
        dip.duration = 0.14
        dip.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.86
        spring.toValue = 1.0
        spring.mass = 1.0
        spring.stiffness = 195.0
        spring.damping = 15.36
        spring.beginTime = 0.14
        spring.duration = 0.6

        let group = CAAnimationGroup()
        group.animations = [dip, spring]
        group.duration = 0.74
        self.logoBackgroundLayer.add(group, forKey: "dip")
        self.fillLogo.add(group, forKey: "dip")
        self.planeLayer.add(group, forKey: "dip")
    }

    func update(matrix: QrCodeMatrix?, ink: QrStudioColor, transition: ContainedViewLayoutTransition, animatesInk: Bool = true) {
        let size = self.bounds.size
        let side = min(size.width, size.height)

        let previousMatrix = self.matrix
        let previousPaths = self.paths
        if let matrix, self.matrix != matrix || self.pathsSize != size {
            self.matrix = matrix
            self.pathsSize = size
            self.paths = QrStudioCodePaths(matrix: matrix, side: side)
        }

        let previousInk = self.ink
        self.ink = ink

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let inkColor = ink.cgColor
        if let previousInk, previousInk != ink, animatesInk, transition.isAnimated {
            var values: [CGColor] = []
            for i in 0 ..< 16 {
                values.append(QrStudioColor.mixLab(previousInk, ink, CGFloat(i) / 15.0).cgColor)
            }
            var targets: [(CALayer, String)] = self.codeLayer.shapeLayers.map { ($0, "fillColor") }
            targets.append((self.logoBackgroundLayer, "backgroundColor"))
            for (targetLayer, keyPath) in targets {
                let animation = CAKeyframeAnimation(keyPath: keyPath)
                animation.values = values
                animation.duration = 0.5
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                targetLayer.add(animation, forKey: "ink")
            }
        }
        self.codeLayer.update(paths: self.paths, color: inkColor, size: size)
        self.fillShapes.update(paths: self.paths, color: NSColor.black.cgColor, size: size)
        self.fillHost.frame = CGRect(origin: CGPoint(), size: size)
        self.fillMask.frame = CGRect(origin: CGPoint(), size: size)

        let hasCode = self.paths != nil
        let logoDiameter = self.paths?.logoDiameter ?? 0.0
        let logoFrame = CGRect(x: (size.width - logoDiameter) * 0.5, y: (size.height - logoDiameter) * 0.5, width: logoDiameter, height: logoDiameter)
        self.logoFrame = logoFrame
        for logoLayer in [self.logoBackgroundLayer, self.fillLogo] {
            logoLayer.bounds = CGRect(origin: CGPoint(), size: logoFrame.size)
            logoLayer.position = CGPoint(x: logoFrame.midX, y: logoFrame.midY)
            logoLayer.cornerRadius = logoDiameter * 0.5
            logoLayer.isHidden = !hasCode
        }
        self.logoBackgroundLayer.backgroundColor = inkColor

        if let previousMatrix, let previousPaths, let matrix = self.matrix, let paths = self.paths, previousMatrix != matrix, transition.isAnimated, side > 0.0 {
            self.startSweep(oldMatrix: previousMatrix, oldPaths: previousPaths, newPaths: paths, ink: ink, side: side)
        }

        let planeSide = logoDiameter + 8.0
        let planeCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.5 - 1.0)
        self.planeFrame = CGRect(x: planeCenter.x - planeSide * 0.5, y: planeCenter.y - planeSide * 0.5, width: planeSide, height: planeSide)
        self.planeLayer.bounds = CGRect(x: 0.0, y: 0.0, width: planeSide, height: planeSide)
        self.planeLayer.position = planeCenter
        self.planeLayer.isHidden = !hasCode

        CATransaction.commit()

        self.planeLayer.update(pointSize: CGSize(width: planeSide, height: planeSide))
    }
}
