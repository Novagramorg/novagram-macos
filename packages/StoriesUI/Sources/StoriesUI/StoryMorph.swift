import Foundation
import CoreGraphics

struct StoryMorphSpring: Equatable {
    var omega: Double
    var damping: Double

    static let position = StoryMorphSpring(omega: 21.0, damping: 0.84)
    static let width = StoryMorphSpring(omega: 22.5, damping: 0.74)
    static let height = StoryMorphSpring(omega: 19.0, damping: 0.76)
    static let roundness = StoryMorphSpring(omega: 15.0, damping: 0.92)
    static let openness = StoryMorphSpring(omega: 21.0, damping: 1.0)
    static let collapse = StoryMorphSpring(omega: 23.56, damping: 1.0)

    func solve(_ t: Double, displacement x0: Double, velocity v0: Double) -> (x: Double, v: Double) {
        if t <= 0 {
            return (x0, v0)
        }
        let w = self.omega
        let z = self.damping
        if z < 1.0 - 1e-6 {
            let wd = w * (1.0 - z * z).squareRoot()
            let e = exp(-z * w * t)
            let a = x0
            let b = (v0 + z * w * x0) / wd
            let c = cos(wd * t)
            let s = sin(wd * t)
            let x = e * (a * c + b * s)
            let v = e * ((b * wd - z * w * a) * c - (a * wd + z * w * b) * s)
            return (x, v)
        } else if z > 1.0 + 1e-6 {
            let r = w * (z * z - 1.0).squareRoot()
            let r1 = -z * w + r
            let r2 = -z * w - r
            let c2 = (v0 - r1 * x0) / (r2 - r1)
            let c1 = x0 - c2
            let e1 = exp(r1 * t)
            let e2 = exp(r2 * t)
            return (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
        } else {
            let e = exp(-w * t)
            let b = v0 + w * x0
            let x = (x0 + b * t) * e
            let v = (b - w * (x0 + b * t)) * e
            return (x, v)
        }
    }

    func settlingTime(displacement x0: Double, velocity v0: Double, tolerance: Double) -> Double {
        if abs(x0) <= tolerance && abs(v0) * StoryMorphSampling.step <= tolerance {
            return 0
        }
        let step = StoryMorphSampling.step / 4.0
        var lastOutside: Double = 0
        var t: Double = 0
        while t <= StoryMorphSampling.maximumDuration {
            if abs(self.solve(t, displacement: x0, velocity: v0).x) > tolerance {
                lastOutside = t
            }
            t += step
        }
        return min(StoryMorphSampling.maximumDuration, lastOutside + step)
    }
}

struct StoryMorphChannel: Equatable {
    var from: Double
    var to: Double
    var velocity: Double
    var spring: StoryMorphSpring
    var tolerance: Double

    func value(at t: Double) -> Double {
        return self.to + self.spring.solve(t, displacement: self.from - self.to, velocity: self.velocity).x
    }

    func velocity(at t: Double) -> Double {
        return self.spring.solve(t, displacement: self.from - self.to, velocity: self.velocity).v
    }

    var settlingTime: Double {
        return self.spring.settlingTime(displacement: self.from - self.to, velocity: self.velocity, tolerance: self.tolerance)
    }
}

struct StoryMorphShape: Equatable {
    var rect: CGRect
    var cornerRadius: CGFloat

    var roundness: CGFloat {
        let half = min(self.rect.width, self.rect.height) / 2.0
        if half <= 0 {
            return 0
        }
        return max(0, min(1, self.cornerRadius / half))
    }

    var isValid: Bool {
        let values = [self.rect.minX, self.rect.minY, self.rect.width, self.rect.height, self.cornerRadius]
        return values.allSatisfy { $0.isFinite } && self.rect.width >= 1 && self.rect.height >= 1
    }

    func state(openness: CGFloat) -> StoryMorphState {
        return StoryMorphState(center: CGPoint(x: self.rect.midX, y: self.rect.midY), size: self.rect.size, roundness: self.roundness, openness: openness)
    }
}

struct StoryMorphState: Equatable {
    var center: CGPoint
    var size: CGSize
    var roundness: CGFloat
    var openness: CGFloat

    var rect: CGRect {
        return CGRect(x: self.center.x - self.size.width / 2.0, y: self.center.y - self.size.height / 2.0, width: self.size.width, height: self.size.height)
    }

    var cornerRadius: CGFloat {
        return max(0, min(1, self.roundness)) * min(self.size.width, self.size.height) / 2.0
    }
}

struct StoryMorphVelocity: Equatable {
    var center: CGPoint
    var size: CGSize
    var roundness: CGFloat
    var openness: CGFloat

    static let zero = StoryMorphVelocity(center: .zero, size: .zero, roundness: 0, openness: 0)
}

struct StoryMorphSprings: Equatable {
    var position: StoryMorphSpring
    var width: StoryMorphSpring
    var height: StoryMorphSpring
    var roundness: StoryMorphSpring
    var openness: StoryMorphSpring

