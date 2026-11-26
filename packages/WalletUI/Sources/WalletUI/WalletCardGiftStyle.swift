import Cocoa
import WalletContext

struct WalletRGB: Equatable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255)
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        self.init(srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }

    var color: NSColor {
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    var cgColor: CGColor {
        return color.cgColor
    }

    func mix(_ other: WalletRGB, _ t: CGFloat) -> WalletRGB {
        return WalletRGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    func clamped() -> WalletRGB {
        return WalletRGB(min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }
}

private func walletSrgbToLinear(_ v: CGFloat) -> CGFloat {
    let c = min(max(v, 0), 1)
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

private func walletLinearToSrgb(_ v: CGFloat) -> CGFloat {
    let y = min(max(v, 0), 1)
    return y <= 0.0031308 ? 12.92 * y : 1.055 * pow(y, 1 / 2.4) - 0.055
}

struct WalletOklch {
    var l: CGFloat
    var c: CGFloat
    var h: CGFloat

    init(l: CGFloat, c: CGFloat, h: CGFloat) {
        self.l = l
        self.c = c
        self.h = h
    }

    init(_ rgb: WalletRGB) {
        let lr = walletSrgbToLinear(rgb.r), lg = walletSrgbToLinear(rgb.g), lb = walletSrgbToLinear(rgb.b)
        let l1 = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m1 = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s1 = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        let L = 0.2104542553 * l1 + 0.7936177850 * m1 - 0.0040720468 * s1
        let A = 1.9779984951 * l1 - 2.4285922050 * m1 + 0.4505937099 * s1
        let B = 0.0259040371 * l1 + 0.7827717662 * m1 - 0.8086757660 * s1
        self.init(l: L, c: hypot(A, B), h: atan2(B, A))
    }

    init(hex: UInt32) {
        self.init(WalletRGB(hex: hex))
    }

    fileprivate static func linear(l: CGFloat, c: CGFloat, h: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let a = c * cos(h), b = c * sin(h)
        let l1 = l + 0.3963377774 * a + 0.2158037573 * b
        let m1 = l - 0.1055613458 * a - 0.0638541728 * b
        let s1 = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l1 * l1 * l1, m3 = m1 * m1 * m1, s3 = s1 * s1 * s1
        return (4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
                -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
                -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
    }

    var rgb: WalletRGB {
        var cc = c
        var v = WalletOklch.linear(l: l, c: cc, h: h)
        func outside(_ x: CGFloat) -> Bool { x < -0.001 || x > 1.001 }
        var tries = 0
        while outside(v.0) || outside(v.1) || outside(v.2), tries < 40 {
            cc *= 0.95
            v = WalletOklch.linear(l: l, c: cc, h: h)
            tries += 1
        }
        return WalletRGB(walletLinearToSrgb(v.0), walletLinearToSrgb(v.1), walletLinearToSrgb(v.2))
    }

    var color: NSColor {
        return rgb.color
    }
}

@available(macOS 10.15, *)
struct WalletCardTint: Equatable {
    let outerColor: UInt32
    let hue: CGFloat
    let chroma: CGFloat
    let cap: CGFloat
    let darkness: CGFloat
    let edgeL: CGFloat
    let centerL: CGFloat
    let darkC: CGFloat
    let lShift: CGFloat

    static let stockDark = WalletOklch(hex: 0x088FEE)
    static let stockLight = WalletOklch(hex: 0x16ABF9)
    static let stockAccent = WalletOklch(hex: 0x6DDCFF)
    static let stockAddress = WalletOklch(hex: 0x2A83E2)
    static let materialCalibration = WalletRGB(1.05933, 0.912212, 0.968627)

    init(_ style: WalletContext.CardGiftStyle) {
        let centerRGB = UInt32(bitPattern: style.innerColor) & 0xffffff
        let edgeRGB = UInt32(bitPattern: style.outerColor) & 0xffffff
        let center = WalletOklch(hex: centerRGB), edge = WalletOklch(hex: edgeRGB)
        let mid = WalletOklch(WalletRGB(hex: centerRGB).mix(WalletRGB(hex: edgeRGB), 0.5))
        outerColor = edgeRGB
        hue = mid.h
        let hueDeg = (mid.h * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let violet = exp(-pow((hueDeg - 300) / 38, 2))
        chroma = min(max(mid.c * 1.5 / 0.155, 0.15), 1) * (1 + 0.18 * violet)
        lShift = -0.025 * violet
        darkness = min(max((0.6 - (center.l + edge.l) / 2) / 0.15, 0), 1)
        cap = center.c * 1.2
        darkC = center.c * 1.1
        edgeL = edge.l
        centerL = center.l
    }

    func tint(_ ref: WalletOklch) -> WalletOklch {
        let dl = Self.stockDark.l, ll = Self.stockLight.l
        let pos = min(max((ref.l - dl) / (ll - dl), -2), 3)
        let own = edgeL - 0.02 + pos * (centerL - edgeL)
        let l = ref.l + (own - ref.l) * darkness + lShift
        let c = min(ref.c * chroma, cap * ref.c / 0.173) * (1 - darkness) + darkC * darkness
        return WalletOklch(l: min(max(l, 0.05), 0.97), c: c, h: hue)
    }

    func surface(_ rgb: WalletRGB, material: Bool) -> WalletRGB {
        let input = material ? WalletRGB(rgb.r * Self.materialCalibration.r, rgb.g * Self.materialCalibration.g, rgb.b * Self.materialCalibration.b).clamped() : rgb.clamped()
        let tinted = tint(WalletOklch(input))
        var c = tinted.c
        var lin = WalletOklch.linear(l: tinted.l, c: c, h: tinted.h)
        var tries = 0
        while ([lin.0, lin.1, lin.2].contains { $0 < -0.001 || $0 > 1.001 }), tries < 12 {
            c *= 0.85
            lin = WalletOklch.linear(l: tinted.l, c: c, h: tinted.h)
            tries += 1
        }
        return WalletRGB(walletLinearToSrgb(lin.0), walletLinearToSrgb(lin.1), walletLinearToSrgb(lin.2))
    }

    var surface: WalletOklch {
        return WalletOklch(tint(Self.stockDark).rgb)
    }

    var accent: NSColor {
        let o = tint(Self.stockAccent)
        return o.l >= 0.8 ? o.color : WalletOklch(l: 0.8, c: o.c, h: o.h).color
    }

    var address: NSColor {
        let s = surface.l
        if s < 0.5 {
            let a = WalletOklch(WalletRGB(accent))
            return WalletOklch(l: a.l * 0.8, c: a.c, h: a.h).color
        }
        return WalletOklch(l: s - 0.22, c: Self.stockAddress.c * chroma * 1.1, h: hue).color
    }

    var darkCard: Bool {
        return WalletOklch(hex: outerColor).l < 0.2
    }
}

enum WalletGiftPattern {
    struct Item {
        var center: CGPoint
        var size: CGFloat
    }

    static let alpha: CGFloat = 0.18

    static func items(size: CGSize, maxX: CGFloat = .greatestFiniteMagnitude) -> [Item] {
        let k = size.width / 370
        let columnPitch = 84 * k, rowPitch = 25 * k, itemSize = floor(20 * k)
        guard rowPitch > 0 else { return [] }
        let center = CGPoint(x: size.width / 2 + 4 * k, y: size.height / 2)
        let rows = Int(ceil(size.height / 2 / rowPitch)) + 1
        let columns = Int(ceil(size.width / 2 / columnPitch)) + 1
        var list: [Item] = []
        for row in -rows...rows {
            let shift: CGFloat = row % 2 == 0 ? 0 : columnPitch / 2
            for column in -columns...columns {
                let point = CGPoint(x: center.x + CGFloat(column) * columnPitch + shift, y: center.y + CGFloat(row) * rowPitch)
                if point.x < -itemSize || point.x > min(size.width + itemSize, maxX) || point.y < -itemSize || point.y > size.height + itemSize {
                    continue
                }
                list.append(Item(center: point, size: itemSize))
            }
        }
        return list
    }

    static func tinted(_ symbol: CGImage, color: Int32) -> CGImage? {
        let width = symbol.width, height = symbol.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(symbol, in: rect)
        context.setBlendMode(.sourceIn)
        context.setFillColor(WalletRGB(hex: UInt32(bitPattern: color) & 0xffffff).cgColor)
        context.fill(rect)
        return context.makeImage()
    }
}

struct WalletCardStyleTransition {
    let progress: CGFloat
    let textMix: CGFloat
    let patternTime: CGFloat
    let contraction: CGFloat
    let removing: Bool

    init(fraction: Double, removing: Bool) {
        let x = CGFloat(min(1, max(0, fraction)))
        self.removing = removing
        let pull = x * x * (2.25 * x - 1.25)
        self.progress = removing ? max(0, pull) : 1 - pow(1 - x, 4)
        self.contraction = removing ? 1 - pull : 1
        let text = min(1, max(0, (self.progress - 0.25) / 0.45))
        self.textMix = text * text * (3 - 2 * text)
        self.patternTime = removing ? 1 : min(1, x * 1.05 / 0.45)
    }

    func radius(origin: CGPoint, size: CGSize) -> CGFloat {
        return hypot(max(origin.x, size.width - origin.x), max(origin.y, size.height - origin.y)) * 1.05 * (removing ? min(1, max(0, contraction)) : progress)
    }
}

@available(macOS 10.15, *)
func walletCardStyleKey(_ style: WalletContext.CardGiftStyle?) -> String {
    guard let style else {
        return "stock"
    }
    return "\(style.innerColor)_\(style.outerColor)"
}
