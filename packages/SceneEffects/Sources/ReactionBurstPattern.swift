import Foundation
import CoreGraphics

public struct ReactionBurstPattern {
    public struct Sample {
        public let position: CGPoint
        public let scale: CGSize
        public let opacity: CGFloat
    }

    struct Keyframe {
        let time: CGFloat
        let value: [CGFloat]
        let easing: (CGFloat, CGFloat, CGFloat, CGFloat)?
        let outTangent: [CGFloat]?
        let inTangent: [CGFloat]?

        init(_ time: CGFloat, _ value: [CGFloat], _ easing: (CGFloat, CGFloat, CGFloat, CGFloat)? = nil, out outTangent: [CGFloat]? = nil, in inTangent: [CGFloat]? = nil) {
            self.time = time
            self.value = value
            self.easing = easing
            self.outTangent = outTangent
            self.inTangent = inTangent
        }
    }

    struct Copy {
        let inPoint: CGFloat
        let outPoint: CGFloat
        let position: [Keyframe]
        let scale: [Keyframe]
        let opacity: [Keyframe]
    }

    public static let frameRate: CGFloat = 60
    public static let frameCount: CGFloat = 91
    public static let side: CGFloat = 512
    public static let emojiSide: CGFloat = 500
    static let parentScale: CGFloat = 0.99

    public static var duration: Double {
        return Double(frameCount / frameRate)
    }

    public static var copyCount: Int {
        return copies.count
    }

    private static let scaleEasing: (CGFloat, CGFloat, CGFloat, CGFloat) = (0.167, 0.167, 0.833, 0.833)
    private static let fadeEasing: (CGFloat, CGFloat, CGFloat, CGFloat) = (0.3, 0, 0.4, 1)

    static let copies: [Copy] = [
        Copy(inPoint: 3, outPoint: 46,
             position: [
                Keyframe(3, [-3.909, -18.385], (0.195, 0.205, 0.504, 0.922), out: [0, 0], in: [0, 0]),
                Keyframe(13, [-22.092, -88.1], (0.279, 0.04, 0.46, 1), out: [0, 0], in: [0, 0]),
                Keyframe(59, [-31.592, 275.598]),
             ],
             scale: [Keyframe(4, [12, 12], scaleEasing), Keyframe(13, [20, 20], scaleEasing), Keyframe(36, [28, 28], scaleEasing), Keyframe(47, [4, 4])],
             opacity: [Keyframe(41, [100], fadeEasing), Keyframe(48.884765625, [0])]),
        Copy(inPoint: 3, outPoint: 49,
             position: [
                Keyframe(3, [-23.388, -13.688], (0.02, 0, 0.109, 0.548), out: [10.707, -41.715], in: [-38.374, 0.791]),
                Keyframe(13, [45.744, -148.649], (0.474, 0.378, 0.708, 1), out: [43.367, -0.894], in: [-12.625, -246.426]),
                Keyframe(61, [172.813, 307.068]),
             ],
             scale: [Keyframe(3, [-8, 8], scaleEasing), Keyframe(13, [-14, 14], scaleEasing), Keyframe(43, [-21, 21], scaleEasing), Keyframe(52, [-4, 4])],
             opacity: [Keyframe(43, [100], fadeEasing), Keyframe(53, [0])]),
        Copy(inPoint: 4, outPoint: 53,
             position: [
                Keyframe(4, [-25.479, -36.14], (0.137, 0.309, 0.417, 0.808), out: [-14.958, -20.45], in: [37.448, -4.406]),
                Keyframe(17, [-144.226, -140.579], (0.385, 0.212, 0.434, 1), out: [-42.843, 5.041], in: [0, 0]),
                Keyframe(73.47265625, [-222.086, 269.091]),
             ],
             scale: [Keyframe(4, [15, 15], (0.167, 0.167, 0.8, 1)), Keyframe(42, [24, 24], (0.167, 0.175, 0.833, 0.833)), Keyframe(55, [5, 5])],
             opacity: [Keyframe(47, [100], fadeEasing), Keyframe(55.8671875, [0])]),
        Copy(inPoint: 8, outPoint: 61,
             position: [
                Keyframe(7, [0.959, -4.44], (0.02, 0, 0.266, 0.874), out: [-18.201, -59.818], in: [35.75, 1.133]),
                Keyframe(19, [-62.024, -177.109], (0.556, 0.158, 0.708, 1), out: [-53.216, 3.549], in: [0, 0]),
                Keyframe(74, [-112.134, 339.231]),
             ],
             scale: [Keyframe(8, [-12, 12], scaleEasing), Keyframe(53, [-24, 24], scaleEasing), Keyframe(63, [-4, 4])],
             opacity: [Keyframe(55, [100], fadeEasing), Keyframe(65, [0])]),
        Copy(inPoint: 5, outPoint: 67,
             position: [
                Keyframe(5, [25.869, -26.788], (0.02, 0, 0.069, 0.731), out: [14.597, -73.616], in: [-41.626, 1.096]),
                Keyframe(20, [98.524, -213.609], (0.466, 0.207, 0.705, 1), out: [50.945, -1.349], in: [-11.393, -177.824]),
                Keyframe(76, [194.127, 275.605]),
             ],
             scale: [Keyframe(5, [8, 8], scaleEasing), Keyframe(13, [15, 15], scaleEasing), Keyframe(57.842, [20, 20], scaleEasing), Keyframe(69, [7, 7])],
             opacity: [Keyframe(60, [100], fadeEasing), Keyframe(70.109375, [0])]),
        Copy(inPoint: 5, outPoint: 72,
             position: [
                Keyframe(5, [-13.449, -6.509], (0.02, 0, 0.1, 1), out: [0, 0], in: [-14.652, 1.25]),
                Keyframe(21, [-3.854, -220.909], (0.43, 0, 0.767, 0.698), out: [15.073, -1.286], in: [0.606, -106.051]),
                Keyframe(79, [24.793, 345.5]),
             ],
             scale: [Keyframe(7, [-10, 10], (0.2, 0, 0.7, 1)), Keyframe(62, [-24, 24], (0.27, 0, 0.45, 1)), Keyframe(75, [-8, 5])],
             opacity: [Keyframe(66, [100], fadeEasing), Keyframe(77, [0])]),
        Copy(inPoint: 8, outPoint: 56,
             position: [
                Keyframe(8, [-4.388, -33.688], (0.02, 0, 0.109, 0.78), out: [5.707, -35.715], in: [-29.498, -0.693]),
                Keyframe(19, [31.744, -160.649], (0.474, 0.154, 0.708, 1), out: [38.182, 0.896], in: [-12.625, -187.426]),
                Keyframe(67, [98.813, 287.068]),
             ],
             scale: [Keyframe(8, [8, 8], scaleEasing), Keyframe(19, [14, 14], scaleEasing), Keyframe(50, [17, 17], scaleEasing), Keyframe(60, [5, 5])],
             opacity: [Keyframe(50, [100], fadeEasing), Keyframe(60, [0])]),
    ]

