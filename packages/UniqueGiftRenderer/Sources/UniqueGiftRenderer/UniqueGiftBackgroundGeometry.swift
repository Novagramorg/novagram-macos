import Foundation
import CoreGraphics
import LokiRng

public struct UniqueGiftColors: Hashable {
    public let center: UInt32
    public let edge: UInt32
    public let pattern: UInt32

    public init(center: Int32, edge: Int32, pattern: Int32) {
        self.center = UInt32(bitPattern: center) & 0xffffff
        self.edge = UInt32(bitPattern: edge) & 0xffffff
        self.pattern = UInt32(bitPattern: pattern) & 0xffffff
    }

    public init(centerRGB: UInt32, edgeRGB: UInt32, patternRGB: UInt32) {
        self.center = centerRGB & 0xffffff
        self.edge = edgeRGB & 0xffffff
        self.pattern = patternRGB & 0xffffff
    }
}

public struct UniqueGiftEllipse: Equatable {
    public let center: CGPoint
    public let radii: CGSize
}

public struct UniqueGiftPatternItem: Equatable {
    public let frame: CGRect
    public let alpha: CGFloat
}

public struct UniqueGiftBackgroundGeometry: Hashable {
    public enum Gradient: Hashable {
        case gift
        case profile(center: CGPoint)
    }

    public enum PatternDensity: Hashable {
        case small
        case compact
        case regular

        public static func forWidth(_ width: CGFloat) -> PatternDensity {
            if width <= 60.0 {
                return .small
            } else if width < 150.0 {
                return .compact
            } else {
                return .regular
            }
        }
    }

    public static let patternTintWidth: CGFloat = 380.0
    public static let patternTintAlpha: CGFloat = 0.6
    public static let patternGlyphAlpha: CGFloat = 0.8

    public var size: CGSize
    public var patternCenter: CGPoint
    public var defaultHeight: CGFloat
    public var avatarSize: CGFloat
    public var topExtension: CGFloat
    public var gradientOnTop: Bool
    public var patternIconScale: CGFloat
    public var gradient: Gradient
    public var cornerRadius: CGFloat
    public var patternDensity: PatternDensity

    public init(size: CGSize, patternCenter: CGPoint, defaultHeight: CGFloat, avatarSize: CGFloat = 100.0, topExtension: CGFloat = 0.0, gradientOnTop: Bool = false, patternIconScale: CGFloat = 1.0, gradient: Gradient = .gift, cornerRadius: CGFloat = 0.0, patternDensity: PatternDensity? = nil) {
        self.size = size
        self.patternCenter = patternCenter
        self.defaultHeight = defaultHeight
        self.avatarSize = avatarSize
        self.topExtension = topExtension
        self.gradientOnTop = gradientOnTop
        self.patternIconScale = patternIconScale
        self.gradient = gradient
        self.cornerRadius = cornerRadius
        self.patternDensity = patternDensity ?? .forWidth(size.width)
    }

    public static func item(size: CGSize, giftCenterY: CGFloat, cornerRadius: CGFloat) -> UniqueGiftBackgroundGeometry {
        return UniqueGiftBackgroundGeometry(size: size, patternCenter: CGPoint(x: size.width / 2.0, y: giftCenterY), defaultHeight: size.height, cornerRadius: cornerRadius, patternDensity: size.width <= 60.0 ? .small : .compact)
    }

    public static func header(size: CGSize, patternCenterY: CGFloat = 104.0, topExtension: CGFloat = 0.0) -> UniqueGiftBackgroundGeometry {
        return UniqueGiftBackgroundGeometry(size: size, patternCenter: CGPoint(x: size.width / 2.0, y: patternCenterY + topExtension), defaultHeight: 300.0, topExtension: topExtension, gradientOnTop: true)
    }

    public static func message(size: CGSize, patternCenterY: CGFloat = 104.0, cornerRadius: CGFloat) -> UniqueGiftBackgroundGeometry {
        return UniqueGiftBackgroundGeometry(size: size, patternCenter: CGPoint(x: size.width / 2.0, y: patternCenterY), defaultHeight: size.height, cornerRadius: cornerRadius)
    }

    public static func profile(size: CGSize, avatarCenter: CGPoint, avatarSize: CGFloat, defaultHeight: CGFloat, gradientCenter: CGPoint) -> UniqueGiftBackgroundGeometry {
        return UniqueGiftBackgroundGeometry(size: size, patternCenter: avatarCenter, defaultHeight: defaultHeight, avatarSize: avatarSize, gradient: .profile(center: gradientCenter))
    }

    public var gradientFrame: CGRect {
        let gradientHeight = self.defaultHeight + self.topExtension
        let gradientWidth: CGFloat
        switch self.gradient {
        case .gift:
            gradientWidth = self.defaultHeight
        case .profile:
            gradientWidth = self.size.width
        }
        return CGRect(x: (self.size.width - gradientWidth) / 2.0, y: self.gradientOnTop ? 0.0 : self.size.height - gradientHeight, width: gradientWidth, height: gradientHeight)
    }

