import Cocoa
import CoreText
import TGUIKit

public enum WalletTransferArrivalAnimation {
    public static let climax = passTime(122.0)
    public static let landing = climax - 0.08
    public static let duration = landing + 1.8

    static func passTime(_ x: CGFloat) -> Double {
        let e = min(1.0, max(0.0, (Double(x) + 30.0) / 320.0))
        return 0.05 + 1.1 * (0.5 - sin(asin(1.0 - 2.0 * e) / 3.0))
    }

    static func sheenX(_ time: Double) -> CGFloat? {
        let u = (time - 0.05) / 1.1
        guard u >= 0.0, u <= 1.0 else {
            return nil
        }
        return CGFloat(-30.0 + 320.0 * u * u * (3.0 - 2.0 * u))
    }

    static func crossing(_ point: CGPoint) -> CGFloat {
        return point.x + 4.0 + 0.35 * (point.y + 4.0) - 13.7
    }

    static func lift(_ time: Double, at x: CGFloat) -> CGFloat {
        let t = time - passTime(x)
        guard t > 0.0, t < 0.8 else {
            return 0.0
        }
        return CGFloat(sin(2.0 * .pi * 1.7 * t) * exp(-t / 0.2))
    }

    struct DigitStroke: Equatable {
        let digit: Int
        let offset: CGFloat
        let alpha: CGFloat
    }

    static func rolledDigit(value: Int, column: Int, pitch: CGFloat, landing: Double, time: Double, integralCount: Int) -> [DigitStroke]? {
        func progress(_ back: Double) -> Double {
            return min(1.0, max(0.0, (time - back - 0.02) / max(landing - 0.02, 0.05)))
        }
        guard progress(0) < 0.999 else {
            return nil
        }
        let distance = Double(value + 10 * min(column, 2))
        func position(_ back: Double) -> Double {
            return distance * (1.0 - pow(1.0 - progress(back), 1.7))
        }
        let now = position(0.0)
        let was = position(1.0 / 60.0)
        let travel = CGFloat(abs(now - was)) * pitch
        let samples = travel > 1.0 ? min(2 + Int(travel), 14) : 1
        let weights = (0 ..< samples).map { index -> CGFloat in
            guard samples > 1 else {
                return 1.0
            }
            let q = CGFloat(index) / CGFloat(samples - 1) * 2.0 - 1.0
            return 1.0 - 0.55 * q * q
        }
        let total = weights.reduce(0, +)
        let low = Int(floor(min(now, was))) - 1
        let high = Int(ceil(max(now, was))) + 1
        var strokes: [DigitStroke] = []
        for n in low ... high {
            let digit = ((n % 10) + 10) % 10
            if digit == 0 && column == 0 && integralCount > 1 && value != 0 {
                continue
            }
            for sample in 0 ..< samples {
                let q = samples > 1 ? Double(sample) / Double(samples - 1) : 1.0
                let dy = CGFloat(was + (now - was) * q - Double(n)) * pitch
                let edge = abs(dy) / (pitch * 0.58)
                let alpha = (edge >= 1 ? 0 : 1 - pow(edge, 2.2)) * weights[sample] / total
                guard alpha > 0.006 else {
                    continue
                }
                strokes.append(DigitStroke(digit: digit, offset: dy, alpha: alpha))
            }
        }
        return strokes
    }

    static func glyphLift(isAmount: Bool, at x: CGFloat, time: Double) -> (scale: CGFloat, offset: CGFloat) {
        let lift = self.lift(time, at: x)
        return (1.0 + (isAmount ? 0.1 : 0.08) * lift, (isAmount ? 1.2 : 0.9) * lift)
    }

    static func textSheen(x: CGFloat) -> (start: CGPoint, end: CGPoint) {
        return (CGPoint(x: x - 112 - 4, y: -4), CGPoint(x: x + 112 - 4, y: 112 * 0.7 - 4))
    }

    static func cardSheenBand(x: CGFloat, width: CGFloat, size: CGSize) -> (start: CGPoint, end: CGPoint) {
        return (CGPoint(x: (x - width - 4) / size.width, y: -4 / size.height), CGPoint(x: (x + width - 4) / size.width, y: (width * 0.7 - 4) / size.height))
    }
}

