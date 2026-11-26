import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
import UniqueGiftBackground

private func qrStudioFraction(_ value: Double) -> Double {
    return value - floor(value)
}

private func qrStudioGiftGradientImage(size: CGSize, inner: QrStudioColor, outer: QrStudioColor) -> CGImage? {
    let scale: CGFloat = 0.5
    let width = max(1, Int(ceil(size.width * scale)))
    let height = max(1, Int(ceil(size.height * scale)))
    guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
        return nil
    }
    context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
    let bounds = CGRect(origin: CGPoint(), size: size)
    context.setFillColor(outer.cgColor)
    context.fill(bounds)
    if let gradient = CGGradient(colorsSpace: space, colors: [inner.cgColor, outer.cgColor] as CFArray, locations: [0.0, 1.0]) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: 500.0, options: [.drawsAfterEndLocation])
    }
    return context.makeImage()
}

private final class QrStudioGiftSymbolNode {
    let layer = SimpleLayer()
    var shine: SimpleLayer?
    var isUsed = false
}

final class QrStudioGiftPatternView: View, QrStudioBackgroundContent {
    private struct Spot {
        var point: CGPoint
        var side: CGFloat
        var angle: Double
        var hash: Double
        var key: Int64
    }

    private static let velocity = CGVector(dx: -2.5, dy: -4.0)
    private static let symbols = QrStudioLattice(dx: 44.0, dy: 38.0, velocity: QrStudioGiftPatternView.velocity, lag: 0.03 ... 0.16, orbit: 2.0 ... 7.0)
    private static let stickers = QrStudioLattice(dx: 170.0, dy: 150.0, velocity: QrStudioGiftPatternView.velocity, lag: 0.06 ... 0.2, orbit: 5.0 ... 12.0)
    private static let modelSide: CGFloat = 94.0
    private static let symbolSide: CGFloat = 21.0

    private let context: any AccountContextProtocol
    private let gift: QrStudioGift
    private let gradientLayer = SimpleLayer()
    private let symbolsLayer = SimpleLayer()
    private let shinesLayer = SimpleLayer()
    private let modelsLayer = SimpleLayer()
    private var modelAnimation: QrStudioPhasedAnimation?
    private var modelLayers: [Int64: SimpleLayer] = [:]
    private var symbolNodes: [Int64: QrStudioGiftSymbolNode] = [:]
    private var reusableSymbolNodes: [QrStudioGiftSymbolNode] = []
    private var symbolImage: CGImage?
    private var shineImage: CGImage?
    private let symbolDisposable = MetaDisposable()

    private var size = CGSize()
    private var revealCenter = CGPoint()
    private var bornAt: Double = -10.0
    private var shownAt: Double?
    private var isVisible = true

    let wantsFullFrameRate: Bool = true

    static func canonicalExportItems(size: CGSize) -> [QrStudioExportPatternItem] {
        let squeeze = QrStudioEdgeSqueeze(size: size)
        let drift = QrStudioDrift()
        let tilt = SIMD2<Double>(0.0, 0.0)
        let spots = QrStudioGiftPatternView.stickers.cells(in: size, at: 0.0, offset: CGSize(), margin: squeeze.margin + 60.0, drift: drift, tilt: tilt).map(QrStudioGiftPatternView.spot)
        var items: [QrStudioExportPatternItem] = []
        for spot in spots {
            items.append(QrStudioExportPatternItem(content: .model, point: CGPoint(x: spot.point.x, y: spot.point.y + CGFloat(3.0 * sin(spot.hash * 2.0 * .pi))), side: spot.side, degrees: spot.angle, hash: spot.hash))
        }
        for cell in QrStudioGiftPatternView.symbols.cells(in: size, at: 0.0, offset: CGSize(), margin: squeeze.margin, drift: drift, tilt: tilt) {
            let h = cell.hash
            guard qrStudioFraction(h * 23.17) > 0.24 else {
                continue
            }
            let raw = CGPoint(x: cell.point.x + CGFloat(qrStudioFraction(h * 3.1) - 0.5) * 38.0, y: cell.point.y + CGFloat(qrStudioFraction(h * 6.7) - 0.5) * 32.0)
            if spots.contains(where: { hypot($0.point.x - raw.x, $0.point.y - raw.y) < $0.side * 0.66 }) {
                continue
            }
            let h2 = qrStudioFraction(h * 7.31)
            let h5 = qrStudioFraction(h * 41.9)
            items.append(QrStudioExportPatternItem(content: .symbol, point: raw, side: CGFloat(21.0 * (0.55 + 0.75 * h5 * h5)), degrees: (h2 - 0.5) * 70.0, hash: h))
        }
        return items
    }

