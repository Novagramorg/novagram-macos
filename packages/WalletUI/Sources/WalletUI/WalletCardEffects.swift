import Cocoa
import CoreImage
import TGUIKit
import TelegramTheme
import TelegramContext
import GeneralRows

public struct WalletCardTilt: Equatable {
    public var tx: CGFloat = 0
    public var ty: CGFloat = 0
    public init(tx: CGFloat = 0, ty: CGFloat = 0) {
        self.tx = tx
        self.ty = ty
    }
}

private func walletCardOklchColor(lightness: CGFloat, chroma: CGFloat, hueDegrees: CGFloat) -> CGColor {
    let hue = hueDegrees * .pi / 180.0
    let a = chroma * cos(hue)
    let b = chroma * sin(hue)

    let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
    let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
    let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b

    let l = l_ * l_ * l_
    let m = m_ * m_ * m_
    let s = s_ * s_ * s_

    let linearR = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let linearG = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let linearB = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    func gamma(_ value: CGFloat) -> CGFloat {
        let clamped = min(1.0, max(0.0, value))
        if clamped <= 0.0031308 {
            return clamped * 12.92
        }
        return 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
    }

    return CGColor(red: gamma(linearR), green: gamma(linearG), blue: gamma(linearB), alpha: 1.0)
}

private let walletCardShineBaseLightness: CGFloat = 0.6320535732
private let walletCardShineBaseChroma: CGFloat = 0.2017874156
private let walletCardShineHue: CGFloat = 254.0879
private let walletCardEffectSteps: Int = 200

private func walletCardOverlayComposite(base: (CGFloat, CGFloat, CGFloat), blend: CGColor) -> CGColor {
    let components = blend.components ?? [0, 0, 0, 1]
    let blendChannels: [CGFloat] = components.count >= 3 ? [components[0], components[1], components[2]] : [components[0], components[0], components[0]]
    let baseChannels = [base.0, base.1, base.2]
    var result: [CGFloat] = []
    for index in 0 ..< 3 {
        let baseValue = baseChannels[index]
        let blendValue = blendChannels[index]
        if baseValue < 0.5 {
            result.append(2.0 * baseValue * blendValue)
        } else {
            result.append(1.0 - 2.0 * (1.0 - baseValue) * (1.0 - blendValue))
        }
    }
    return CGColor(red: result[0], green: result[1], blue: result[2], alpha: 1.0)
}

public let walletCardShineColorLUT: [CGColor] = {
    let cardBase: (CGFloat, CGFloat, CGFloat) = (0.0, 136.0 / 255.0, 1.0)
    var colors: [CGColor] = []
    colors.reserveCapacity(walletCardEffectSteps + 1)
    for index in 0 ... walletCardEffectSteps {
        let ty = CGFloat(index) / CGFloat(walletCardEffectSteps) * 2.0 - 1.0
        let shine = walletCardOklchColor(lightness: walletCardShineBaseLightness + 0.066 + ty * 0.1, chroma: walletCardShineBaseChroma * 0.8, hueDegrees: walletCardShineHue)
        colors.append(walletCardOverlayComposite(base: cardBase, blend: shine))
    }
    return colors
}()

private struct WalletCardMaskCacheKey: Hashable {
    public let pixelSide: Int
    public let backingScale: Int
    public let shineBlurRadius: Int
}

private struct WalletCardMaskImages {
    public let shine: CGImage
    public let stars: CGImage
}

private final class WalletCardMaskRenderer {
    public static let shared = WalletCardMaskRenderer()

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let spokesKernel = CIColorKernel(source: """
        kernel vec4 walletCardSpokes(vec2 center, float spread) {
            vec2 delta = destCoord() - center;
            float position = atan(delta.y, delta.x) / 6.283185307179586;
            if (position < 0.0) {
                position += 1.0;
            }
            float first = max(0.0, 1.0 - abs(position - 0.25) / spread);
            float second = max(0.0, 1.0 - abs(position - 0.75) / spread);
            float alpha = max(first, second);
            return vec4(alpha, alpha, alpha, alpha);
        }
        """)
    private let lock = NSLock()
    private var cache: [WalletCardMaskCacheKey: WalletCardMaskImages] = [:]

