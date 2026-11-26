import Cocoa
import TGUIKit

final class WalletDigitRollLayer: SimpleLayer {
    var lines: [(line: CTLine, position: CGPoint)] = []

    override func draw(in ctx: CGContext) {
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSmoothing(contentsScale == 1.0)
        ctx.setShouldSmoothFonts(contentsScale == 1.0)
        ctx.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        for (line, position) in lines {
            for run in CTLineGetGlyphRuns(line) as NSArray {
                ctx.textPosition = position
                CTRunDraw(run as! CTRun, ctx, CFRangeMake(0, 0))
            }
        }
    }
}

struct WalletDigitMorph {
    static let offsetFactor: CGFloat = 0.6
    static let minScale: CGFloat = 0.3

    let offset: CGFloat
    let scale: CGFloat
    let alpha: CGFloat

    init(distance: CGFloat, height: CGFloat) {
        let amount = min(1.0, abs(distance))
        self.offset = max(-1.0, min(1.0, distance)) * height * WalletDigitMorph.offsetFactor
        self.scale = 1.0 - (1.0 - WalletDigitMorph.minScale) * amount
        self.alpha = 1.0 - amount
    }
}

func walletTimingCurveValue(_ x: Double, _ function: CAMediaTimingFunction) -> Double {
    var p1: [Float] = [0, 0]
    var p2: [Float] = [0, 0]
    function.getControlPoint(at: 1, values: &p1)
    function.getControlPoint(at: 2, values: &p2)
    let x1 = Double(p1[0]), y1 = Double(p1[1]), x2 = Double(p2[0]), y2 = Double(p2[1])
    func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1.0 - t
        return 3.0 * u * u * t * a + 3.0 * u * t * t * b + t * t * t
    }
    let target = max(0.0, min(1.0, x))
    var low = 0.0
    var high = 1.0
    var t = target
    for _ in 0 ..< 32 {
        let value = bezier(t, x1, x2)
        if abs(value - target) < 1e-6 {
            break
        }
        if value < target {
            low = t
        } else {
            high = t
        }
        t = (low + high) / 2.0
    }
    return bezier(t, y1, y2)
}

final class WalletDigitRoll {
    enum Mode {
        case fullTurns(rightmost: Int)
        case fromZero(maxTurns: Int)
    }

    private struct Column {
        let cells: [CALayer]
        let steps: Int
        let height: CGFloat
    }

    private let container = SimpleLayer()
    private weak var textView: TextView?
    private var columns: [Column] = []
    let key: String
    let source: NSAttributedString
    private(set) var endTime: CFTimeInterval?

