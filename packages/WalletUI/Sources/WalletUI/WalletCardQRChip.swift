import Cocoa

private let walletCardQRChipReferenceOrigin = CGPoint(x: 268.5, y: 82.0)
let walletCardQRChipReferenceSize = CGSize(width: 50.0, height: 38.0)
let walletCardQRChipMargin: CGFloat = 2.0

struct WalletCardChipTexture {
    let width: Int
    let height: Int
    let values: [Float]

    func sample(_ u: Float, _ v: Float, wraps: Bool) -> Float {
        let x = u * Float(width) - 0.5
        let y = v * Float(height) - 0.5
        let x0 = x.rounded(.down)
        let y0 = y.rounded(.down)
        let fx = x - x0
        let fy = y - y0
        func index(_ value: Int, _ count: Int) -> Int {
            if wraps {
                return ((value % count) + count) % count
            }
            return max(0, min(count - 1, value))
        }
        let left = index(Int(x0), width)
        let right = index(Int(x0) + 1, width)
        let top = index(Int(y0), height) * width
        let bottom = index(Int(y0) + 1, height) * width
        let upper = values[top + left] + (values[top + right] - values[top + left]) * fx
        let lower = values[bottom + left] + (values[bottom + right] - values[bottom + left]) * fx
        return upper + (lower - upper) * fy
    }
}

let walletCardChipNoise: WalletCardChipTexture = {
    let dimension = 256
    var seed: UInt64 = 0x2545_F491_4F6C_DD1D
    func random() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return Float(seed & 0xffff) / Float(0xffff)
    }
    let base = (0 ..< dimension * dimension).map { _ in random() }
    let radius = 9
    var values = [Float](repeating: 0, count: dimension * dimension)
    for y in 0 ..< dimension {
        let row = y * dimension
        var accumulator: Float = 0
        for offset in -radius ... radius {
            accumulator += base[row + (offset + dimension) % dimension]
        }
        for x in 0 ..< dimension {
            if x > 0 {
                accumulator += base[row + (x + radius) % dimension] - base[row + (x - radius - 1 + dimension) % dimension]
            }
            var value = accumulator / Float(2 * radius + 1)
            value = 0.5 + (value - 0.5) * 3.4
            let combined = 0.68 * value + 0.32 * random()
            values[row + x] = Float(UInt8(max(0.0, min(255.0, combined * 255.0)))) / 255.0
        }
    }
    return WalletCardChipTexture(width: dimension, height: dimension, values: values)
}()

let walletCardChipGlyph: WalletCardChipTexture = {
    let side = 176
    var pixels = [UInt8](repeating: 0, count: side * side)
    pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return
        }
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 8.0, y: -8.0)
        context.translateBy(x: -282.5, y: -90.0)
        context.setFillColor(gray: 1.0, alpha: 1.0)
        for origin in [CGPoint(x: 284.25, y: 91.75), CGPoint(x: 294.5, y: 91.75), CGPoint(x: 284.25, y: 102.0)] {
            let outer = CGRect(origin: origin, size: CGSize(width: 8.25, height: 8.25))
            let inner = outer.insetBy(dx: 1.375, dy: 1.375)
            let path = CGMutablePath()
            path.addRoundedRect(in: outer, cornerWidth: 2.4, cornerHeight: 2.4)
            path.addRoundedRect(in: inner, cornerWidth: 1.1, cornerHeight: 1.1)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        }
        for origin in [CGPoint(x: 295.0, y: 103.0), CGPoint(x: 300.12, y: 103.0), CGPoint(x: 297.6, y: 105.3), CGPoint(x: 295.0, y: 108.15), CGPoint(x: 300.12, y: 108.15)] {
            let dot = CGRect(origin: origin, size: CGSize(width: 2.12, height: 2.1))
            context.addPath(CGPath(roundedRect: dot, cornerWidth: 0.45, cornerHeight: 0.45, transform: nil))
            context.fillPath()
        }
    }
    return WalletCardChipTexture(width: side, height: side, values: pixels.map { Float($0) / 255.0 })
}()

