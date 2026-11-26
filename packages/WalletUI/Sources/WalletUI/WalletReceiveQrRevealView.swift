import Cocoa
import TGUIKit
import QRCodeUtils

struct WalletReceiveQrRevealPlan {
    let batches: [[CGRect]]
    let markers: [CGRect]
}

let walletReceiveQrRevealBatchCount = 48

func walletReceiveQrRevealGeometry(moduleCount: Int, imageSize: CGSize, scale: CGFloat) -> (moduleSide: CGFloat, padding: CGFloat) {
    let (_, _, moduleSide) = qrCodeCutout(size: moduleCount, dimensions: imageSize, scale: scale)
    let padding = round((imageSize.width - moduleSide * CGFloat(moduleCount)) * 0.5 * scale) / scale
    return (moduleSide, padding)
}

func walletReceiveQrRevealPlan(moduleCount: Int, moduleSide: CGFloat, padding: CGFloat, jitter: () -> Double) -> WalletReceiveQrRevealPlan {
    let markerModuleCount = 9
    let markerOrigins = [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: CGFloat(moduleCount - markerModuleCount), y: 0.0),
        CGPoint(x: 0.0, y: CGFloat(moduleCount - markerModuleCount))
    ]
    let markerFrames = markerOrigins.map { origin in
        return CGRect(
            x: padding + origin.x * moduleSide,
            y: padding + origin.y * moduleSide,
            width: CGFloat(markerModuleCount) * moduleSide,
            height: CGFloat(markerModuleCount) * moduleSide
        )
    }

    let batchCount = walletReceiveQrRevealBatchCount
    var batches = Array(repeating: [CGRect](), count: batchCount)
    let center = CGFloat(moduleCount - 1) * 0.5
    for y in 0 ..< moduleCount {
        for x in 0 ..< moduleCount {
            if (y < markerModuleCount && (x < markerModuleCount || x >= moduleCount - markerModuleCount))
                || (y >= moduleCount - markerModuleCount && x < markerModuleCount) {
                continue
            }
            let frame = CGRect(
                x: padding + CGFloat(x) * moduleSide,
                y: padding + CGFloat(y) * moduleSide,
                width: moduleSide,
                height: moduleSide
            )
            let distanceToEdge = min(min(x, y), min(moduleCount - 1 - x, moduleCount - 1 - y))
            let inwardProgress = Double(CGFloat(distanceToEdge) / center)
            let dx = Double(CGFloat(x) - center)
            let dy = Double(CGFloat(y) - center)
            let angle = (atan2(dy, dx) + Double.pi) / (2.0 * Double.pi)
            let radius = hypot(dx, dy) / Double(center)
            let spiralPosition = angle + radius * 1.25
            let spiralPhase = spiralPosition - floor(spiralPosition)
            let phase = inwardProgress * 0.55 + spiralPhase * 0.4 + jitter()
            let batchIndex = min(batchCount - 1, Int(phase * Double(batchCount - 1)))
            batches[batchIndex].append(frame)
        }
    }
    return WalletReceiveQrRevealPlan(batches: batches, markers: markerFrames)
}

func walletReceiveQrRevealBatchDelay(index: Int, delay: Double, duration: Double) -> Double {
    return delay + Double(index) / Double(walletReceiveQrRevealBatchCount - 1) * max(0.0, duration - 0.12)
}

final class WalletReceiveQrRevealView: View {
    func animateIn(image: CGImage, moduleCount: Int, delay: Double, duration: Double) {
        guard let layer = self.layer else {
            return
        }
        let imageSize = self.frame.size
        let scale = CGFloat(image.width) / max(1.0, imageSize.width)
        let (moduleSide, padding) = walletReceiveQrRevealGeometry(moduleCount: moduleCount, imageSize: imageSize, scale: scale)
        guard moduleSide > 0.0, moduleCount >= 21 else {
            return
        }
        let plan = walletReceiveQrRevealPlan(moduleCount: moduleCount, moduleSide: moduleSide, padding: padding, jitter: { Double.random(in: 0.0 ... 0.05) })

        let codeLayer = SimpleLayer()
        codeLayer.frame = CGRect(origin: .zero, size: imageSize)
        codeLayer.contents = image
        layer.addSublayer(codeLayer)

        let revealMask = SimpleLayer()
        revealMask.frame = codeLayer.bounds
        codeLayer.mask = revealMask

        let now = CACurrentMediaTime()
        for (index, frames) in plan.batches.enumerated() {
            let path = CGMutablePath()
            for frame in frames {
                path.addRect(frame)
            }

            let batchLayer = CAShapeLayer()
            batchLayer.frame = revealMask.bounds
            batchLayer.contentsScale = scale
            batchLayer.fillColor = NSColor.black.cgColor
            batchLayer.path = path
            revealMask.addSublayer(batchLayer)

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = 0.12
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.beginTime = batchLayer.convertTime(now, from: nil) + walletReceiveQrRevealBatchDelay(index: index, delay: delay, duration: duration)
            fade.fillMode = .backwards
            batchLayer.add(fade, forKey: "opacity")
        }

        for frame in plan.markers {
            let markerLayer = SimpleLayer()
            markerLayer.frame = frame
            markerLayer.contents = image.cropping(to: CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale).integral)
            layer.addSublayer(markerLayer)

            let grow = makeSpringAnimation("transform.scale")
            grow.fromValue = 0.01
            grow.toValue = 1.0
            grow.beginTime = markerLayer.convertTime(now, from: nil) + delay
            grow.fillMode = .backwards
            markerLayer.add(grow, forKey: "scale")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = 0.12
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.beginTime = markerLayer.convertTime(now, from: nil) + delay
            fade.fillMode = .backwards
            markerLayer.add(fade, forKey: "opacity")
        }
    }
}
