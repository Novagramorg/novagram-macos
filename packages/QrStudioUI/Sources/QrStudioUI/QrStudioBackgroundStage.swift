import Foundation
import Cocoa
import TGUIKit

let qrStudioRevealDiscImage: CGImage? = {
    let side = 128
    guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
        return nil
    }
    let white = NSColor.white.cgColor
    let clear = NSColor.white.withAlphaComponent(0.0).cgColor
    guard let gradient = CGGradient(colorsSpace: space, colors: [white, white, clear] as CFArray, locations: [0.0, 0.72, 1.0]) else {
        return nil
    }
    let center = CGPoint(x: CGFloat(side) * 0.5, y: CGFloat(side) * 0.5)
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: CGFloat(side) * 0.5, options: [])
    return context.makeImage()
}()

final class QrStudioBackgroundStage: View {
    var makeContent: ((QrStudioBackdrop) -> QrStudioBackgroundContent)?
    var updateContent: ((QrStudioBackgroundContent, QrStudioBackdrop) -> Void)?

    private var stack = QrStudioStageStack<QrStudioBackgroundContent>()
    private var currentBackdrop: QrStudioBackdrop?
    private var size = CGSize()
    private var revealCenter = CGPoint()
    private var activeReveals = 0
    private var isVisible = true

    var isRevealing: Bool {
        return self.activeReveals > 0
    }

    var wantsFullFrameRate: Bool {
        return self.stack.layers.last?.item.wantsFullFrameRate ?? false
    }

    func update(backdrop: QrStudioBackdrop, size: CGSize, revealCenter: CGPoint, animated: Bool) -> QrStudioAppearanceReveal? {
        self.size = size
        self.revealCenter = revealCenter

        for layer in self.stack.layers {
            layer.item.frame = CGRect(origin: CGPoint(), size: size)
            layer.item.update(size: size, revealCenter: revealCenter)
        }

        guard let makeContent = self.makeContent else {
            return nil
        }
        if let currentBackdrop = self.currentBackdrop {
            if currentBackdrop.signature == backdrop.signature {
                return nil
            }
            if currentBackdrop.key == backdrop.key, let top = self.stack.layers.last {
                self.currentBackdrop = backdrop
                self.updateContent?(top.item, backdrop)
                return nil
            }
        }
        let isFirst = self.currentBackdrop == nil
        self.currentBackdrop = backdrop

        let content = makeContent(backdrop)
        content.frame = CGRect(origin: CGPoint(), size: size)
        content.update(size: size, revealCenter: revealCenter)
        content.setVisible(self.isVisible)
        self.addSubview(content)
        let id = self.stack.push(content)

        if isFirst || !animated || size.width <= 0.0 || size.height <= 0.0 {
            self.revealCompleted(id: id)
        } else {
            let reveal = QrStudioAppearanceReveal(center: revealCenter, size: size, startTime: CACurrentMediaTime())
            content.beginReveal(at: QrStudioClock.now)
            self.runReveal(on: content, id: id, reveal: reveal)
            return reveal
        }
        return nil
    }

    func tick(time: Double, pan: QrStudioPan, drift: QrStudioDrift, tilt: SIMD2<Double>) {
        for layer in self.stack.layers {
            layer.item.tick(time: time, pan: pan, drift: drift, tilt: tilt)
        }
    }

    func forEachContent(_ f: (QrStudioBackgroundContent) -> Void) {
        for layer in self.stack.layers {
            f(layer.item)
        }
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
        for layer in self.stack.layers {
            layer.item.setVisible(isVisible)
        }
    }

    private func revealCompleted(id: Int) {
        let removedIds = Set(self.stack.revealCompleted(id: id))
        guard !removedIds.isEmpty else {
            return
        }
        let remaining = Set(self.stack.layers.map { ObjectIdentifier($0.item) })
        for subview in self.subviews {
            if let content = subview as? QrStudioBackgroundContent, !remaining.contains(ObjectIdentifier(content)) {
                content.setVisible(false)
                content.removeFromSuperview()
            }
        }
    }

