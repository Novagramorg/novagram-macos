import Cocoa
import QuartzCore

struct QrStudioAppearanceReveal {
    let center: CGPoint
    let size: CGSize
    let startTime: CFTimeInterval

    func animation(_ keyPath: String, values: [Any], layer: CALayer) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.duration = QrStudioReveal.duration
        animation.beginTime = layer.convertTime(self.startTime, from: nil)
        animation.calculationMode = .linear
        animation.fillMode = .backwards
        return animation
    }

    func makeMask(frame: CGRect) -> CALayer {
        let localCenter = CGPoint(x: self.center.x - frame.minX, y: self.center.y - frame.minY)
        let steps = 30
        if #available(macOS 10.14, *) {
            let unitCenter = CGPoint(x: localCenter.x / frame.width, y: localCenter.y / frame.height)
            var endPoints: [NSValue] = []
            var locations: [[NSNumber]] = []
            for step in 0...steps {
                let linear = Double(step) / Double(steps)
                let progress = 1.0 - pow(1.0 - linear, 2.0)
                let radius = max(QrStudioReveal.radius(progress: progress, center: self.center, size: self.size), 0.01)
                endPoints.append(NSValue(point: CGPoint(x: unitCenter.x + radius / frame.width, y: unitCenter.y + radius / frame.height)))
                let soft = radius > 1.0 ? max(0.0, (radius - QrStudioReveal.feather) / radius) : 0.0
                locations.append([0.0, NSNumber(value: Double(soft)), 1.0])
            }
            let mask = CAGradientLayer()
            mask.type = .radial
            mask.frame = CGRect(origin: .zero, size: frame.size)
            mask.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.white.withAlphaComponent(0.0).cgColor]
            mask.startPoint = unitCenter
            mask.endPoint = endPoints[steps].pointValue
            mask.locations = locations[steps]
            mask.add(self.animation("endPoint", values: endPoints, layer: mask), forKey: "reveal")
            mask.add(self.animation("locations", values: locations, layer: mask), forKey: "revealLocations")
            return mask
        } else {
            var bounds: [NSValue] = []
            for step in 0...steps {
                let linear = Double(step) / Double(steps)
                let progress = 1.0 - pow(1.0 - linear, 2.0)
                let radius = max(QrStudioReveal.radius(progress: progress, center: self.center, size: self.size), 0.01) / 0.72
                bounds.append(NSValue(rect: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)))
            }
            let mask = CALayer()
            mask.contents = qrStudioRevealDiscImage
            mask.contentsGravity = .resize
            mask.bounds = bounds[steps].rectValue
            mask.position = localCenter
            mask.add(self.animation("bounds", values: bounds, layer: mask), forKey: "reveal")
            return mask
        }
    }
}