    public func images(diameter: CGFloat, unit: CGFloat, backingScale: CGFloat) -> WalletCardMaskImages? {
        let effectiveBackingScale = min(2.0, backingScale)
        let pixelSide = max(8, Int(ceil(diameter * effectiveBackingScale)))
        let renderScale = CGFloat(pixelSide) / diameter
        let blurRadius = 10.0 * unit * renderScale
        let key = WalletCardMaskCacheKey(
            pixelSide: pixelSide,
            backingScale: Int(round(effectiveBackingScale * 1000.0)),
            shineBlurRadius: Int(round(blurRadius * 1000.0))
        )

        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached {
            return cached
        }

        guard let kernel = spokesKernel else {
            return nil
        }
        let extent = CGRect(x: 0.0, y: 0.0, width: CGFloat(pixelSide), height: CGFloat(pixelSide))
        let center = CIVector(x: extent.midX, y: extent.midY)
        guard let sharpShine = kernel.apply(extent: extent, arguments: [center, NSNumber(value: 0.11)]),
              let sharpStars = kernel.apply(extent: extent, arguments: [center, NSNumber(value: 0.16)]) else {
            return nil
        }

        let clampedShine = sharpShine.clampedToExtent()
        let blurredShine = clampedShine
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: extent)
        guard let shine = context.createCGImage(blurredShine, from: extent),
              let stars = context.createCGImage(sharpStars, from: extent) else {
            return nil
        }

        let result = WalletCardMaskImages(shine: shine, stars: stars)
        lock.lock()
        cache[key] = result
        lock.unlock()
        return result
    }
}

private func walletCardHash(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    var px = x - floor(x / 289.0) * 289.0
    var py = y - floor(y / 289.0) * 289.0
    px = (px * 123.34).truncatingRemainder(dividingBy: 1.0)
    py = (py * 456.21).truncatingRemainder(dividingBy: 1.0)
    if px < 0 { px += 1 }
    if py < 0 { py += 1 }
    let d = px * (px + 45.32) + py * (py + 45.32)
    px += d
    py += d
    let value = (px * py).truncatingRemainder(dividingBy: 1.0)
    return value < 0 ? value + 1 : value
}

private func walletCardValueNoise(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    let ix = floor(x)
    let iy = floor(y)
    let fx = x - ix
    let fy = y - iy
    let ux = fx * fx * (3.0 - 2.0 * fx)
    let uy = fy * fy * (3.0 - 2.0 * fy)
    let a = walletCardHash(ix, iy)
    let b = walletCardHash(ix + 1, iy)
    let c = walletCardHash(ix, iy + 1)
    let d = walletCardHash(ix + 1, iy + 1)
    let ab = a + (b - a) * ux
    let cd = c + (d - c) * ux
    return ab + (cd - ab) * uy
}

private func walletCardFbm(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    var value: CGFloat = 0
    var amplitude: CGFloat = 0.5
    var px = x
    var py = y
    for _ in 0 ..< 4 {
        value += amplitude * walletCardValueNoise(px, py)
        px *= 2
        py *= 2
        amplitude *= 0.5
    }
    return value
}

struct WalletCardTextureField {
    let width: Int
    let height: Int
    let steps: [UInt16]
    let range: ClosedRange<Int>
}

private let walletCardTextureSteps = 1024