    init(context: any AccountContextProtocol, gift: QrStudioGift) {
        self.context = context
        self.gift = gift

        super.init(frame: CGRect())

        self.backgroundColor = gift.outer.nsColor

        self.gradientLayer.contentsGravity = .resize
        self.layer?.addSublayer(self.gradientLayer)
        self.layer?.addSublayer(self.symbolsLayer)
        self.layer?.addSublayer(self.shinesLayer)
        self.layer?.addSublayer(self.modelsLayer)

        let animation = QrStudioPhasedAnimation(context: context, file: gift.model, pointSize: CGSize(width: QrStudioGiftPatternView.modelSide, height: QrStudioGiftPatternView.modelSide), placeholderColor: gift.patternColor.nsColor.withAlphaComponent(0.55))
        if animation.hasPlaceholder || animation.hasFrames {
            self.shownAt = QrStudioClock.now
        } else {
            animation.onFirstFrame = { [weak self] in
                self?.shownAt = QrStudioClock.now
            }
        }
        self.modelAnimation = animation

        let patternFile = gift.pattern
        let symbolSize = CGSize(width: 48.0, height: 48.0)
        if let data = patternFile.immediateThumbnailData {
            let imageSize: CGSize
            if let dimensions = patternFile.dimensions {
                imageSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
            } else {
                imageSize = CGSize(width: 512.0, height: 512.0)
            }
            if let placeholder = generateStickerPlaceholderImage(data: data, size: symbolSize, scale: 2.0, imageSize: imageSize, backgroundColor: nil, foregroundColor: .white) {
                self.applySymbolTemplate(placeholder, animated: false)
            }
        }

        let pattern = UniqueGiftBackgroundContent.Pattern.file(patternFile)
        if let glyph = UniqueGiftPatternGlyphs.shared.cachedGlyph(fileId: pattern.fileId) {
            self.applySymbolTemplate(glyph.template, animated: false)
        } else {
            self.symbolDisposable.set((UniqueGiftPatternGlyphs.shared.glyph(context: context, pattern: pattern)
            |> deliverOnMainQueue).start(next: { [weak self] glyph in
                self?.applySymbolTemplate(glyph.template, animated: true)
            }))
        }
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.symbolDisposable.dispose()
    }

    private func applySymbolTemplate(_ template: CGImage, animated: Bool) {
        self.symbolImage = qrStudioTinted(template, color: self.gift.patternColor.nsColor)
        self.shineImage = qrStudioTinted(template, color: self.gift.text.nsColor)
        for (_, node) in self.symbolNodes {
            if animated {
                qrStudioCrossfadeContents(node.layer)
            }
            node.layer.contents = self.symbolImage
            node.shine?.contents = self.shineImage
        }
    }