    static let expand = StoryMorphSprings(position: .position, width: .width, height: .height, roundness: .roundness, openness: .openness)
    static let collapse = StoryMorphSprings(position: .collapse, width: .collapse, height: .collapse, roundness: .collapse, openness: .collapse)
}

struct StoryMorphPlan: Equatable {
    static let geometryTolerance: Double = 0.2
    static let unitTolerance: Double = 0.002

    let centerX: StoryMorphChannel
    let centerY: StoryMorphChannel
    let width: StoryMorphChannel
    let height: StoryMorphChannel
    let roundness: StoryMorphChannel
    let openness: StoryMorphChannel
    let duration: Double
    let from: StoryMorphState
    let to: StoryMorphState

    init(from: StoryMorphState, to: StoryMorphState, velocity: StoryMorphVelocity = .zero, springs: StoryMorphSprings) {
        self.from = from
        self.to = to
        let geometry = StoryMorphPlan.geometryTolerance
        let unit = StoryMorphPlan.unitTolerance
        self.centerX = StoryMorphChannel(from: Double(from.center.x), to: Double(to.center.x), velocity: Double(velocity.center.x), spring: springs.position, tolerance: geometry)
        self.centerY = StoryMorphChannel(from: Double(from.center.y), to: Double(to.center.y), velocity: Double(velocity.center.y), spring: springs.position, tolerance: geometry)
        self.width = StoryMorphChannel(from: Double(from.size.width), to: Double(to.size.width), velocity: Double(velocity.size.width), spring: springs.width, tolerance: geometry)
        self.height = StoryMorphChannel(from: Double(from.size.height), to: Double(to.size.height), velocity: Double(velocity.size.height), spring: springs.height, tolerance: geometry)
        self.roundness = StoryMorphChannel(from: Double(from.roundness), to: Double(to.roundness), velocity: Double(velocity.roundness), spring: springs.roundness, tolerance: unit)
        self.openness = StoryMorphChannel(from: Double(from.openness), to: Double(to.openness), velocity: Double(velocity.openness), spring: springs.openness, tolerance: unit)
        self.duration = [self.centerX, self.centerY, self.width, self.height, self.roundness, self.openness].map { $0.settlingTime }.max() ?? 0
    }

    func state(at t: Double) -> StoryMorphState {
        if t <= 0 {
            return self.from
        }
        if t >= self.duration {
            return self.to
        }
        return StoryMorphState(
            center: CGPoint(x: self.centerX.value(at: t), y: self.centerY.value(at: t)),
            size: CGSize(width: max(1, self.width.value(at: t)), height: max(1, self.height.value(at: t))),
            roundness: CGFloat(self.roundness.value(at: t)),
            openness: CGFloat(self.openness.value(at: t))
        )
    }

    func velocity(at t: Double) -> StoryMorphVelocity {
        if t >= self.duration {
            return .zero
        }
        return StoryMorphVelocity(
            center: CGPoint(x: self.centerX.velocity(at: t), y: self.centerY.velocity(at: t)),
            size: CGSize(width: self.width.velocity(at: t), height: self.height.velocity(at: t)),
            roundness: CGFloat(self.roundness.velocity(at: t)),
            openness: CGFloat(self.openness.velocity(at: t))
        )
    }
}

struct StoryMorphGeometry: Equatable {
    let bubble: CGRect
    let cornerRadius: CGFloat
    let contentScale: CGFloat
    let contentFrame: CGRect
    let snapshotFrame: CGRect

    init(state: StoryMorphState, contentSize: CGSize) {
        let size = CGSize(width: max(1, state.size.width), height: max(1, state.size.height))
        self.bubble = CGRect(x: state.center.x - size.width / 2.0, y: state.center.y - size.height / 2.0, width: size.width, height: size.height)
        self.cornerRadius = max(0, min(1, state.roundness)) * min(size.width, size.height) / 2.0
        let scale: CGFloat
        if contentSize.width > 0 && contentSize.height > 0 {
            scale = max(size.width / contentSize.width, size.height / contentSize.height)
        } else {
            scale = 1
        }
        self.contentScale = scale
        let scaled = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        self.contentFrame = CGRect(x: (size.width - scaled.width) / 2.0, y: (size.height - scaled.height) / 2.0, width: scaled.width, height: scaled.height)
        let side = max(size.width, size.height)
        self.snapshotFrame = CGRect(x: (size.width - side) / 2.0, y: (size.height - side) / 2.0, width: side, height: side)
    }
}

struct StoryMorphFades {
    let snapshot: (CGFloat) -> CGFloat
    let chrome: (CGFloat) -> CGFloat
    let bubble: (CGFloat) -> CGFloat
    let source: (CGFloat) -> CGFloat

    struct Values: Equatable {
        var snapshot: CGFloat
        var chrome: CGFloat
        var bubble: CGFloat
        var source: CGFloat
    }

    func values(openness: CGFloat) -> Values {
        let o = max(0, min(1, openness))
        return Values(snapshot: clamp(self.snapshot(o)), chrome: clamp(self.chrome(o)), bubble: clamp(self.bubble(o)), source: clamp(self.source(o)))
    }