final class WalletChatCardArrivalTextView: View {
    private struct GlyphKey: Hashable {
        let font: String
        let size: CGFloat
        let glyph: CGGlyph
    }
    private struct Shape {
        let path: CGPath
        let advance: CGFloat
        let image: CGImage?
    }
    private struct Glyph {
        let path: CGPath
        let origin: CGPoint
        let color: CGColor
        let kind: Int
        let landing: CGFloat
        let value: Int?
        let column: Int
        let pitch: CGFloat
        let advance: CGFloat
        let digits: [Shape]
        let image: CGImage?
    }
    private static var shapes: [GlyphKey: Shape] = [:]
    private var glyphs: [Glyph] = []
    private var layouts: [(TextViewLayout, NSRect)] = []
    private var integralCount = 0
    private var time: Double = 0.0
    private let addressGradient: CGGradient
    private let nameGradient: CGGradient

    required init(frame frameRect: NSRect) {
        func gradient(color: NSColor, peak: CGFloat) -> CGGradient {
            let alphas: [CGFloat] = [0.0, 0.18, 0.6, 1.0, 0.6, 0.18, 0.0]
            let colors = alphas.map { color.withAlphaComponent($0 * peak).cgColor }
            let locations: [CGFloat] = [0.0, 0.22, 0.4, 0.5, 0.6, 0.78, 1.0]
            return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
        }
        self.addressGradient = gradient(color: NSColor(red: 0.36, green: 0.86, blue: 1.0, alpha: 1.0), peak: 0.9)
        self.nameGradient = gradient(color: .white, peak: 0.25)
        super.init(frame: frameRect)
        self.isEventLess = true
        self.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func shape(font: CTFont, glyph: CGGlyph) -> Shape {
        let key = GlyphKey(font: CTFontCopyPostScriptName(font) as String, size: CTFontGetSize(font), glyph: glyph)
        if let cached = self.shapes[key] {
            return cached
        }
        var glyph = glyph
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let path: CGPath
        var image: CGImage?
        if let outline = CTFontCreatePathForGlyph(font, glyph, nil) {
            path = outline
        } else {
            let bounds = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, nil, 1).integral
            if !bounds.isEmpty && !bounds.isInfinite && !bounds.isNull {
                image = generateImage(bounds.size, rotatedContext: { size, context in
                    context.clear(CGRect(origin: .zero, size: size))
                    context.translateBy(x: -bounds.minX, y: bounds.maxY)
                    context.scaleBy(x: 1, y: -1)
                    var position = CGPoint.zero
                    CTFontDrawGlyphs(font, &glyph, &position, 1, context)
                })
                path = CGPath(rect: bounds, transform: nil)
            } else {
                path = CGMutablePath()
            }
        }
        let result = Shape(path: path, advance: advance.width, image: image)
        self.shapes[key] = result
        return result
    }

    private static func enumerateLines(_ view: TextView, _ body: (TextViewLayout, CTLine, CGPoint) -> Void) {
        guard let layout = view.textLayout else {
            return
        }
        let size = view.frame.size
        let start = NSMakePoint(round((size.width - layout.layoutSize.width) / 2), round((size.height - layout.layoutSize.height) / 2))
        for line in layout.lines {
            var penOffset = CGFloat(CTLineGetPenOffsetForFlush(line.line, line.penFlush, Double(size.width)))
            if layout.penFlush == 0.5, line.penFlush != 0.5 {
                penOffset = start.x
            }
            body(layout, line.line, NSMakePoint(view.frame.minX + penOffset + line.frame.minX, view.frame.minY + start.y + line.frame.minY))
        }
    }