    init?(textView: TextView, key: String = "", mode: Mode) {
        guard let layout = textView.textLayout, let line = layout.lines.first, let hostLayer = textView.layer, !textView.bounds.isEmpty else {
            return nil
        }
        let attributed = layout.attributedString
        let string = attributed.string as NSString
        var digits: [(index: Int, value: Int)] = []
        for index in 0 ..< string.length {
            let code = Int(string.character(at: index))
            if code >= 48, code <= 57 {
                digits.append((index, code - 48))
            }
        }
        guard !digits.isEmpty else {
            return nil
        }
        self.textView = textView
        self.key = key
        self.source = attributed

        let origin = textView.focus(layout.layoutSize).origin
        let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line.line, line.penFlush, Double(textView.frame.width)))
        let textPosition = CGPoint(x: penOffset + line.frame.minX, y: origin.y + line.frame.minY)
        let window = textView.bounds.insetBy(dx: 0, dy: -3)
        let contentsScale = textView.window?.backingScaleFactor ?? System.backingScale

        func makeLine(visible digit: (index: Int, value: Int)?) -> CTLine {
            let text = NSMutableAttributedString(attributedString: attributed)
            if let digit {
                let color = attributed.attribute(.foregroundColor, at: digit.index, effectiveRange: nil) ?? NSColor.white
                text.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: 0, length: text.length))
                text.replaceCharacters(in: NSRange(location: digit.index, length: 1), with: "\(digit.value)")
                text.addAttribute(.foregroundColor, value: color, range: NSRange(location: digit.index, length: 1))
            } else {
                for digit in digits {
                    text.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: digit.index, length: 1))
                }
            }
            return CTLineCreateWithAttributedString(text)
        }

        func advance(_ line: CTLine, at index: Int) -> CGFloat {
            return CTLineGetOffsetForStringIndex(line, index + 1, nil) - CTLineGetOffsetForStringIndex(line, index, nil)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        container.frame = textView.bounds
        if digits.count < string.length {
            let staticLayer = WalletDigitRollLayer()
            staticLayer.contentsScale = contentsScale
            staticLayer.frame = window
            staticLayer.lines = [(makeLine(visible: nil), CGPoint(x: textPosition.x - window.minX, y: textPosition.y - window.minY))]
            staticLayer.setNeedsDisplay()
            container.addSublayer(staticLayer)
        }
        var prefixValue = 0
        for (position, digit) in digits.enumerated() {
            prefixValue = min(prefixValue * 10 + digit.value, 1_000_000)
            let steps: Int
            let firstValue: Int
            switch mode {
            case let .fullTurns(rightmost):
                steps = 10 * (position == digits.count - 1 ? max(1, rightmost) : 1)
                firstValue = digit.value
            case let .fromZero(maxTurns):
                steps = digit.value + 10 * min(maxTurns, prefixValue / 10)
                firstValue = 0
            }
            let lines = (0 ... steps).map { step -> CTLine in
                return makeLine(visible: (digit.index, (firstValue + step) % 10))
            }
            let finalAdvance = advance(line.line, at: digit.index)
            let widestAdvance = lines.reduce(finalAdvance) { max($0, advance($1, at: digit.index)) }
            let glyphMinX = textPosition.x + CTLineGetOffsetForStringIndex(line.line, digit.index, nil)
            let center = glyphMinX + finalAdvance / 2
            let minX = floor(center - widestAdvance / 2) - 2.0
            let maxX = ceil(center + widestAdvance / 2) + 2.0
            let frame = NSMakeRect(minX, window.minY, maxX - minX, window.height)
            let font = attributed.attribute(.font, at: digit.index, effectiveRange: nil) as? NSFont
            let baseline = textPosition.y - window.minY
            let glyphMidY = baseline - (font?.capHeight ?? window.height / 2) / 2
            let glyphHeight = (font.map { $0.ascender - $0.descender }) ?? window.height
            let cells = lines.enumerated().map { step, cell -> CALayer in
                let layer = WalletDigitRollLayer()
                layer.contentsScale = contentsScale
                layer.anchorPoint = CGPoint(x: (center - minX) / frame.width, y: glyphMidY / frame.height)
                layer.frame = frame
                let shift = (finalAdvance - advance(cell, at: digit.index)) / 2
                layer.lines = [(cell, CGPoint(x: textPosition.x - minX + shift, y: baseline))]
                layer.opacity = step == 0 ? 1.0 : 0.0
                layer.setNeedsDisplay()
                container.addSublayer(layer)
                return layer
            }
            if steps > 0 {
                columns.append(Column(cells: cells, steps: steps, height: glyphHeight))
            }
        }
        hostLayer.addSublayer(container)
        textView.drawingLayer.opacity = 0.0

        CATransaction.commit()
    }

    func play(at start: CFTimeInterval, duration: Double, timingFunction: CAMediaTimingFunction, completion: (() -> Void)? = nil) {
        endTime = start + duration
        let samples = max(2, Int(ceil(duration * 120.0)))
        let progress = (0 ... samples).map { walletTimingCurveValue(Double($0) / Double(samples), timingFunction) }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.0
        NSAnimationContext.current.timingFunction = nil
        NSAnimationContext.current.allowsImplicitAnimation = false
        let beginTime = container.convertTime(start, from: nil)
        var isFirst = true
        for column in columns {
            for (step, cell) in column.cells.enumerated() {
                let morphs = progress.map { value in
                    return WalletDigitMorph(distance: CGFloat(step) - CGFloat(value) * CGFloat(column.steps), height: column.height)
                }
                guard morphs.contains(where: { $0.alpha > 0.0 }) else {
                    continue
                }
                let transform = CAKeyframeAnimation(keyPath: "transform")
                transform.values = morphs.map { morph in
                    return NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeTranslation(0.0, morph.offset, 0.0), morph.scale, morph.scale, 1.0))
                }
                let opacity = CAKeyframeAnimation(keyPath: "opacity")
                opacity.values = morphs.map { NSNumber(value: Float($0.alpha)) }
                for animation in [transform, opacity] {
                    animation.duration = duration
                    animation.calculationMode = .linear
                    animation.beginTime = beginTime
                    animation.fillMode = .both
                    animation.isRemovedOnCompletion = false
                }
                if isFirst, let completion {
                    isFirst = false
                    opacity.delegate = CALayerAnimationDelegate(completion: { _ in
                        completion()
                    })
                }
                cell.add(transform, forKey: "walletDigitMorphTransform")
                cell.add(opacity, forKey: "walletDigitMorphOpacity")
            }
        }
        NSAnimationContext.endGrouping()
        if isFirst {
            completion?()
        }
    }

    func matches(_ textView: TextView) -> Bool {
        return textView === self.textView && textView.textLayout?.attributedString.isEqual(to: source) == true
    }

    func remove() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.removeFromSuperlayer()
        textView?.drawingLayer.opacity = 1.0
        CATransaction.commit()
    }
}