func walletCardTextureField(size: NSSize, backingScale: CGFloat) -> WalletCardTextureField {
    let renderScale = min(2.0, backingScale)
    let width = max(1, Int(ceil(size.width * renderScale)))
    let height = max(1, Int(ceil(size.height * renderScale)))
    let heightPx = CGFloat(height)
    var steps = [UInt16](repeating: 0, count: width * height)
    var lowest = walletCardTextureSteps
    var highest = 0
    for py in 0 ..< height {
        let flippedY = CGFloat(height - 1 - py)
        let uvY = flippedY / heightPx
        for px in 0 ..< width {
            let uvX = CGFloat(px) / heightPx
            let mottle = walletCardFbm(uvX * 244.5, uvY * 129.0) - 0.5
            let grain = walletCardValueNoise(CGFloat(px) * 1.7, flippedY * 1.7) - 0.5
            let value = min(1.0, max(0.0, 0.5 + mottle * 0.06 + grain * 0.03))
            let step = Int((value * CGFloat(walletCardTextureSteps)).rounded())
            lowest = min(lowest, step)
            highest = max(highest, step)
            steps[py * width + px] = UInt16(step)
        }
    }
    return WalletCardTextureField(width: width, height: height, steps: steps, range: lowest ... max(lowest, highest))
}

func walletCardTextureImage(field: WalletCardTextureField, baseColor: NSColor, map: ((WalletRGB) -> WalletRGB)?) -> CGImage? {
    let base = baseColor.usingColorSpace(.deviceRGB) ?? baseColor
    let baseChannels: [CGFloat] = [base.redComponent, base.greenComponent, base.blueComponent]

    func overlayBlend(_ baseValue: CGFloat, _ blendValue: CGFloat) -> CGFloat {
        if baseValue < 0.5 {
            return 2.0 * baseValue * blendValue
        }
        return 1.0 - 2.0 * (1.0 - baseValue) * (1.0 - blendValue)
    }

    var table = [UInt32](repeating: 0, count: walletCardTextureSteps + 1)
    for step in field.range {
        let value = CGFloat(step) / CGFloat(walletCardTextureSteps)
        var color = WalletRGB(overlayBlend(baseChannels[0], value), overlayBlend(baseChannels[1], value), overlayBlend(baseChannels[2], value)).clamped()
        if let map {
            color = map(color).clamped()
        }
        table[step] = UInt32(UInt8(color.r * 255.0)) << 16 | UInt32(UInt8(color.g * 255.0)) << 8 | UInt32(UInt8(color.b * 255.0)) | 0xff000000
    }

    var pixels = [UInt32](repeating: 0, count: field.width * field.height)
    pixels.withUnsafeMutableBufferPointer { output in
        table.withUnsafeBufferPointer { table in
            field.steps.withUnsafeBufferPointer { steps in
                for index in 0 ..< steps.count {
                    output[index] = table[Int(steps[index])]
                }
            }
        }
    }
    return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
        guard let context = CGContext(data: bytes.baseAddress, width: field.width, height: field.height, bitsPerComponent: 8, bytesPerRow: field.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        return context.makeImage()
    }
}

private final class WalletCardTextureRequest {
    private let lock = NSLock()
    private var value: Int = 0
    
    func set(_ value: Int) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
    
    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class WalletCardTextureCache {
    static let shared = WalletCardTextureCache()
    
    let queue = DispatchQueue(label: "WalletCardTextureCache", qos: .userInitiated)
    private let images: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 8
        return cache
    }()
    
    func cached(_ key: String) -> CGImage? {
        return images.object(forKey: key as NSString)
    }
    
    func store(_ image: CGImage, key: String) {
        images.setObject(image, forKey: key as NSString)
    }

    private let fieldLock = NSLock()
    private var fields: [String: WalletCardTextureField] = [:]

    func field(_ key: String) -> WalletCardTextureField? {
        fieldLock.lock()
        defer { fieldLock.unlock() }
        return fields[key]
    }

    func store(_ field: WalletCardTextureField, key: String) {
        fieldLock.lock()
        fields = [key: field]
        fieldLock.unlock()
    }
}