    func update(views: [TextView]) {
        let layouts = views.compactMap { view -> (TextViewLayout, NSRect)? in
            return view.textLayout.map { ($0, view.frame) }
        }
        if layouts.count == self.layouts.count && zip(layouts, self.layouts).allSatisfy({ $0.0.0 === $0.1.0 && $0.0.1 == $0.1.1 }) {
            return
        }
        self.layouts = layouts
        self.glyphs.removeAll(keepingCapacity: true)
        self.integralCount = 0
        var column = 0
        for (kind, view) in views.enumerated() where !view.isHidden {
            Self.enumerateLines(view, { layout, line, baseline in
                let string = layout.attributedString.string as NSString
                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    let font = attributes[kCTFontAttributeName] as! CTFont
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    var indices = [CFIndex](repeating: 0, count: count)
                    CTRunGetGlyphs(run, CFRange(), &glyphs)
                    CTRunGetPositions(run, CFRange(), &positions)
                    CTRunGetStringIndices(run, CFRange(), &indices)
                    for i in 0 ..< count {
                        let shape = Self.shape(font: font, glyph: glyphs[i])
                        guard !shape.path.isEmpty else {
                            continue
                        }
                        let origin = CGPoint(x: baseline.x + positions[i].x, y: baseline.y - positions[i].y)
                        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origin.x, ty: origin.y)
                        guard let path = shape.path.copy(using: &transform) else {
                            continue
                        }
                        let index = indices[i]
                        var value: Int?
                        var digits: [Shape] = []
                        let color = (attributes[NSAttributedString.Key.foregroundColor.rawValue] as? NSColor)
                            ?? (index >= 0 && index < string.length ? layout.attributedString.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor : nil)
                            ?? .white
                        if kind == 0, index >= 0, index < string.length {
                            let character = string.substring(with: string.rangeOfComposedCharacterSequence(at: index)).first
                            if let number = character?.wholeNumberValue, number < 10 {
                                var code = string.character(at: index)
                                var expected: CGGlyph = 0
                                if CTFontGetGlyphsForCharacters(font, &code, &expected, 1), expected == glyphs[i] {
                                    value = number
                                    for digit in 0 ..< 10 {
                                        var digitCode = UniChar(Int(code) - number + digit)
                                        var digitGlyph: CGGlyph = 0
                                        CTFontGetGlyphsForCharacters(font, &digitCode, &digitGlyph, 1)
                                        digits.append(Self.shape(font: font, glyph: digitGlyph))
                                    }
                                }
                            }
                        }
                        let isIntegral = CTFontGetSize(font) >= 17.0
                        if value != nil && isIntegral {
                            self.integralCount += 1
                        }
                        let midpoint = CGPoint(x: path.boundingBoxOfPath.midX, y: path.boundingBoxOfPath.midY)
                        self.glyphs.append(Glyph(path: path, origin: origin, color: color.cgColor, kind: kind,
                            landing: WalletTransferArrivalAnimation.crossing(midpoint), value: value, column: column,
                            pitch: isIntegral ? 17.0 : 13.2, advance: shape.advance, digits: digits, image: shape.image))
                        if value != nil {
                            column += 1
                        }
                    }
                }
            })
        }
        self.needsDisplay = true
    }

    func update(time: Double) {
        self.time = time
        self.needsDisplay = true
    }

    override func draw(_ layer: CALayer, in context: CGContext) {
        super.draw(layer, in: context)
        let namePath = CGMutablePath()
        let addressPath = CGMutablePath()
        for glyph in self.glyphs {
            if let value = glyph.value, let strokes = WalletTransferArrivalAnimation.rolledDigit(value: value, column: glyph.column, pitch: glyph.pitch, landing: WalletTransferArrivalAnimation.passTime(glyph.landing), time: self.time, integralCount: self.integralCount) {
                for stroke in strokes {
                    let shape = glyph.digits[stroke.digit]
                    context.saveGState()
                    context.translateBy(x: glyph.origin.x + (glyph.advance - shape.advance) * 0.5, y: glyph.origin.y - stroke.offset)
                    context.scaleBy(x: 1.0, y: -1.0)
                    context.setAlpha(stroke.alpha)
                    context.setFillColor(glyph.color)
                    context.addPath(shape.path)
                    context.fillPath()
                    context.restoreGState()
                }
                continue
            }
            let lift = WalletTransferArrivalAnimation.glyphLift(isAmount: glyph.kind == 0, at: glyph.landing, time: self.time)
            let bounds = glyph.path.boundingBoxOfPath
            var transform = CGAffineTransform(translationX: bounds.midX, y: bounds.midY - lift.offset)
                .scaledBy(x: lift.scale, y: lift.scale).translatedBy(x: -bounds.midX, y: -bounds.midY)
            if let image = glyph.image {
                context.saveGState()
                context.concatenate(transform)
                context.translateBy(x: 0, y: bounds.maxY + bounds.minY)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: bounds)
                context.restoreGState()
                continue
            }
            guard let path = glyph.path.copy(using: &transform) else {
                continue
            }
            if glyph.kind == 2 {
                context.saveGState()
                context.translateBy(x: 0, y: 1)
                context.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
                context.addPath(path)
                context.fillPath()
                context.restoreGState()
                addressPath.addPath(path)
            } else if glyph.kind == 1 {
                namePath.addPath(path)
            }
            context.setFillColor(glyph.color)
            context.addPath(path)
            context.fillPath()
        }
        if let x = WalletTransferArrivalAnimation.sheenX(self.time) {
            for (path, gradient) in [(addressPath, self.addressGradient), (namePath, self.nameGradient)] {
                context.saveGState()
                context.addPath(path)
                context.clip()
                if path === namePath {
                    context.setBlendMode(.plusLighter)
                }
                let sheen = WalletTransferArrivalAnimation.textSheen(x: x)
                context.drawLinearGradient(gradient, start: sheen.start, end: sheen.end, options: [])
                context.restoreGState()
            }
        }
    }
}