    public var gradientEllipse: UniqueGiftEllipse {
        let frame = self.gradientFrame
        let start: CGPoint
        switch self.gradient {
        case .gift:
            start = CGPoint(x: 0.5, y: frame.height > 0.0 ? self.patternCenter.y / frame.height : 0.5)
        case let .profile(center):
            start = center
        }
        return UniqueGiftEllipse(center: CGPoint(x: frame.minX + start.x * frame.width, y: frame.minY + start.y * frame.height), radii: CGSize(width: abs(1.0 - start.x) * frame.width, height: abs(1.0 - start.y) * frame.height))
    }

    public var patternTintFrame: CGRect {
        let height = floor(self.defaultHeight)
        return CGRect(x: self.patternCenter.x - UniqueGiftBackgroundGeometry.patternTintWidth / 2.0, y: self.patternCenter.y - height / 2.0, width: UniqueGiftBackgroundGeometry.patternTintWidth, height: height)
    }

    public var patternTintEllipse: UniqueGiftEllipse {
        return UniqueGiftEllipse(center: self.patternCenter, radii: CGSize(width: UniqueGiftBackgroundGeometry.patternTintWidth / 2.0, height: floor(self.defaultHeight) / 2.0))
    }

    public func patternItems(transitionFraction: CGFloat = 0.0) -> [UniqueGiftPatternItem] {
        var baseDistance = self.avatarSize / 2.0 + 22.0
        var baseRowDistance: CGFloat = 28.0
        var baseItemSize: CGFloat = 26.0 * self.patternIconScale
        switch self.patternDensity {
        case .small:
            baseDistance *= 0.35
            baseRowDistance *= 0.3
            baseItemSize *= 0.4
        case .compact:
            baseDistance *= 0.6
            baseRowDistance *= 0.6
            baseItemSize *= 0.83
        case .regular:
            break
        }

        let random = LokiRng(seed0: 123, seed1: 0, seed2: 0)
        let rows = 5
        let countPerRow = 7
        let angleSpan = CGFloat.pi * 2.0 / CGFloat(countPerRow - 1)
        var items: [UniqueGiftPatternItem] = []
        items.reserveCapacity(rows * (countPerRow - 1))
        for row in 0 ..< rows {
            for i in 0 ..< countPerRow - 1 {
                let baseItemDistance = baseDistance + CGFloat(row) * baseRowDistance
                let distanceFraction = max(0.0, min(1.0, baseItemDistance / (baseDistance * 2.0)))
                let scaleFraction = uniqueGiftPatternScaleValue(fraction: transitionFraction * 1.6, t: distanceFraction)
                let distance = baseItemDistance * (1.0 - scaleFraction) + 20.0 * scaleFraction
                var angle = -CGFloat.pi * 0.5 + CGFloat(i) * angleSpan
                if row % 2 != 0 {
                    angle += angleSpan * 0.5
                }
                let position = CGPoint(x: self.patternCenter.x + cos(angle) * distance, y: self.patternCenter.y + sin(angle) * distance)
                let scale = 0.7 + CGFloat(random.next()) * (1.0 - 0.7)
                let itemSize = floor(baseItemSize * scale)
                items.append(UniqueGiftPatternItem(frame: CGRect(x: position.x - itemSize / 2.0, y: position.y - itemSize / 2.0, width: itemSize, height: itemSize), alpha: 1.0 - scaleFraction))
            }
        }
        return items
    }
}

public func uniqueGiftPatternScaleValue(fraction: CGFloat, t: CGFloat) -> CGFloat {
    let windowSize: CGFloat = 0.8
    let windowStartOffset = -windowSize
    let windowEndOffset: CGFloat = 1.0
    let windowPosition = (1.0 - fraction) * windowStartOffset + fraction * windowEndOffset
    let windowT = max(0.0, min(windowSize, t - windowPosition)) / windowSize
    return 1.0 - uniqueGiftBezierPoint(0.6, 0.0, 0.4, 1.0, windowT)
}

private func bezierA(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 1.0 - 3.0 * a2 + 3.0 * a1
}

private func bezierB(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 3.0 * a2 - 6.0 * a1
}

private func bezierC(_ a1: CGFloat) -> CGFloat {
    return 3.0 * a1
}

private func calcBezier(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return ((bezierA(a1, a2) * t + bezierB(a1, a2)) * t + bezierC(a1)) * t
}

private func calcSlope(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 3.0 * bezierA(a1, a2) * t * t + 2.0 * bezierB(a1, a2) * t + bezierC(a1)
}

private func tForX(_ x: CGFloat, _ x1: CGFloat, _ x2: CGFloat) -> CGFloat {
    var t = x
    for _ in 0 ..< 4 {
        let slope = calcSlope(t, x1, x2)
        if slope == 0.0 {
            return t
        }
        t -= (calcBezier(t, x1, x2) - x) / slope
    }
    return t
}

func uniqueGiftBezierPoint(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat) -> CGFloat {
    var value = calcBezier(tForX(x, x1, x2), y1, y2)
    if value >= 0.997 {
        value = 1.0
    }
    return value
}