    func update(size: CGSize, revealCenter: CGPoint) {
        self.revealCenter = revealCenter
        guard self.size != size, size.width > 0.0, size.height > 0.0 else {
            return
        }
        self.size = size
        let frame = CGRect(origin: CGPoint(), size: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.gradientLayer.frame = frame
        self.gradientLayer.contents = qrStudioGiftGradientImage(size: size, inner: self.gift.inner, outer: self.gift.outer)
        self.symbolsLayer.frame = frame
        self.shinesLayer.frame = frame
        self.modelsLayer.frame = frame
        CATransaction.commit()
    }

    func beginReveal(at time: Double) {
        self.bornAt = time
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
        self.modelAnimation?.setPaused(!isVisible)
    }

    private static func spot(_ cell: QrStudioLattice.Cell) -> Spot {
        let h = cell.hash
        return Spot(
            point: CGPoint(x: cell.point.x + CGFloat(qrStudioFraction(h * 3.7) - 0.5) * 76.0, y: cell.point.y + CGFloat(qrStudioFraction(h * 5.3) - 0.5) * 64.0),
            side: 62.0 + 32.0 * CGFloat(qrStudioFraction(h * 11.9)),
            angle: (qrStudioFraction(h * 17.3) - 0.5) * 22.0,
            hash: h,
            key: (Int64(cell.r) << 32) | Int64(UInt32(truncatingIfNeeded: cell.c))
        )
    }

    private func symbolNode(for key: Int64) -> QrStudioGiftSymbolNode {
        if let current = self.symbolNodes[key] {
            return current
        }
        let node: QrStudioGiftSymbolNode
        if let reused = self.reusableSymbolNodes.popLast() {
            node = reused
        } else {
            node = QrStudioGiftSymbolNode()
            node.layer.bounds = CGRect(x: 0.0, y: 0.0, width: QrStudioGiftPatternView.symbolSide, height: QrStudioGiftPatternView.symbolSide)
            node.layer.contentsGravity = .resizeAspect
        }
        node.layer.contents = self.symbolImage
        self.symbolsLayer.addSublayer(node.layer)
        if let shine = node.shine {
            shine.contents = self.shineImage
            self.shinesLayer.addSublayer(shine)
        }
        self.symbolNodes[key] = node
        return node
    }

    private func shineLayer(for node: QrStudioGiftSymbolNode) -> SimpleLayer {
        if let current = node.shine {
            return current
        }
        let shine = SimpleLayer()
        shine.bounds = CGRect(x: 0.0, y: 0.0, width: QrStudioGiftPatternView.symbolSide, height: QrStudioGiftPatternView.symbolSide)
        shine.contentsGravity = .resizeAspect
        shine.compositingFilter = "plusL"
        shine.contents = self.shineImage
        self.shinesLayer.addSublayer(shine)
        node.shine = shine
        return shine
    }

    func tick(time: Double, pan: QrStudioPan, drift: QrStudioDrift, tilt: SIMD2<Double>) {
        guard self.isVisible, self.size.width > 0.0, self.size.height > 0.0 else {
            return
        }
        let size = self.size
        let squeeze = QrStudioEdgeSqueeze(size: size)
        let offset = pan.offset(at: time)
        let since = time - self.bornAt
        let shaderTime = time.truncatingRemainder(dividingBy: 3600.0)
        let shaderSince = min(since, 100.0)
        let strength = QrStudioCurve.smooth(QrStudioCurve.clamp01(hypot(tilt.x, tilt.y) / 0.14))
        let bandAt = 0.5 + tilt.x * 1.6 + tilt.y * 1.2

        let spots = QrStudioGiftPatternView.stickers.cells(in: size, at: time, offset: offset, margin: squeeze.margin + 60.0, drift: drift, tilt: tilt).map(QrStudioGiftPatternView.spot)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (_, node) in self.symbolNodes {
            node.isUsed = false
        }

        for cell in QrStudioGiftPatternView.symbols.cells(in: size, at: time, offset: offset, margin: squeeze.margin, drift: drift, tilt: tilt) {
            let h = cell.hash
            guard qrStudioFraction(h * 23.17) > 0.24 else {
                continue
            }
            let raw = CGPoint(x: cell.point.x + CGFloat(qrStudioFraction(h * 3.1) - 0.5) * 38.0, y: cell.point.y + CGFloat(qrStudioFraction(h * 6.7) - 0.5) * 32.0)
            var isCovered = false
            for spot in spots {
                if hypot(spot.point.x - raw.x, spot.point.y - raw.y) < spot.side * 0.66 {
                    isCovered = true
                    break
                }
            }
            if isCovered {
                continue
            }
            let (point, k) = squeeze.apply(raw)
            let alpha = squeeze.alpha(k)
            let enter = QrStudioReveal.entrance(point, center: self.revealCenter, since: since)
            guard alpha > 0.0, enter > 0.01 else {
                continue
            }
            let h2 = qrStudioFraction(h * 7.31)
            let h5 = qrStudioFraction(h * 41.9)
            let baseSide = 21.0 * (0.55 + 0.75 * h5 * h5) * Double(k) * enter

            let twinkle = pow(0.5 + 0.5 * sin(shaderTime * (0.35 + 0.55 * h2) + h * 6.283), 2.0)
            let across = Double(point.x / size.width) * 0.55 + Double(point.y / size.height) * 0.45
            let band = strength * exp(-pow((across - bandAt) / 0.11, 2.0))
            let distance = Double(hypot(point.x - self.revealCenter.x, point.y - self.revealCenter.y))
            let u = (shaderSince - distance / 620.0 - 0.18) / 0.14
            let shine = min(1.0, band + exp(-u * u))
            let side = baseSide * (1.0 + 0.35 * shine + 0.1 * twinkle)
            let scale = CGFloat(side) / QrStudioGiftPatternView.symbolSide
            let transform = CATransform3DRotate(CATransform3DMakeScale(scale, scale, 1.0), CGFloat((h2 - 0.5) * 70.0 * .pi / 180.0), 0.0, 0.0, 1.0)

            let key = (Int64(cell.r) << 32) | Int64(UInt32(truncatingIfNeeded: cell.c))
            let node = self.symbolNode(for: key)
            node.isUsed = true
            node.layer.position = point
            node.layer.opacity = Float(alpha * (0.55 + 0.45 * twinkle) * 0.42)
            node.layer.transform = transform

            let light = shine * alpha * 0.85
            if light > 0.01 {
                let shineLayer = self.shineLayer(for: node)
                shineLayer.isHidden = false
                shineLayer.position = point
                shineLayer.opacity = Float(min(1.0, light))
                shineLayer.transform = transform
            } else if let shineLayer = node.shine, !shineLayer.isHidden {
                shineLayer.isHidden = true
            }
        }

        for (key, node) in self.symbolNodes where !node.isUsed {
            node.layer.removeFromSuperlayer()
            if let shine = node.shine {
                shine.isHidden = true
                shine.removeFromSuperlayer()
            }
            self.reusableSymbolNodes.append(node)
            self.symbolNodes.removeValue(forKey: key)
        }

        var usedKeys = Set<Int64>()
        if let shownAt = self.shownAt, let modelAnimation = self.modelAnimation {
            let appear = QrStudioCurve.clamp01((time - shownAt) / 0.4)
            let modelSide = QrStudioGiftPatternView.modelSide
            for spot in spots {
                let (point, k) = squeeze.apply(CGPoint(x: spot.point.x, y: spot.point.y + CGFloat(3.0 * sin(time * 0.35 + spot.hash * 2.0 * .pi))))
                let alpha = squeeze.alpha(k) * appear
                let enter = QrStudioReveal.entrance(point, center: self.revealCenter, since: since)
                guard alpha > 0.0, enter > 0.01 else {
                    continue
                }
                usedKeys.insert(spot.key)
                let modelLayer: SimpleLayer
                if let current = self.modelLayers[spot.key] {
                    modelLayer = current
                } else {
                    modelLayer = SimpleLayer()
                    modelLayer.bounds = CGRect(x: 0.0, y: 0.0, width: modelSide, height: modelSide)
                    modelLayer.contentsGravity = .resizeAspect
                    self.modelsLayer.addSublayer(modelLayer)
                    self.modelLayers[spot.key] = modelLayer
                    modelAnimation.attach(modelLayer, group: qrStudioPhaseGroup(hash: spot.hash))
                }
                let scale = spot.side * k * CGFloat(enter) / modelSide
                modelLayer.position = point
                modelLayer.opacity = Float(alpha)
                modelLayer.transform = CATransform3DRotate(CATransform3DMakeScale(scale, scale, 1.0), CGFloat(spot.angle * .pi / 180.0), 0.0, 0.0, 1.0)
            }
        } else if let modelAnimation = self.modelAnimation, self.modelLayers.isEmpty {
            let probeKey: Int64 = Int64.min
            let probeLayer = SimpleLayer()
            probeLayer.isHidden = true
            self.modelsLayer.addSublayer(probeLayer)
            self.modelLayers[probeKey] = probeLayer
            modelAnimation.attach(probeLayer, group: 0)
            usedKeys.insert(probeKey)
        } else {
            usedKeys.formUnion(self.modelLayers.keys)
        }
        for (key, modelLayer) in self.modelLayers where !usedKeys.contains(key) {
            self.modelAnimation?.detach(modelLayer)
            modelLayer.removeFromSuperlayer()
            self.modelLayers.removeValue(forKey: key)
        }

        CATransaction.commit()
    }
}