private func walletCardChipSmoothStep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    let t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)
}

private func walletCardChipRoundRect(_ x: Float, _ y: Float, _ halfWidth: Float, _ halfHeight: Float, _ radius: Float) -> Float {
    let qx = abs(x) - (halfWidth - radius)
    let qy = abs(y) - (halfHeight - radius)
    return (max(qx, 0.0) * max(qx, 0.0) + max(qy, 0.0) * max(qy, 0.0)).squareRoot() + min(max(qx, qy), 0.0) - radius
}

func walletCardRoundRectNormal(_ point: CGPoint, _ halfSize: CGSize, _ radius: CGFloat) -> CGPoint {
    let qx = abs(point.x) - (halfSize.width - radius)
    let qy = abs(point.y) - (halfSize.height - radius)
    var normal: CGPoint
    if qx > 0.0 && qy > 0.0 {
        let length = hypot(qx, qy)
        normal = CGPoint(x: qx / length, y: qy / length)
    } else {
        normal = qx > qy ? CGPoint(x: 1.0, y: 0.0) : CGPoint(x: 0.0, y: 1.0)
    }
    return CGPoint(x: point.x < 0.0 ? -normal.x : normal.x, y: point.y < 0.0 ? -normal.y : normal.y)
}

private struct WalletCardQRChipPixel {
    var offset: Int
    var skyCoordinate: Float
    var across: Float
    var grain: Float
    var fresnel: Float
    var chamfer: Float
    var normalX: Float
    var normalY: Float
    var lip: Float
    var ink: Float
    var inkRed: Float
    var inkGreen: Float
    var inkBlue: Float
    var ringMask: Float
    var cover: Float
    var socket: Float
}

final class WalletCardQRChipRenderer {
    let width: Int
    let height: Int
    private let chipPixels: [WalletCardQRChipPixel]
    private var buffer: [UInt8]
    var ringColor: (Float, Float, Float) = (0.047, 0.451, 0.835)
    var metalTint: (Float, Float, Float, Float) = (0, 0, 0, 0)