    public static func sample(copy index: Int, frame: CGFloat) -> Sample {
        let copy = self.copies[index]
        let local = value(of: copy.position, at: frame, spatial: true)
        let scale = value(of: copy.scale, at: frame, spatial: false)
        let visible = frame >= copy.inPoint && frame < copy.outPoint
        let opacity = visible ? value(of: copy.opacity, at: frame, spatial: false)[0] / 100 : 0
        let x = local[0] * parentScale
        let y = local[1] * parentScale
        return Sample(position: CGPoint(x: x, y: -y), scale: CGSize(width: scale[0] / 100 * parentScale, height: scale[1] / 100 * parentScale), opacity: max(0, min(1, opacity)))
    }

    static func value(of keyframes: [Keyframe], at frame: CGFloat, spatial: Bool) -> [CGFloat] {
        guard let first = keyframes.first, let last = keyframes.last else {
            return []
        }
        if frame <= first.time {
            return first.value
        }
        if frame >= last.time {
            return last.value
        }
        var index = 0
        while index + 1 < keyframes.count && keyframes[index + 1].time <= frame {
            index += 1
        }
        let from = keyframes[index]
        let to = keyframes[index + 1]
        let linear = (frame - from.time) / (to.time - from.time)
        let eased: CGFloat
        if let easing = from.easing {
            eased = timingValue(linear, easing)
        } else {
            eased = linear
        }
        if spatial, let outTangent = from.outTangent, let inTangent = from.inTangent, outTangent.contains(where: { $0 != 0 }) || inTangent.contains(where: { $0 != 0 }) {
            let p0 = CGPoint(x: from.value[0], y: from.value[1])
            let p3 = CGPoint(x: to.value[0], y: to.value[1])
            let p1 = CGPoint(x: p0.x + outTangent[0], y: p0.y + outTangent[1])
            let p2 = CGPoint(x: p3.x + inTangent[0], y: p3.y + inTangent[1])
            let point = pointAtArcFraction(eased, p0, p1, p2, p3)
            return [point.x, point.y]
        }
        return zip(from.value, to.value).map { $0 + ($1 - $0) * eased }
    }

    static func timingValue(_ x: CGFloat, _ easing: (CGFloat, CGFloat, CGFloat, CGFloat)) -> CGFloat {
        let (x1, y1, x2, y2) = easing
        func coordinate(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        var t = x
        for _ in 0 ..< 48 {
            let value = coordinate(t, x1, x2)
            if abs(value - x) < 1e-7 {
                break
            }
            if value < x {
                low = t
            } else {
                high = t
            }
            t = (low + high) / 2
        }
        return coordinate(t, y1, y2)
    }

    static func cubicPoint(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    static func pointAtArcFraction(_ fraction: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
        let steps = 96
        var points: [CGPoint] = [p0]
        var lengths: [CGFloat] = [0]
        for step in 1 ... steps {
            let point = cubicPoint(CGFloat(step) / CGFloat(steps), p0, p1, p2, p3)
            lengths.append(lengths[step - 1] + hypot(point.x - points[step - 1].x, point.y - points[step - 1].y))
            points.append(point)
        }
        let target = max(0, min(1, fraction)) * lengths[steps]
        var index = 1
        while index < steps && lengths[index] < target {
            index += 1
        }
        let span = lengths[index] - lengths[index - 1]
        let t = span > 0 ? (target - lengths[index - 1]) / span : 0
        let a = points[index - 1], b = points[index]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