public let walletCardStarPositions: [CGPoint] = [
    CGPoint(x: 14, y: 10), CGPoint(x: 70, y: 26), CGPoint(x: 126, y: 14), CGPoint(x: 188, y: 28), CGPoint(x: 248, y: 14),
    CGPoint(x: 22, y: 50), CGPoint(x: 120, y: 48), CGPoint(x: 212, y: 50), CGPoint(x: 262, y: 50), CGPoint(x: 222, y: 76),
    CGPoint(x: 56, y: 144), CGPoint(x: 110, y: 156), CGPoint(x: 156, y: 144), CGPoint(x: 188, y: 160), CGPoint(x: 156, y: 196), CGPoint(x: 188, y: 196)
]

public func walletCardStarHalfExtent(_ position: CGPoint) -> CGFloat {
    let seed = (position.x * 7.31 + position.y * 13.17).truncatingRemainder(dividingBy: 100.0) / 100.0
    return 3.0 + abs(seed)
}

public func walletCardSparklePath(halfExtent: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let waist = halfExtent * 0.18
    let outer: [CGPoint] = [
        CGPoint(x: 0, y: halfExtent), CGPoint(x: halfExtent, y: 0), CGPoint(x: 0, y: -halfExtent), CGPoint(x: -halfExtent, y: 0)
    ]
    let inner: [CGPoint] = [
        CGPoint(x: waist, y: waist), CGPoint(x: waist, y: -waist), CGPoint(x: -waist, y: -waist), CGPoint(x: -waist, y: waist)
    ]
    path.move(to: outer[0])
    for index in 0 ..< 4 {
        path.addLine(to: inner[index])
        path.addLine(to: outer[(index + 1) % 4])
    }
    path.closeSubpath()
    return path
}

private struct WalletCardEffectsGeometry: Equatable {
    public let bounds: CGRect
    public let unit: CGFloat
    public let backingScale: CGFloat
}


struct WalletCardSurfacePalette {
    let key: String
    let map: ((WalletRGB) -> WalletRGB)?

    static let stock = WalletCardSurfacePalette(key: "stock", map: nil)

    func color(_ color: CGColor) -> CGColor {
        guard let map else {
            return color
        }
        let components = color.components ?? [0, 0, 0, 1]
        let rgb = components.count >= 3 ? WalletRGB(components[0], components[1], components[2]) : WalletRGB(components[0], components[0], components[0])
        return map(rgb).cgColor
    }
}

private final class WalletCardSurfaceStack {
    let container = SimpleLayer()
    let textureLayer = SimpleLayer()
    let shineLayer = SimpleLayer()
    let shineMaskLayer = SimpleLayer()
    let palette: WalletCardSurfacePalette
    let shineColors: [CGColor]
    var appliedColorIndex: Int = -1
    var textureKey: String = ""
    var pendingTextureRenderKey: Int = 0
    let latestTextureRequest = WalletCardTextureRequest()

    init(palette: WalletCardSurfacePalette) {
        self.palette = palette
        self.shineColors = palette.map == nil ? walletCardShineColorLUT : walletCardShineColorLUT.map(palette.color)
        shineLayer.opacity = 0.75
        shineLayer.mask = shineMaskLayer
        shineMaskLayer.contentsGravity = .resize
        textureLayer.contentsGravity = .resize
        container.addSublayer(textureLayer)
        container.addSublayer(shineLayer)
    }
}

public final class WalletCardEffectsLayers {
    private var current: WalletCardSurfaceStack
    private var previous: WalletCardSurfaceStack?
    private let starsLayer = SimpleLayer()
    private let starsMaskLayer = SimpleLayer()
    private var starShapeLayers: [CAShapeLayer] = []
    private let rimShadowLayer = CAShapeLayer()
    private let waveMaskLayer = CAGradientLayer()
    private weak var host: CALayer?

    private var appliedTilt = WalletCardTilt(tx: .greatestFiniteMagnitude, ty: .greatestFiniteMagnitude)
    private var maskKey: WalletCardMaskCacheKey?
    private var maskImages: WalletCardMaskImages?
    private var geometry: WalletCardEffectsGeometry?
    private var unit: CGFloat = 1
    private var twinkleInstalled = true