    init?(chipSize: NSSize, backingScale: CGFloat) {
        let chipScaleX = Float(chipSize.width / walletCardQRChipReferenceSize.width)
        let chipScaleY = Float(chipSize.height / walletCardQRChipReferenceSize.height)
        guard chipScaleX > 0.0, chipScaleY > 0.0, backingScale > 0.0 else {
            return nil
        }
        let scale = Float(backingScale)
        let margin = Float(walletCardQRChipMargin)
        let width = max(1, Int(((Float(chipSize.width) + margin * chipScaleX * 2.0) * scale).rounded(.up)))
        let height = max(1, Int(((Float(chipSize.height) + margin * chipScaleY * 2.0) * scale).rounded(.up)))
        self.width = width
        self.height = height
        self.buffer = [UInt8](repeating: 0, count: width * height * 4)

        let halfWidth: Float = 25.0
        let halfHeight: Float = 19.0
        let radius: Float = 9.0
        let acrossLength = Float(hypot(1.0, 0.45))
        let baseInk: (Float, Float, Float) = (0.459, 0.486, 0.514)
        var pixels: [WalletCardQRChipPixel] = []
        pixels.reserveCapacity(width * height)
        for py in 0 ..< height {
            let y = (Float(py) + 0.5) / scale - margin * chipScaleY
            let cpY = y / chipScaleY + Float(walletCardQRChipReferenceOrigin.y)
            for px in 0 ..< width {
                let x = (Float(px) + 0.5) / scale - margin * chipScaleX
                let cpX = x / chipScaleX + Float(walletCardQRChipReferenceOrigin.x)
                let localX = cpX - 293.5
                let localY = cpY - 101.0
                let d = walletCardChipRoundRect(localX, localY, halfWidth, halfHeight, radius)
                guard d < 2.0 else {
                    continue
                }
                let gradient = walletCardRoundRectNormal(CGPoint(x: CGFloat(localX), y: CGFloat(localY)), CGSize(width: CGFloat(halfWidth), height: CGFloat(halfHeight)), CGFloat(radius))
                let aa = max(0.6 * (abs(Float(gradient.x)) / (chipScaleX * scale) + abs(Float(gradient.y)) / (chipScaleY * scale)), 0.001)
                let socket = (1.0 - walletCardChipSmoothStep(0.0, 1.2, d)) * (d >= 0.0 ? 1.0 : 0.0) * 0.10

                let qx = localX / halfWidth
                let qy = localY / halfHeight
                let brush = walletCardChipNoise.sample(cpX * 0.012, cpY * 1.4, wraps: true)
                let brushFine = walletCardChipNoise.sample(cpX * 0.03, cpY * 3.1, wraps: true)
                let grain = (brush - 0.5) * 0.020 + (brushFine - 0.5) * 0.014

                let inner = walletCardChipRoundRect(localX, localY, halfWidth - 1.0, halfHeight - 1.0, radius - 1.0)
                let normal = walletCardRoundRectNormal(CGPoint(x: CGFloat(localX), y: CGFloat(localY)), CGSize(width: CGFloat(halfWidth - 1.0), height: CGFloat(halfHeight - 1.0)), CGFloat(radius - 1.0))

                let qrU = (cpX - 282.5) / 22.0
                let qrV = (cpY - 90.0) / 22.0
                let ink = walletCardChipGlyph.sample(qrU, qrV, wraps: false)
                let lip = walletCardChipGlyph.sample(qrU, qrV - 1.0 / 22.0, wraps: false)
                let upper = walletCardChipGlyph.sample(qrU, qrV + 0.55 / 22.0, wraps: false)

                pixels.append(WalletCardQRChipPixel(
                    offset: (py * width + px) * 4,
                    skyCoordinate: qy + 0.18 * qx,
                    across: (qx - 0.45 * qy) / acrossLength,
                    grain: grain,
                    fresnel: walletCardChipSmoothStep(-5.0, 0.0, inner) * 0.18,
                    chamfer: walletCardChipSmoothStep(-1.3, -0.1, inner) * 0.12,
                    normalX: Float(normal.x),
                    normalY: Float(normal.y),
                    lip: lip * (1.0 - ink),
                    ink: ink,
                    inkRed: baseInk.0 * 0.80 + baseInk.0 * 0.20 * upper,
                    inkGreen: baseInk.1 * 0.80 + baseInk.1 * 0.20 * upper,
                    inkBlue: baseInk.2 * 0.80 + baseInk.2 * 0.20 * upper,
                    ringMask: walletCardChipSmoothStep(-1.0 - aa, -1.0 + aa, d),
                    cover: 1.0 - walletCardChipSmoothStep(-aa, aa, d),
                    socket: socket
                ))
            }
        }
        self.chipPixels = pixels
    }

