import Cocoa

enum ChatWalletTransferFlightMotion {
    static let duration: Double = 0.62
    static let cardTimeout: Double = 0.5
    static let handOverTimeout: Double = 1.5
    static let landingDuration: Double = 1.2

    static func progress(now: CFTimeInterval, start: CFTimeInterval) -> CGFloat {
        return CGFloat(min(1.0, max(0.0, now - start) / duration))
    }

    static func center(origin: NSPoint, target: NSPoint, t: CGFloat) -> NSPoint {
        let deltaY = target.y - origin.y
        let rise = 56.0 + max(0.0, -deltaY)
        let b = -2.0 * rise - 2.0 * sqrt(max(0.0, rise * rise + rise * deltaY))
        return NSMakePoint(origin.x + (target.x - origin.x) * t, origin.y + b * t + (deltaY - b) * t * t)
    }

    static func width(sourceWidth: CGFloat, targetWidth: CGFloat, t: CGFloat) -> CGFloat {
        return (sourceWidth + (targetWidth - sourceWidth) * t) * (1.0 + 0.28 * sin(.pi * min(1.0, t / 0.75)))
    }

    static func rotationSpeed(t: CGFloat) -> Float {
        return Float(2.0 * .pi / 26.0 + (5.0 - 2.0 * .pi / 26.0) * min(1.0, t / 0.6))
    }

    static func usesCardAppearance(t: CGFloat) -> Bool {
        return t > 0.5
    }

    static func landing(at time: Double, isLast: Bool) -> (scale: CGFloat, offset: CGFloat) {
        let impact = isLast ? 0 : sin(2 * Double.pi * 2.2 * time) * exp(-time / 0.2)
        return (CGFloat(1 - 0.025 * impact), CGFloat(4 * impact))
    }
}

enum ChatWalletTransferArrivalMotion {
    static let spacing: Double = 0.9
    static let afterLanding: Double = 1.8
    static let glintDelay: Double = 0.6

    static func card(time t: Double, finish: Double, rise: Bool, height: CGFloat) -> (scale: CGFloat, offset: CGFloat, opacity: CGFloat) {
        let bounce = finish > 0 && finish < 1.2 ? -sin(2 * .pi * 2 * finish) * exp(-finish / 0.25) : 0
        if rise {
            let spring = t < 0.8 ? 1 - exp(-9 * t) * (cos(13 * t) + 9.0 / 13.0 * sin(13 * t)) : 1
            let scale = CGFloat(0.86 + 0.14 * spring) * CGFloat(1 + 0.045 * bounce)
            return (scale, CGFloat(70 * (1 - spring)) + (1 - scale) * height * 0.5, CGFloat(min(1, t / 0.12)))
        } else {
            let pop = t < 1.2 ? 0.05 * sin(2 * .pi * 1.8 * t) * exp(-t / 0.22) : 0
            return (CGFloat((1 + pop) * (1 + 0.045 * bounce)), 0, 1)
        }
    }

    static func ribbon(finish: Double) -> (length: Double, width: Double) {
        let tau = 0.08
        let w = 2 * Double.pi * 1.6
        let length = 1 - exp(-finish / tau) * (cos(w * finish) + sin(w * finish) / (tau * w))
        let width = 1 - pow(1 - min(1, finish / 0.3), 2.2)
        return (length, width)
    }

    static func ribbonTransform(length: Double, width: Double, pivot: NSPoint, center: NSPoint) -> CGAffineTransform {
        return CGAffineTransform(translationX: pivot.x - center.x, y: pivot.y - center.y)
            .rotated(by: .pi / 4).scaledBy(x: CGFloat(max(0.001, length)), y: CGFloat(0.2 + 0.8 * width))
            .rotated(by: -.pi / 4).translatedBy(x: center.x - pivot.x, y: center.y - pivot.y)
    }

    static func ribbonAlpha(length: Double) -> CGFloat {
        return CGFloat(min(1, max(0, length * 4)))
    }

    static func ribbonTextAlpha(length: Double) -> CGFloat {
        return CGFloat(min(1, max(0, (length - 0.6) / 0.35)))
    }
}
