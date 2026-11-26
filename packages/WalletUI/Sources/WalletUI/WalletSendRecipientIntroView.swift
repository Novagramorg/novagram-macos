import Cocoa
import CoreText
import TGUIKit
import TelegramTheme

final class WalletSendRecipientIntroView: NSView {
    private struct ShapeKey: Hashable {
        var font: String
        var size: CGFloat
        var glyph: CGGlyph
    }
    private struct Shape {
        var path: CGPath
        var image: CGImage?
        var advance: CGFloat
    }
    private struct Piece {
        var shape: Shape
        var font: CTFont
        var origin: CGPoint
        var width: CGFloat
        var color: NSColor
        var column: Int
        var space: Bool
    }
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    private var shapes: [ShapeKey: Shape] = [:]
    private var title: [Piece] = []
    private var address: [[Piece]] = []
    private var titleLayouts: [TextViewLayout] = []
    private var titleFrames: [CGRect] = []
    private var addressLayout: TextViewLayout?
    private var addressFrame = CGRect.zero
    private var avatarFrame = CGRect.zero
    private var avatarImage: CGImage?
    private var coarseAvatar: CGImage?
    private var fineAvatar: CGImage?
    private var font: CTFont = walletRecipientAddressFont as CTFont
    private var secondary = theme.colors.grayText
    private var primary = theme.colors.text
    private var time: Double = 0.0
    private var loadingAddress = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return true
    }

    override var isOpaque: Bool {
        return false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }

    private static func noise(_ a: Int, _ salt: Int) -> Double {
        var x = UInt32(truncatingIfNeeded: a &* 73_856_093 ^ salt &* 19_349_663)
        x ^= x >> 13
        x = x &* 0x5bd1_e995
        x ^= x >> 15
        return Double(x % 10_000) / 10_000.0
    }

    private static func start(x: CGFloat, salt: Int, delay: Double = 0.0) -> Double {
        return 0.1 + delay + 0.5 * Double(x / 300.0) + 0.14 * self.noise(Int(x * 10.0), salt)
    }

    private static func path(_ u: Double) -> (p: Double, speed: Double) {
        let x = u - 1.0
        return (1.0 + 1.9 * x * x * x + 0.9 * x * x, 5.7 * x * x + 1.8 * x)
    }

    private static func passTime(_ target: Double) -> Double {
        var lo = 0.0
        var hi = 1.0
        for _ in 0 ..< 18 {
            let mid = (lo + hi) / 2.0
            if self.path(mid).p < target {
                lo = mid
            } else {
                hi = mid
            }
        }
        return hi
    }

    private static func smooth(_ value: Double) -> Double {
        let k = min(1.0, max(0.0, value))
        return k * k * (3.0 - 2.0 * k)
    }

    private static func isLayerTreeAttached(_ view: NSView) -> Bool {
        guard let layer = view.layer else {
            return false
        }
        return view.subviews.allSatisfy { $0.layer?.superlayer === layer && self.isLayerTreeAttached($0) }
    }

    private func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private func shape(font: CTFont, glyph: CGGlyph) -> Shape {
        let key = ShapeKey(font: CTFontCopyPostScriptName(font) as String, size: CTFontGetSize(font), glyph: glyph)
        if let shape = self.shapes[key] {
            return shape
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
                let glyphToDraw = glyph
                image = generateImage(bounds.size, contextGenerator: { size, context in
                    context.clear(CGRect(origin: .zero, size: size))
                    context.translateBy(x: -bounds.minX, y: -bounds.minY)
                    var glyph = glyphToDraw
                    var position = CGPoint.zero
                    CTFontDrawGlyphs(font, &glyph, &position, 1, context)
                }, scale: self.backingScaleFactor)
                path = CGPath(rect: bounds, transform: nil)
            } else {
                path = CGMutablePath()
            }
        }
        let result = Shape(path: path, image: image, advance: advance.width)
        self.shapes[key] = result
        return result
    }

    private func random(_ index: Int, salt: Int, font: CTFont, time: Double? = nil) -> Shape {
        let tick = Int(min(max(time ?? self.time, 0.0), 3600.0) / 0.045)
        let hash = (index &* 2_654_435_761) ^ (tick &* 40_503) ^ (salt &* 97)
        var code = String(Self.alphabet[(hash & 0x7fff_ffff) % Self.alphabet.count]).utf16.first ?? 48
        var glyph: CGGlyph = 0
        var font = font
        if !CTFontGetGlyphsForCharacters(font, &code, &glyph, 1) {
            font = NSFont.systemFont(ofSize: CTFontGetSize(font)) as CTFont
            _ = CTFontGetGlyphsForCharacters(font, &code, &glyph, 1)
        }
        return self.shape(font: font, glyph: glyph)
    }

    private func pieces(_ view: TextView, frame: CGRect) -> [[Piece]] {
        guard let layout = view.textLayout else {
            return []
        }
        let text = layout.attributedString.string as NSString
        let startY = round((frame.height - layout.layoutSize.height) / 2.0)
        var lines: [[Piece]] = []
        for textLine in layout.lines {
            let penOffset = CGFloat(CTLineGetPenOffsetForFlush(textLine.line, textLine.penFlush, Double(frame.width)))
            let baseline = CGPoint(x: penOffset + textLine.frame.minX, y: startY + textLine.frame.minY)
            var pieces: [Piece] = []
            for run in CTLineGetGlyphRuns(textLine.line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let fontValue = attributes[kCTFontAttributeName] else {
                    continue
                }
                let font = fontValue as! CTFont
                let color = attributes[NSAttributedString.Key.foregroundColor.rawValue] as? NSColor ?? self.primary
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphs)
                CTRunGetPositions(run, CFRange(), &positions)
                CTRunGetAdvances(run, CFRange(), &advances)
                CTRunGetStringIndices(run, CFRange(), &indices)
                for i in 0 ..< count {
                    let index = indices[i]
                    let character = index >= 0 && index < text.length ? text.character(at: index) : 0
                    if character == 10 {
                        continue
                    }
                    pieces.append(Piece(shape: self.shape(font: font, glyph: glyphs[i]), font: font,
                        origin: CGPoint(x: frame.minX + baseline.x + positions[i].x, y: frame.minY + baseline.y - positions[i].y),
                        width: advances[i].width, color: color, column: pieces.count, space: character == 32))
                }
            }
            lines.append(pieces)
        }
        return lines
    }

    func updateTitle(_ views: [TextView], frames: [CGRect], primary: NSColor, secondary: NSColor) {
        self.primary = primary
        self.secondary = secondary
        let layouts = views.compactMap { $0.textLayout }
        guard self.titleFrames != frames || layouts.count != self.titleLayouts.count
            || !zip(layouts, self.titleLayouts).allSatisfy({ $0.0 === $0.1 }) else {
            return
        }
        self.titleLayouts = layouts
        self.titleFrames = frames
        self.title = zip(views, frames).flatMap { view, frame in
            self.pieces(view, frame: frame).flatMap { $0 }.filter { !$0.space }
        }
    }

    func updateAddress(_ view: TextView, frame: CGRect, loading: Bool) {
        self.loadingAddress = loading
        guard self.addressLayout !== view.textLayout || self.addressFrame != frame else {
            return
        }
        self.addressLayout = view.textLayout
        self.addressFrame = frame
        self.address = self.pieces(view, frame: frame)
        if let font = self.address.first?.first?.font {
            self.font = font
        }
    }

    func updateAvatar(_ view: NSView, frame: CGRect) {
        self.avatarFrame = frame
        guard self.avatarImage == nil, !view.bounds.isEmpty, view.window != nil, let layer = view.layer, Self.isLayerTreeAttached(view) else {
            return
        }
        func display(_ layer: CALayer) {
            layer.displayIfNeeded()
            for child in layer.sublayers ?? [] {
                display(child)
            }
        }
        display(layer)
        let alpha = view.alphaValue
        view.alphaValue = 1.0
        let isFlipped = layer.contentsAreFlipped()
        let image = generateImage(view.bounds.size, contextGenerator: { size, context in
            context.clear(CGRect(origin: .zero, size: size))
            if isFlipped {
                context.translateBy(x: 0.0, y: size.height)
                context.scaleBy(x: 1.0, y: -1.0)
            }
            layer.render(in: context)
        }, scale: view.backingScaleFactor)
        view.alphaValue = alpha
        guard let image else {
            return
        }
        self.avatarImage = image
        let grid = self.avatarGrid
        func sample(_ split: Int) -> CGImage? {
            let size = CGSize(width: CGFloat(grid.columns * split), height: CGFloat(grid.rows * split))
            return generateImage(size, contextGenerator: { size, context in
                context.clear(CGRect(origin: .zero, size: size))
                context.draw(image, in: CGRect(origin: .zero, size: size))
            }, scale: 1.0)
        }
        self.coarseAvatar = sample(2)
        self.fineAvatar = sample(4)
    }

    func update(time: Double) {
        self.time = time
        self.needsDisplay = true
    }

    private func fill(_ shape: Shape, at origin: CGPoint, color: NSColor, alpha: CGFloat = 1.0, context: CGContext) {
        context.saveGState()
        context.setAlpha(alpha)
        if let image = shape.image {
            let bounds = shape.path.boundingBoxOfPath
            self.drawImage(image, in: CGRect(x: origin.x + bounds.minX, y: origin.y - bounds.maxY, width: bounds.width, height: bounds.height), context: context)
        } else {
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: 1.0, y: -1.0)
            context.setFillColor(color.cgColor)
            context.addPath(shape.path)
            context.fillPath()
        }
        context.restoreGState()
    }

    private func smear(_ shape: Shape, at origin: CGPoint, font: CTFont, velocity: CGFloat,
                       color: NSColor, alpha: CGFloat, context: CGContext) {
        guard alpha > 0.01 else {
            return
        }
        let length = min(max(velocity, 0.0) * 0.04, CTFontGetSize(font) * 1.2)
        let samples = length > 1.0 ? min(2 + Int(length / 1.2), 14) : 1
        let weights = (0 ..< samples).map { index -> CGFloat in
            let k = samples > 1 ? CGFloat(index) / CGFloat(samples - 1) : 0.0
            return pow(1.0 - k, 1.6)
        }
        let total = max(weights.dropFirst().reduce(0.0, +), 0.001)
        for index in 0 ..< samples {
            let k = samples > 1 ? CGFloat(index) / CGFloat(samples - 1) : 0.0
            self.fill(shape, at: origin.offsetBy(dx: 0.0, dy: -length * k),
                color: index == 0 ? color : self.secondary,
                alpha: alpha * (index == 0 ? 0.8 : weights[index] / total * 1.4), context: context)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        for (index, piece) in self.title.enumerated() {
            let start = Self.start(x: piece.origin.x, salt: 51 + index)
            let fall = 0.3 + 0.08 * Self.noise(index, 52)
            let u = min((self.time - start) / fall, 1.0)
            guard u > 0.0 else {
                continue
            }
            if u >= 1.0 {
                self.fill(piece.shape, at: piece.origin, color: piece.color, context: context)
            } else {
                let path = Self.path(u)
                let drop: CGFloat = 22.0 * 1.1
                let shape = u > 0.72 ? piece.shape : self.random(index, salt: 53, font: piece.font)
                let origin = piece.origin.offsetBy(dx: (piece.width - shape.advance) / 2.0, dy: -drop * CGFloat(1.0 - path.p))
                self.smear(shape, at: origin, font: piece.font, velocity: CGFloat(path.speed) * drop / CGFloat(fall),
                    color: piece.color, alpha: CGFloat(min(u / 0.4, 1.0)), context: context)
            }
        }
        self.drawAddress(context)
        self.drawAvatar(context)
    }

    private func addressTiming(_ column: Int) -> (start: Double, fall: Double) {
        let x = self.address.first?.first(where: { $0.column == column })?.origin.x ?? self.addressFrame.minX
        return (Self.start(x: x, salt: 1, delay: 0.08), 0.36 + 0.1 * Self.noise(column, 2))
    }

    private func drawAddress(_ context: CGContext) {
        let columns = self.address.map { $0.count }.max() ?? 0
        for column in 0 ..< columns {
            let rows = self.address.indices.filter { column < self.address[$0].count && !self.address[$0][column].space }
            guard let last = rows.last else {
                continue
            }
            let bottom = self.address[last][column]
            let firstBaseline = self.address.first?.first?.origin.y ?? bottom.origin.y
            let line: CGFloat
            if self.address.count > 1, let second = self.address[1].first {
                line = second.origin.y - firstBaseline
            } else {
                line = CTFontGetAscent(self.font) + CTFontGetDescent(self.font) + 2.0
            }
            let top = firstBaseline - line
            let timing = self.addressTiming(column)
            let local = self.time - timing.start
            guard local > 0.0 else {
                continue
            }
            let u = min(local / timing.fall, 1.0)
            let path = Self.path(u)
            let head = top + (bottom.origin.y - top) * CGFloat(path.p)
            for row in rows where row != last {
                let piece = self.address[row][column]
                guard head >= piece.origin.y else {
                    continue
                }
                let passed = Self.passTime(Double((piece.origin.y - top) / (bottom.origin.y - top)))
                self.putAddress(row: row, column: column, last: last, settled: local - passed * timing.fall > 0.14, context: context)
            }
            if u < 1.0 {
                let shape = u > 0.72 ? bottom.shape : self.random(column, salt: 7, font: bottom.font)
                let enter = min(max((head - top) / line, 0.0), 1.0)
                self.smear(shape, at: CGPoint(x: bottom.origin.x + (bottom.width - shape.advance) / 2.0, y: head),
                    font: bottom.font, velocity: CGFloat(path.speed) * (bottom.origin.y - top) / CGFloat(timing.fall),
                    color: self.primary.withMultipliedAlpha(0.95), alpha: enter * enter, context: context)
            } else {
                self.putAddress(row: last, column: column, last: last, settled: true, context: context)
            }
        }
    }

    private func putAddress(row: Int, column: Int, last: Int, settled: Bool, context: CGContext) {
        let piece = self.address[row][column]
        if !settled {
            let shape = self.random(column, salt: 11 + row, font: piece.font)
            self.fill(shape, at: piece.origin.offsetBy(dx: (piece.width - shape.advance) / 2.0, dy: 0.0),
                color: self.secondary.withMultipliedAlpha(0.55), context: context)
            return
        }
        if self.loadingAddress {
            self.fill(piece.shape, at: piece.origin, color: piece.color, context: context)
            return
        }
        var from = column
        var to = column
        while from > 0 && !self.address[row][from - 1].space {
            from -= 1
        }
        while to + 1 < self.address[row].count && !self.address[row][to + 1].space {
            to += 1
        }
        let ready = (from ... to).map { column -> Double in
            let timing = self.addressTiming(column)
            return timing.start + timing.fall + (row == last ? 0.0 : 0.14)
        }.max() ?? 0.0
        let k = CGFloat(Self.smooth((self.time - ready - 0.06) / 0.24))
        let color: NSColor
        if k >= 1.0 {
            color = piece.color
        } else if k <= 0.0 {
            color = self.secondary
        } else {
            color = self.secondary.interpolateTo(piece.color, fraction: k) ?? piece.color
        }
        self.fill(piece.shape, at: piece.origin, color: color, context: context)
    }

    private var avatarGrid: (columns: Int, rows: Int, cell: CGSize) {
        var zero: UniChar = 48
        var glyph: CGGlyph = 0
        _ = CTFontGetGlyphsForCharacters(self.font, &zero, &glyph, 1)
        let columns = max(3, Int(self.avatarFrame.width / max(1.0, self.shape(font: self.font, glyph: glyph).advance)))
        let rows = max(2, Int(self.avatarFrame.height / 10.5))
        return (columns, rows, CGSize(width: self.avatarFrame.width / CGFloat(columns), height: self.avatarFrame.height / CGFloat(rows)))
    }

    private func drawAvatar(_ context: CGContext) {
        guard let image = self.avatarImage else {
            return
        }
        let grid = self.avatarGrid
        let cap = CTFontGetCapHeight(self.font)
        func baseline(_ row: Int) -> CGFloat {
            return self.avatarFrame.minY + grid.cell.height * CGFloat(row) + (grid.cell.height + cap) / 2.0
        }
        let top = baseline(0) - grid.cell.height * 1.6
        let bottom = baseline(grid.rows - 1)
        for column in 0 ..< grid.columns {
            let x = self.avatarFrame.minX + grid.cell.width * CGFloat(column)
            let start = Self.start(x: x, salt: 31)
            let fall = 0.3 + 0.08 * Self.noise(column, 32)
            for row in 0 ..< grid.rows {
                let last = row == grid.rows - 1
                let passed = start + Self.passTime(Double((baseline(row) - top) / (bottom - top))) * fall
                let settled = last ? start + fall : passed + 0.14
                let decodeStart = settled + 0.1 + 0.04 * Self.noise(row * 7 + column, 71)
                let k = (self.time - decodeStart) / 0.24
                let id = row * grid.columns + column
                let origin = CGPoint(x: x, y: baseline(row))
                if self.time >= (last ? settled : passed), k < 1.0 / 3.0 {
                    let still = self.time >= settled
                    let shape = self.random(id, salt: still ? 77 : 78, font: self.font, time: still ? 0.0 : nil)
                    self.fill(shape, at: origin.offsetBy(dx: (grid.cell.width - shape.advance) / 2.0, dy: 0.0),
                        color: still ? self.secondary : self.secondary.withMultipliedAlpha(0.55),
                        alpha: CGFloat(k > 0.0 ? 1.0 - k * 3.0 : 1.0), context: context)
                }
                if k > 0.0 {
                    context.saveGState()
                    context.addEllipse(in: self.avatarFrame)
                    context.clip()
                    let rect = CGRect(x: x, y: self.avatarFrame.minY + grid.cell.height * CGFloat(row), width: grid.cell.width, height: grid.cell.height)
                    context.clip(to: rect.insetBy(dx: -0.5, dy: -0.5))
                    context.interpolationQuality = k < 2.0 / 3.0 ? .none : .high
                    if let sample = k < 1.0 / 3.0 ? self.coarseAvatar : (k < 2.0 / 3.0 ? self.fineAvatar : image) {
                        self.drawImage(sample, in: self.avatarFrame, context: context)
                    }
                    if k < 1.0 / 3.0 {
                        let shape = self.random(id, salt: 77, font: self.font, time: 0.0)
                        self.fill(shape, at: origin.offsetBy(dx: (grid.cell.width - shape.advance) / 2.0, dy: 0.0),
                            color: .white, alpha: CGFloat(1.0 - k * 3.0), context: context)
                    }
                    context.restoreGState()
                }
            }
            let u = (self.time - start) / fall
            if u > 0.0 && u < 1.0 {
                let path = Self.path(u)
                let y = top + (bottom - top) * CGFloat(path.p)
                let id = (grid.rows - 1) * grid.columns + column
                let shape = u > 0.72 ? self.random(id, salt: 77, font: self.font, time: 0.0) : self.random(column, salt: 79, font: self.font)
                let enter = min(max((y - top) / grid.cell.height, 0.0), 1.0)
                self.smear(shape, at: CGPoint(x: x + (grid.cell.width - shape.advance) / 2.0, y: y), font: self.font,
                    velocity: CGFloat(path.speed) * (bottom - top) / CGFloat(fall), color: self.primary.withMultipliedAlpha(0.95),
                    alpha: enter * enter, context: context)
            }
        }
    }
}