    func image(surface: CGPoint, time: CGFloat) -> CGImage? {
        let surfaceX = Float(max(-1.0, min(1.0, surface.x)))
        let surfaceY = Float(max(-1.0, min(1.0, surface.y)))
        let horizon = 0.10 + 0.55 * surfaceY - 0.18 * surfaceX
        let skyLow = horizon - 0.55
        let skyRange: Float = 1.40
        let slide = 0.10 + 0.95 * surfaceX - 0.55 * surfaceY + 0.12 * Float(sin(Double(time) * 0.45))
        let lightX = -0.55 - 0.7 * surfaceX
        let lightY = -0.85 + 0.6 * surfaceY
        let lightLength = (lightX * lightX + lightY * lightY).squareRoot()
        let lx = lightX / lightLength
        let ly = lightY / lightLength
        let ring = ringColor
        let tint = metalTint
        let tintLuma = 0.2126 * tint.0 + 0.7152 * tint.1 + 0.0722 * tint.2
        let tintTarget = (tint.0 - tintLuma, tint.1 - tintLuma, tint.2 - tintLuma)
        let tintLength = (tintTarget.0 * tintTarget.0 + tintTarget.1 * tintTarget.1 + tintTarget.2 * tintTarget.2).squareRoot()
        let tintAmount: Float = tintLength > 1e-4 ? tint.3 : 0
        let tintDirection = tintLength > 1e-4 ? (tintTarget.0 / tintLength, tintTarget.1 / tintLength, tintTarget.2 / tintLength) : (0, 0, 0)

        chipPixels.withUnsafeBufferPointer { pixels in
            buffer.withUnsafeMutableBufferPointer { output in
                for pixel in pixels {
                    let skyT = max(0.0, min(1.0, (pixel.skyCoordinate - skyLow) / skyRange))
                    let sky = 1.0 - skyT * skyT * (3.0 - 2.0 * skyT)
                    let grainScale = 1.0 + pixel.grain
                    var red = (0.66 + 0.295 * sky) * grainScale
                    var green = (0.78 + 0.195 * sky) * grainScale
                    var blue = (0.93 + 0.07 * sky) * grainScale

                    let t = pixel.across - slide
                    let t2 = t * t
                    let soft = expf(-t2 / 0.3025)
                    let sharp = expf(-t2 / 0.01)
                    let sheen = soft * 0.22 + sharp * (0.30 + pixel.grain * 6.0)
                    red += (1.0 - red) * sheen
                    green += (1.0 - green) * sheen
                    blue += (1.0 - blue) * sheen

                    red += (0.98 - red) * pixel.fresnel
                    green += (0.99 - green) * pixel.fresnel
                    blue += (1.0 - blue) * pixel.fresnel
                    let lightDot = pixel.normalX * lx + pixel.normalY * ly
                    let chamfer = pixel.chamfer * lightDot
                    red -= chamfer
                    green -= chamfer
                    blue -= chamfer
                    if tintAmount > 0 {
                        let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                        let strength = ((red - luma) * (red - luma) + (green - luma) * (green - luma) + (blue - luma) * (blue - luma)).squareRoot()
                        red += (max(0.0, min(1.0, luma + tintDirection.0 * strength)) - red) * tintAmount
                        green += (max(0.0, min(1.0, luma + tintDirection.1 * strength)) - green) * tintAmount
                        blue += (max(0.0, min(1.0, luma + tintDirection.2 * strength)) - blue) * tintAmount
                    }

                    red += (0.90 - red) * pixel.lip
                    green += (0.93 - green) * pixel.lip
                    blue += (0.96 - blue) * pixel.lip
                    red += (pixel.inkRed - red) * pixel.ink
                    green += (pixel.inkGreen - green) * pixel.ink
                    blue += (pixel.inkBlue - blue) * pixel.ink

                    red = max(0.0, min(1.0, red))
                    green = max(0.0, min(1.0, green))
                    blue = max(0.0, min(1.0, blue))
                    let ringShade = 0.92 + 0.16 * lightDot
                    red += (ring.0 * ringShade - red) * pixel.ringMask
                    green += (ring.1 * ringShade - green) * pixel.ringMask
                    blue += (ring.2 * ringShade - blue) * pixel.ringMask

                    let cover = pixel.cover
                    let alpha = cover + pixel.socket * (1.0 - cover)
                    output[pixel.offset] = UInt8(max(0.0, min(255.0, (red * cover * 255.0).rounded())))
                    output[pixel.offset + 1] = UInt8(max(0.0, min(255.0, (green * cover * 255.0).rounded())))
                    output[pixel.offset + 2] = UInt8(max(0.0, min(255.0, (blue * cover * 255.0).rounded())))
                    output[pixel.offset + 3] = UInt8(max(0.0, min(255.0, (alpha * 255.0).rounded())))
                }
            }
        }

        let bytesPerRow = width * 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return buffer.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                return nil
            }
            return context.makeImage()
        }
    }
}