    private func runReveal(on view: NSView, id: Int, reveal: QrStudioAppearanceReveal) {
        guard let viewLayer = view.layer, let hostLayer = self.layer else {
            self.revealCompleted(id: id)
            return
        }
        if #available(macOS 10.14, *) {
            self.runRadialReveal(viewLayer: viewLayer, hostLayer: hostLayer, id: id, reveal: reveal)
        } else {
            self.runDiscReveal(viewLayer: viewLayer, id: id, reveal: reveal)
        }
    }

    @available(macOS 10.14, *)
    private func runRadialReveal(viewLayer: CALayer, hostLayer: CALayer, id: Int, reveal: QrStudioAppearanceReveal) {
        let center = reveal.center
        let size = reveal.size
        let steps = 30
        let unitCenter = CGPoint(x: center.x / size.width, y: center.y / size.height)
        var ringEndPoints: [NSValue] = []
        var ringLocations: [[NSNumber]] = []
        var ringOpacity: [NSNumber] = []
        for i in 0 ... steps {
            let linear = Double(i) / Double(steps)
            let progress = 1.0 - pow(1.0 - linear, 2.0)
            let radius = max(QrStudioReveal.radius(progress: progress, center: center, size: size), 0.01)
            let ringRadius = max(radius - QrStudioReveal.feather * 0.5, 0.01)
            let outer = ringRadius + 12.0
            ringEndPoints.append(NSValue(point: CGPoint(x: unitCenter.x + outer / size.width, y: unitCenter.y + outer / size.height)))
            ringLocations.append([NSNumber(value: Double(max(0.0, (ringRadius - 12.0) / outer))), NSNumber(value: Double(ringRadius / outer)), 1.0])
            ringOpacity.append(NSNumber(value: sin(.pi * min(1.0, progress * 1.15))))
        }

        let frame = CGRect(origin: CGPoint(), size: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let ring = CAGradientLayer()
        ring.type = .radial
        ring.frame = frame
        ring.colors = [NSColor.white.withAlphaComponent(0.0).cgColor, NSColor.white.withAlphaComponent(0.5).cgColor, NSColor.white.withAlphaComponent(0.0).cgColor]
        ring.startPoint = unitCenter
        ring.endPoint = ringEndPoints[steps].pointValue
        ring.locations = ringLocations[steps]
        ring.opacity = 0.0
        ring.compositingFilter = "plusL"
        hostLayer.insertSublayer(ring, above: viewLayer)

        CATransaction.commit()

        self.activeReveals += 1
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak viewLayer, weak ring] in
            viewLayer?.mask = nil
            ring?.removeFromSuperlayer()
            guard let self = self else {
                return
            }
            self.activeReveals -= 1
            self.revealCompleted(id: id)
        }
        CATransaction.setDisableActions(true)
        viewLayer.mask = reveal.makeMask(frame: frame)
        ring.add(reveal.animation("endPoint", values: ringEndPoints, layer: ring), forKey: "reveal")
        ring.add(reveal.animation("locations", values: ringLocations, layer: ring), forKey: "revealLocations")
        ring.add(reveal.animation("opacity", values: ringOpacity, layer: ring), forKey: "revealOpacity")
        CATransaction.commit()
    }

    private func runDiscReveal(viewLayer: CALayer, id: Int, reveal: QrStudioAppearanceReveal) {
        self.activeReveals += 1
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak viewLayer] in
            viewLayer?.mask = nil
            guard let self = self else {
                return
            }
            self.activeReveals -= 1
            self.revealCompleted(id: id)
        }
        CATransaction.setDisableActions(true)
        viewLayer.mask = reveal.makeMask(frame: CGRect(origin: .zero, size: reveal.size))
        CATransaction.commit()
    }
}