    public init() {
        current = WalletCardSurfaceStack(palette: .stock)

        starsLayer.mask = starsMaskLayer
        starsMaskLayer.contentsGravity = .resize

        rimShadowLayer.fillRule = .evenOdd
        rimShadowLayer.fillColor = NSColor.black.cgColor
        rimShadowLayer.shadowColor = NSColor.black.cgColor
        rimShadowLayer.shadowOpacity = 0.16

        if #available(macOS 10.14, *) {
            waveMaskLayer.type = .radial
        }
        waveMaskLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        waveMaskLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        waveMaskLayer.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.black.withAlphaComponent(0).cgColor]

        for position in walletCardStarPositions {
            let star = CAShapeLayer()
            star.fillColor = NSColor.white.withAlphaComponent(0.4).cgColor
            star.path = walletCardSparklePath(halfExtent: walletCardStarHalfExtent(position))
            starShapeLayers.append(star)
            starsLayer.addSublayer(star)
        }
    }

    public func install(into container: CALayer) {
        host = container
        container.addSublayer(current.container)
        container.addSublayer(starsLayer)
        container.addSublayer(rimShadowLayer)
    }

    var paletteKey: String {
        return current.palette.key
    }

    func setPalette(_ palette: WalletCardSurfacePalette, animated: Bool) {
        guard palette.key != current.palette.key else {
            return
        }
        let stack = WalletCardSurfaceStack(palette: palette)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previous?.container.removeFromSuperlayer()
        if animated {
            previous = current
            host?.insertSublayer(stack.container, above: current.container)
        } else {
            previous = nil
            host?.insertSublayer(stack.container, above: current.container)
            current.container.removeFromSuperlayer()
        }
        current = stack
        if let geometry {
            layoutStack(stack, geometry: geometry)
        }
        let tilt = appliedTilt
        appliedTilt = WalletCardTilt(tx: .greatestFiniteMagnitude, ty: .greatestFiniteMagnitude)
        if tilt.tx != .greatestFiniteMagnitude {
            apply(tilt: tilt)
        }
        CATransaction.commit()
    }

    func updatePaletteTransition(origin: CGPoint, radius: CGFloat, progress: CGFloat, fade: Bool, receding: Bool = false) {
        guard previous != nil else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let canWave: Bool
        if #available(macOS 10.14, *) {
            canWave = true
        } else {
            canWave = false
        }
        if receding, let previous {
            host?.insertSublayer(previous.container, above: current.container)
            let outer = max(radius, 1)
            waveMaskLayer.frame = CGRect(x: origin.x - outer, y: origin.y - outer, width: outer * 2, height: outer * 2)
            waveMaskLayer.locations = [0, NSNumber(value: Double(max(0, (outer - 18) / outer))), 1]
            previous.container.mask = waveMaskLayer
            current.container.mask = nil
            current.container.opacity = 1
        } else if fade || !canWave {
            current.container.mask = nil
            current.container.opacity = Float(progress)
        } else {
            let outer = max(radius, 1)
            waveMaskLayer.frame = CGRect(x: origin.x - outer, y: origin.y - outer, width: outer * 2, height: outer * 2)
            let soft = max(0, (outer - 18) / outer)
            waveMaskLayer.locations = [0, NSNumber(value: Double(soft)), 1]
            current.container.opacity = 1
            current.container.mask = waveMaskLayer
        }
        CATransaction.commit()
    }

    func finishPaletteTransition() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previous?.container.removeFromSuperlayer()
        previous = nil
        current.container.mask = nil
        current.container.opacity = 1
        CATransaction.commit()
    }

    private var stacks: [WalletCardSurfaceStack] {
        if let previous {
            return [previous, current]
        }
        return [current]
    }

    private func layoutStack(_ stack: WalletCardSurfaceStack, geometry: WalletCardEffectsGeometry) {
        let bounds = geometry.bounds
        let shineSide = 349.5 * geometry.unit
        let shineSize = CGSize(width: shineSide, height: shineSide)
        stack.container.frame = bounds
        stack.textureLayer.frame = bounds
        stack.shineLayer.bounds = CGRect(origin: .zero, size: shineSize)
        stack.shineLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        stack.shineMaskLayer.frame = CGRect(origin: .zero, size: shineSize)
        stack.shineMaskLayer.contentsScale = geometry.backingScale
        if let maskImages {
            stack.shineMaskLayer.contents = maskImages.shine
        }
        renderTextureIfNeeded(stack, bounds: bounds, backingScale: geometry.backingScale)
    }

    public func layout(bounds: CGRect, unit: CGFloat, safeZones: [CGRect], backingScale: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        self.unit = unit
        let geometry = WalletCardEffectsGeometry(bounds: bounds, unit: unit, backingScale: backingScale)
        let geometryChanged = geometry != self.geometry
        if geometryChanged {
            self.geometry = geometry
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if geometryChanged {
            let shineSide = 349.5 * unit
            let shineSize = CGSize(width: shineSide, height: shineSide)

            starsLayer.frame = bounds
            starsMaskLayer.bounds = CGRect(origin: .zero, size: shineSize)
            starsMaskLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            starsMaskLayer.contentsScale = backingScale

            installMasksIfNeeded(shineSide: shineSide, backingScale: backingScale)

            for stack in stacks {
                layoutStack(stack, geometry: geometry)
            }

            let rimPath = CGMutablePath()
            rimPath.addRect(bounds.insetBy(dx: -8.0 * unit, dy: -8.0 * unit))
            rimPath.addRoundedRect(in: bounds, cornerWidth: 20.0 * unit, cornerHeight: 20.0 * unit)
            rimShadowLayer.frame = bounds
            rimShadowLayer.path = rimPath
            rimShadowLayer.shadowRadius = 1.0 * unit
            let shadowAngle = 212.0 * CGFloat.pi / 180.0
            rimShadowLayer.shadowOffset = CGSize(width: -sin(shadowAngle) * unit, height: -cos(shadowAngle) * unit)
        }

        let inset = -8.0 * unit
        var visibleOrdinal = 0
        for (index, position) in walletCardStarPositions.enumerated() {
            let star = starShapeLayers[index]
            let point = CGPoint(x: position.x * unit, y: bounds.height - position.y * unit)
            star.position = point
            let starScale = unit
            var isHidden = false
            for zone in safeZones {
                if zone.insetBy(dx: inset, dy: inset).contains(point) {
                    isHidden = true
                    break
                }
            }
            star.isHidden = isHidden
            star.transform = CATransform3DMakeScale(starScale, starScale, 1)
            if !isHidden {
                installTwinkle(star, ordinal: visibleOrdinal)
                visibleOrdinal += 1
            } else {
                star.removeAnimation(forKey: "twinkle")
            }
        }

        CATransaction.commit()

        if geometryChanged {
            appliedTilt = WalletCardTilt(tx: .greatestFiniteMagnitude, ty: .greatestFiniteMagnitude)
        }
    }

    private func installMasksIfNeeded(shineSide: CGFloat, backingScale: CGFloat) {
        let effectiveBackingScale = min(2.0, backingScale)
        let pixelSide = max(8, Int(ceil(shineSide * effectiveBackingScale)))
        let renderScale = CGFloat(pixelSide) / shineSide
        let key = WalletCardMaskCacheKey(
            pixelSide: pixelSide,
            backingScale: Int(round(effectiveBackingScale * 1000.0)),
            shineBlurRadius: Int(round(10.0 * unit * renderScale * 1000.0))
        )
        guard key != maskKey else {
            return
        }
        guard let images = WalletCardMaskRenderer.shared.images(diameter: shineSide, unit: unit, backingScale: backingScale) else {
            return
        }
        maskImages = images
        for stack in stacks {
            stack.shineMaskLayer.contents = images.shine
        }
        starsMaskLayer.contents = images.stars
        maskKey = key
    }

    private func renderTextureIfNeeded(_ stack: WalletCardSurfaceStack, bounds: CGRect, backingScale: CGFloat) {
        let key = "\(Int(bounds.width))x\(Int(bounds.height))@\(backingScale)"
        guard key != stack.textureKey else {
            return
        }
        stack.textureKey = key
        stack.pendingTextureRenderKey += 1
        let renderKey = stack.pendingTextureRenderKey
        let textureSize = bounds.size
        let palette = stack.palette

        let cache = WalletCardTextureCache.shared
        let renderScale = min(2.0, backingScale)
        let fieldKey = "\(max(1, Int(ceil(textureSize.width * renderScale))))x\(max(1, Int(ceil(textureSize.height * renderScale))))"
        let cacheKey = "\(fieldKey)_\(palette.key)"
        let latestTextureRequest = stack.latestTextureRequest
        latestTextureRequest.set(renderKey)
        var texture = cache.cached(cacheKey)
        if texture == nil, let field = cache.field(fieldKey), let colored = walletCardTextureImage(field: field, baseColor: NSColor(rgb: 0x0088ff), map: palette.map) {
            cache.store(colored, key: cacheKey)
            texture = colored
        }
        if let texture {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stack.textureLayer.contents = texture
            CATransaction.commit()
            return
        }

        cache.queue.async { [weak stack] in
            let texture: CGImage?
            if let cached = cache.cached(cacheKey) {
                texture = cached
            } else if latestTextureRequest.get() != renderKey {
                return
            } else {
                let field = cache.field(fieldKey) ?? walletCardTextureField(size: textureSize, backingScale: backingScale)
                cache.store(field, key: fieldKey)
                texture = walletCardTextureImage(field: field, baseColor: NSColor(rgb: 0x0088ff), map: palette.map)
                if let texture {
                    cache.store(texture, key: cacheKey)
                }
            }
            DispatchQueue.main.async {
                guard let stack, stack.pendingTextureRenderKey == renderKey else {
                    return
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                stack.textureLayer.contents = texture
                CATransaction.commit()
            }
        }
    }

    private func installTwinkle(_ star: CAShapeLayer, ordinal: Int) {
        guard twinkleInstalled else {
            return
        }
        if star.animation(forKey: "twinkle") != nil {
            return
        }
        let n = CGFloat(ordinal)
        let rawDuration = 4.2 + (n * 0.41).truncatingRemainder(dividingBy: 1.0) * 2.6
        let duration = rawDuration * 0.5
        let delay = (n * 0.73).truncatingRemainder(dividingBy: duration)
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.92 * unit
        animation.toValue = 1.08 * unit
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.beginTime = CACurrentMediaTime() - Double(delay)
        star.add(animation, forKey: "twinkle")
    }

    public func setTwinkleEnabled(_ enabled: Bool) {
        twinkleInstalled = enabled
        if !enabled {
            for star in starShapeLayers {
                star.removeAnimation(forKey: "twinkle")
            }
        }
    }

    public func apply(tilt: WalletCardTilt) {
        guard tilt != appliedTilt else {
            return
        }
        appliedTilt = tilt

        let colorIndex = Int(round((tilt.ty + 1.0) * CGFloat(walletCardEffectSteps) / 2.0))
        let clampedColorIndex = max(0, min(walletCardEffectSteps, colorIndex))

        let angle = (-58.0 + tilt.tx * 60.0) * .pi / 180.0
        let shineTransform = CATransform3DConcat(CATransform3DMakeRotation(angle, 0, 0, 1), CATransform3DMakeScale(1, 1.65, 1))

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for stack in stacks {
            stack.shineLayer.transform = shineTransform
            if clampedColorIndex != stack.appliedColorIndex {
                stack.shineLayer.backgroundColor = stack.shineColors[clampedColorIndex]
                stack.appliedColorIndex = clampedColorIndex
            }
        }

        starsMaskLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)

        CATransaction.commit()
    }
}