    static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        if b <= a {
            return x < a ? 0 : 1
        }
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    static func opening(hasSnapshot: Bool) -> StoryMorphFades {
        return .opening(hasSnapshot: hasSnapshot, startOpenness: 0, start: Values(snapshot: hasSnapshot ? 1 : 0, chrome: 0, bubble: hasSnapshot ? 1 : 0, source: hasSnapshot ? 0 : 1))
    }

    static func opening(hasSnapshot: Bool, startOpenness: CGFloat, start: Values) -> StoryMorphFades {
        let s = max(0, min(0.999, startOpenness))
        func at(_ fraction: CGFloat) -> CGFloat {
            return s + fraction * (1 - s)
        }
        return StoryMorphFades(
            snapshot: { o in start.snapshot * (1 - smoothstep(at(0.04), at(0.42), o)) },
            chrome: { o in start.chrome + (1 - start.chrome) * smoothstep(at(0.4), at(0.92), o) },
            bubble: { o in start.bubble + (1 - start.bubble) * smoothstep(at(0), at(0.16), o) },
            source: { o in hasSnapshot ? 0 : start.source * (1 - smoothstep(at(0.08), at(0.3), o)) }
        )
    }

    static func closing(hasSnapshot: Bool, hasDestination: Bool, startOpenness: CGFloat, start: Values) -> StoryMorphFades {
        let s = max(0.001, startOpenness)
        if !hasDestination {
            return StoryMorphFades(
                snapshot: { o in start.snapshot * smoothstep(0, s, o) },
                chrome: { o in start.chrome * smoothstep(0.5 * s, s, o) },
                bubble: { o in start.bubble * smoothstep(0, s, o) },
                source: { _ in 0 }
            )
        }
        return StoryMorphFades(
            snapshot: { o in hasSnapshot ? start.snapshot + (1 - start.snapshot) * (1 - smoothstep(0, 0.45 * s, o)) : 0 },
            chrome: { o in start.chrome * smoothstep(0.7 * s, s, o) },
            bubble: { o in hasSnapshot ? start.bubble + (1 - start.bubble) * (1 - smoothstep(0.5 * s, s, o)) : start.bubble * smoothstep(0, 0.35 * s, o) },
            source: { o in hasSnapshot ? 0 : start.source + (1 - start.source) * (1 - smoothstep(0, 0.4 * s, o)) }
        )
    }
}

private func clamp(_ value: CGFloat) -> CGFloat {
    if !value.isFinite {
        return 0
    }
    return max(0, min(1, value))
}

enum StoryMorphSampling {
    static let step: Double = 1.0 / 120.0
    static let maximumDuration: Double = 2.0

    static func times(duration: Double) -> [Double] {
        if duration <= 0 {
            return [0]
        }
        let count = max(1, Int((duration / self.step).rounded(.up)))
        return (0 ... count).map { min(duration, Double($0) * self.step) }
    }
}

struct StoryMorphSample: Equatable {
    let time: Double
    let state: StoryMorphState
    let geometry: StoryMorphGeometry
    let fades: StoryMorphFades.Values
}

struct StoryMorphTimeline {
    let plan: StoryMorphPlan
    let samples: [StoryMorphSample]

    init(plan: StoryMorphPlan, contentSize: CGSize, fades: StoryMorphFades) {
        self.plan = plan
        self.samples = StoryMorphSampling.times(duration: plan.duration).map { t in
            let state = plan.state(at: t)
            return StoryMorphSample(time: t, state: state, geometry: StoryMorphGeometry(state: state, contentSize: contentSize), fades: fades.values(openness: state.openness))
        }
    }

    var keyTimes: [NSNumber] {
        let duration = self.plan.duration
        if duration <= 0 {
            return [0]
        }
        return self.samples.map { NSNumber(value: $0.time / duration) }
    }
}

enum StoryMorphImageShape {
    static func cornerRadius(of image: CGImage, displaySize: CGSize) -> CGFloat? {
        let side = 128
        guard displaySize.width > 0, displaySize.height > 0, let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else {
            return nil
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            return pixels[(y * side + x) * 4 + 3]
        }
        let center = side / 2
        if alpha(center, center) < 128 {
            return nil
        }
        var corners: [Int] = []
        for (dx, dy, x0, y0) in [(1, 1, 0, 0), (-1, 1, side - 1, 0), (1, -1, 0, side - 1), (-1, -1, side - 1, side - 1)] {
            var step = 0
            while step < center, alpha(x0 + dx * step, y0 + dy * step) < 128 {
                step += 1
            }
            corners.append(step)
        }
        let inset = CGFloat(corners.max() ?? 0) / CGFloat(side)
        let diagonal: CGFloat = 1.0 - 1.0 / 2.0.squareRoot()
        let half = min(displaySize.width, displaySize.height) / 2.0
        let radius = inset * min(displaySize.width, displaySize.height) / diagonal
        return min(half, max(0, radius))
    }
}
