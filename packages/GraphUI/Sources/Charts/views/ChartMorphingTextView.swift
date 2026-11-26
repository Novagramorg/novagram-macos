import Cocoa
import TGUIKit

private let glyphPadding: CGFloat = 2
private let glyphCacheLimit = 768
private let departingLimit = 64
private let rollTravel: CGFloat = 0.72
private let rollScale: CGFloat = 0.64
private let popScale: CGFloat = 0.42
private let staggerStep: Double = 0.012
private let staggerLimit: Double = 0.06
private let fadeInDuration: Double = 0.2
private let fadeOutDuration: Double = 0.11
private let springStiffness: CGFloat = 380
private let springDamping: CGFloat = 31
private let minimumAnimatedInterval: Double = 0.07
private let springSettlingDuration: Double = {
    let animation = CASpringAnimation()
    animation.mass = 1
    animation.stiffness = springStiffness
    animation.damping = springDamping
    animation.initialVelocity = 0
    return animation.settlingDuration
}()
private let glyphActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "transform": NSNull(), "contents": NSNull(), "contentsScale": NSNull(), "hidden": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull()]

private struct MorphGlyphKey: Hashable {
    let character: String
    let fontName: String
    let fontSize: CGFloat
    let color: UInt64
    let scale: CGFloat
}

private final class MorphGlyphImage {
    let image: CGImage?
    let size: CGSize
    let advance: CGFloat

    init(image: CGImage?, size: CGSize, advance: CGFloat) {
        self.image = image
        self.size = size
        self.advance = advance
    }
}

private func packedColor(_ color: NSColor) -> UInt64 {
    guard let rgb = color.usingColorSpace(.sRGB) else {
        return UInt64(truncatingIfNeeded: color.hashValue)
    }
    func channel(_ value: CGFloat) -> UInt64 {
        return UInt64(max(0, min(65535, (value * 65535).rounded())))
    }
    return channel(rgb.redComponent) << 48 | channel(rgb.greenComponent) << 32 | channel(rgb.blueComponent) << 16 | channel(rgb.alphaComponent)
}

private final class MorphGlyphCache {
    static let shared = MorphGlyphCache()

    private var images: [MorphGlyphKey: MorphGlyphImage] = [:]
    private var advances: [MorphGlyphKey: CGFloat] = [:]

    func advance(_ character: String, font: NSFont) -> CGFloat {
        let key = MorphGlyphKey(character: character, fontName: font.fontName, fontSize: font.pointSize, color: 0, scale: 0)
        if let advance = self.advances[key] {
            return advance
        }
        if self.advances.count > glyphCacheLimit * 2 {
            self.advances.removeAll(keepingCapacity: true)
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: character, attributes: [.font: font]))
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        self.advances[key] = advance
        return advance
    }

    func image(_ character: String, font: NSFont, color: NSColor, colorKey: UInt64, scale: CGFloat) -> MorphGlyphImage {
        let key = MorphGlyphKey(character: character, fontName: font.fontName, fontSize: font.pointSize, color: colorKey, scale: scale)
        if let image = self.images[key] {
            return image
        }
        if self.images.count > glyphCacheLimit {
            self.images.removeAll(keepingCapacity: true)
        }
        let advance = self.advance(character, font: font)
        let ascent = ceil(font.ascender)
        let descent = ceil(-font.descender)
        let size = CGSize(width: ceil(advance) + glyphPadding * 2, height: ascent + descent + glyphPadding * 2)
        var image: CGImage?
        if !character.allSatisfy(\.isWhitespace) {
            let width = Int(size.width * scale)
            let height = Int(size.height * scale)
            if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.scaleBy(x: scale, y: scale)
                context.setAllowsFontSmoothing(false)
                context.setShouldSubpixelPositionFonts(true)
                context.setShouldSubpixelQuantizeFonts(false)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: character, attributes: [.font: font, .foregroundColor: color]))
                context.textPosition = CGPoint(x: glyphPadding, y: glyphPadding + descent)
                CTLineDraw(line, context)
                image = context.makeImage()
            }
        }
        let result = MorphGlyphImage(image: image, size: size, advance: advance)
        self.images[key] = result
        return result
    }
}

private final class DepartingLayerRemover: NSObject, CAAnimationDelegate {
    private weak var layer: CALayer?
    private weak var owner: ChartMorphingTextView?

    init(layer: CALayer, owner: ChartMorphingTextView) {
        self.layer = layer
        self.owner = owner
    }

    func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        if let layer = self.layer {
            self.owner?.finishDeparting(layer)
        }
    }
}

public final class ChartMorphingTextView: View {
    public enum Alignment {
        case left
        case right
    }

    private struct Glyph: Equatable {
        let character: String
        let font: NSFont
        let color: NSColor
        let colorKey: UInt64

        var isWhitespace: Bool {
            return self.character.allSatisfy(\.isWhitespace)
        }

        var isDigit: Bool {
            return self.character.first?.isNumber ?? false
        }

        static func ==(lhs: Glyph, rhs: Glyph) -> Bool {
            return lhs.colorKey == rhs.colorKey && lhs.character == rhs.character && lhs.font == rhs.font
        }
    }

    private final class Slot {
        let glyph: Glyph
        let layer: CALayer?
        let advance: CGFloat

        init(glyph: Glyph, layer: CALayer?, advance: CGFloat) {
            self.glyph = glyph
            self.layer = layer
            self.advance = advance
        }
    }

    private enum Direction {
        case up
        case down
        case none
    }

    private enum Change {
        case recolor
        case roll(Direction)
        case pop
    }

    public var alignment: Alignment = .left {
        didSet {
            if oldValue != self.alignment {
                self.placeSlots()
            }
        }
    }

    public private(set) var contentSize: CGSize = .zero

    public var clipsToRow: Bool = false {
        didSet {
            self.layer?.masksToBounds = self.clipsToRow
        }
    }

    private var slots: [Slot] = []
    private var departing: [CALayer] = []
    private var lineAscent: CGFloat = 0
    private var lastUpdate: Double = 0

    public static func size(of attributedString: NSAttributedString) -> CGSize {
        var width: CGFloat = 0
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: attributedString.length), options: []) { value, range, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            ascent = max(ascent, ceil(font.ascender))
            descent = max(descent, ceil(-font.descender))
            for character in attributedString.attributedSubstring(from: range).string {
                width += MorphGlyphCache.shared.advance(String(character), font: font)
            }
        }
        return CGSize(width: ceil(width), height: ascent + descent)
    }

    public static func size(of text: String, font: NSFont) -> CGSize {
        var width: CGFloat = 0
        for character in text {
            width += MorphGlyphCache.shared.advance(String(character), font: font)
        }
        return CGSize(width: ceil(width), height: ceil(font.ascender) + ceil(-font.descender))
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isEventLess = true
        self.layer?.masksToBounds = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        self.placeSlots()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let glyphs = self.slots.map(\.glyph)
        self.removeAllGlyphs()
        self.apply(glyphs, animated: false)
    }

    public func update(text: String, font: NSFont, color: NSColor, animated: Bool) {
        let colorKey = packedColor(color)
        self.apply(text.map { Glyph(character: String($0), font: font, color: color, colorKey: colorKey) }, animated: animated)
    }

    public func update(attributedString: NSAttributedString, animated: Bool) {
        var glyphs: [Glyph] = []
        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { attributes, range, _ in
            let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            let color = (attributes[.foregroundColor] as? NSColor) ?? .labelColor
            let colorKey = packedColor(color)
            for character in attributedString.attributedSubstring(from: range).string {
                glyphs.append(Glyph(character: String(character), font: font, color: color, colorKey: colorKey))
            }
        }
        self.apply(glyphs, animated: animated)
    }

    fileprivate func finishDeparting(_ layer: CALayer) {
        layer.removeFromSuperlayer()
        if let index = self.departing.firstIndex(where: { $0 === layer }) {
            self.departing.remove(at: index)
        }
    }

    private var backingScale: CGFloat {
        return self.window?.backingScaleFactor ?? System.backingScale
    }

    private func makeLayer(for glyph: Glyph) -> (CALayer?, CGFloat) {
        let scale = self.backingScale
        let image = MorphGlyphCache.shared.image(glyph.character, font: glyph.font, color: glyph.color, colorKey: glyph.colorKey, scale: scale)
        guard let cgImage = image.image else {
            return (nil, image.advance)
        }
        let layer = CALayer()
        layer.actions = glyphActions
        layer.contents = cgImage
        layer.contentsScale = scale
        layer.bounds = CGRect(origin: .zero, size: image.size)
        return (layer, image.advance)
    }

    private func removeAllGlyphs() {
        for slot in self.slots {
            slot.layer?.removeFromSuperlayer()
        }
        for layer in self.departing {
            layer.removeFromSuperlayer()
        }
        self.slots.removeAll()
        self.departing.removeAll()
    }

    private func updateMetrics(_ glyphs: [Glyph]) {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        for glyph in glyphs {
            ascent = max(ascent, ceil(glyph.font.ascender))
            descent = max(descent, ceil(-glyph.font.descender))
        }
        self.lineAscent = ascent
        self.contentSize = CGSize(width: ceil(self.slots.reduce(0) { $0 + $1.advance }), height: ascent + descent)
    }

    private func apply(_ glyphs: [Glyph], animated: Bool) {
        if glyphs.count == self.slots.count && zip(glyphs, self.slots).allSatisfy({ $0 == $1.glyph }) {
            return
        }
        self.setAccessibilityLabel(glyphs.map(\.character).joined())

        if !animated || self.window == nil || self.slots.isEmpty {
            self.removeAllGlyphs()
            self.slots = glyphs.map { glyph in
                let (layer, advance) = self.makeLayer(for: glyph)
                if let layer = layer {
                    self.layer?.addSublayer(layer)
                }
                return Slot(glyph: glyph, layer: layer, advance: advance)
            }
            self.updateMetrics(glyphs)
            self.placeSlots()
            return
        }

        let now = CACurrentMediaTime()
        let instant = now - self.lastUpdate < minimumAnimatedInterval
        self.lastUpdate = now
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let oldSlots = self.slots
        let oldGlyphs = oldSlots.map(\.glyph)
        let pairs = self.pairs(old: oldGlyphs, new: glyphs)
        let direction = self.direction(old: oldGlyphs, new: glyphs)
        var newSlots: [Slot] = []
        var entering: [(CALayer, Change, Double)] = []
        var leaving: [(CALayer, Change, Double)] = []
        var changedCount = 0

        func replace(_ oldSlot: Slot?, with glyph: Glyph, change: Change, delay: Double) {
            let (layer, advance) = self.makeLayer(for: glyph)
            newSlots.append(Slot(glyph: glyph, layer: layer, advance: advance))
            if let layer = layer {
                self.layer?.addSublayer(layer)
                entering.append((layer, change, delay))
            }
            if let layer = oldSlot?.layer {
                leaving.append((layer, change, delay))
            }
        }

        for pair in pairs.reversed() {
            switch pair {
            case let (old?, new?):
                let oldSlot = oldSlots[old]
                let glyph = glyphs[new]
                if oldSlot.glyph == glyph {
                    newSlots.append(oldSlot)
                } else if oldSlot.glyph.character == glyph.character {
                    replace(oldSlot, with: glyph, change: .recolor, delay: 0)
                } else {
                    let delay = min(Double(changedCount) * staggerStep, staggerLimit)
                    changedCount += 1
                    let roll = (glyph.isDigit && oldSlot.glyph.isDigit) ? direction : Direction.none
                    replace(oldSlot, with: glyph, change: .roll(roll), delay: delay)
                }
            case let (nil, new?):
                replace(nil, with: glyphs[new], change: .pop, delay: min(Double(changedCount) * staggerStep, staggerLimit))
                changedCount += 1
            case let (old?, nil):
                if let layer = oldSlots[old].layer {
                    leaving.append((layer, .pop, 0))
                }
            default:
                break
            }
        }
        newSlots.reverse()
        self.slots = newSlots
        self.updateMetrics(glyphs)

        if instant {
            for (layer, _, _) in leaving {
                layer.removeFromSuperlayer()
            }
            self.placeSlots()
            return
        }

        var previousPositions: [ObjectIdentifier: CGPoint] = [:]
        if !reduceMotion {
            let enteringLayers = Set(entering.map { ObjectIdentifier($0.0) })
            for slot in newSlots {
                if let layer = slot.layer, !enteringLayers.contains(ObjectIdentifier(layer)) {
                    previousPositions[ObjectIdentifier(layer)] = self.presentedPosition(layer)
                }
            }
        }
        self.placeSlots()

        for slot in newSlots {
            guard let layer = slot.layer, let from = previousPositions[ObjectIdentifier(layer)], from != layer.position else {
                continue
            }
            layer.add(self.spring("position", from: NSValue(point: from), to: NSValue(point: layer.position), delay: 0), forKey: "position")
        }

        let lineHeight = self.contentSize.height
        for (layer, change, delay) in entering {
            layer.add(self.fade(from: 0, to: 1, duration: fadeInDuration, delay: delay, timing: .easeIn), forKey: "opacity")
            if reduceMotion {
                continue
            }
            switch change {
            case .recolor:
                break
            case .pop:
                layer.add(self.spring("transform.scale", from: popScale, to: 1, delay: delay), forKey: "scale")
            case .roll(.none):
                layer.add(self.spring("transform.scale", from: 0.86, to: 1, delay: delay), forKey: "scale")
            case let .roll(roll):
                let offset = lineHeight * rollTravel * (roll == .up ? 1 : -1)
                let target = layer.position
                layer.add(self.spring("position", from: NSValue(point: CGPoint(x: target.x, y: target.y + offset)), to: NSValue(point: target), delay: delay), forKey: "position")
                layer.add(self.spring("transform.scale", from: rollScale, to: 1, delay: delay), forKey: "scale")
            }
        }

        for (layer, change, delay) in leaving {
            let animating = layer.animationKeys() != nil
            let presentation = animating ? layer.presentation() : nil
            let fromOpacity = presentation?.opacity ?? layer.opacity
            let fromPosition = presentation?.position ?? layer.position
            let fromScale = (presentation?.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
            if animating {
                layer.removeAllAnimations()
            }
            self.departing.append(layer)
            layer.opacity = 0
            layer.position = fromPosition
            let fade: CAAnimation
            if case .recolor = change {
                fade = self.fade(from: fromOpacity, to: fromOpacity, duration: fadeInDuration, delay: 0)
            } else {
                fade = self.fade(from: fromOpacity, to: 0, duration: fadeOutDuration, delay: delay)
            }
            fade.delegate = DepartingLayerRemover(layer: layer, owner: self)
            layer.add(fade, forKey: "opacity")
            if reduceMotion {
                continue
            }
            switch change {
            case .recolor:
                break
            case .pop:
                layer.add(self.spring("transform.scale", from: fromScale, to: popScale, delay: delay), forKey: "scale")
            case .roll(.none):
                layer.add(self.spring("transform.scale", from: fromScale, to: 0.86, delay: delay), forKey: "scale")
            case let .roll(roll):
                let offset = lineHeight * rollTravel * (roll == .up ? -1 : 1)
                let target = CGPoint(x: fromPosition.x, y: fromPosition.y + offset)
                layer.position = target
                layer.add(self.spring("position", from: NSValue(point: fromPosition), to: NSValue(point: target), delay: delay), forKey: "position")
                layer.add(self.spring("transform.scale", from: fromScale, to: rollScale, delay: delay), forKey: "scale")
            }
        }

        while self.departing.count > departingLimit {
            self.departing.removeFirst().removeFromSuperlayer()
        }
    }

    private func presentedPosition(_ layer: CALayer) -> CGPoint {
        if layer.animation(forKey: "position") != nil, let presentation = layer.presentation() {
            return presentation.position
        }
        return layer.position
    }

    private func placeSlots() {
        let originX: CGFloat
        switch self.alignment {
        case .left:
            originX = 0
        case .right:
            originX = self.bounds.width - self.contentSize.width
        }
        let originY = floor((self.bounds.height - self.contentSize.height) / 2)
        var x = originX
        for slot in self.slots {
            if let layer = slot.layer {
                let size = layer.bounds.size
                let top = originY + self.lineAscent - ceil(slot.glyph.font.ascender) - glyphPadding
                let position = CGPoint(x: x - glyphPadding + size.width / 2, y: top + size.height / 2)
                if layer.position != position {
                    layer.position = position
                }
            }
            x += slot.advance
        }
    }

    private func pairs(old: [Glyph], new: [Glyph]) -> [(Int?, Int?)] {
        func aligned(_ oldRange: Range<Int>, _ newRange: Range<Int>, fromRight: Bool) -> [(Int?, Int?)] {
            let count = max(oldRange.count, newRange.count)
            var result: [(Int?, Int?)] = []
            result.reserveCapacity(count)
            for i in 0 ..< count {
                if fromRight {
                    let o = oldRange.count - count + i
                    let n = newRange.count - count + i
                    result.append((o >= 0 ? oldRange.lowerBound + o : nil, n >= 0 ? newRange.lowerBound + n : nil))
                } else {
                    result.append((i < oldRange.count ? oldRange.lowerBound + i : nil, i < newRange.count ? newRange.lowerBound + i : nil))
                }
            }
            return result
        }
        if self.alignment == .right {
            return aligned(0 ..< old.count, 0 ..< new.count, fromRight: true)
        }
        func words(_ glyphs: [Glyph]) -> [Range<Int>] {
            var result: [Range<Int>] = []
            var start: Int?
            for (index, glyph) in glyphs.enumerated() {
                if glyph.isWhitespace {
                    if let value = start {
                        result.append(value ..< index)
                        start = nil
                    }
                    result.append(index ..< index + 1)
                } else if start == nil {
                    start = index
                }
            }
            if let value = start {
                result.append(value ..< glyphs.count)
            }
            return result
        }
        let oldWords = words(old)
        let newWords = words(new)
        guard oldWords.count == newWords.count else {
            return aligned(0 ..< old.count, 0 ..< new.count, fromRight: false)
        }
        var result: [(Int?, Int?)] = []
        for (oldWord, newWord) in zip(oldWords, newWords) {
            let numeric = new[newWord].contains(where: \.isDigit) || old[oldWord].contains(where: \.isDigit)
            result.append(contentsOf: aligned(oldWord, newWord, fromRight: numeric))
        }
        return result
    }

    private func direction(old: [Glyph], new: [Glyph]) -> Direction {
        func value(_ glyphs: [Glyph]) -> Double? {
            var digits = ""
            var multiplier: Double = 1
            scan: for glyph in glyphs {
                if glyph.isDigit {
                    digits += glyph.character
                } else if digits.isEmpty || glyph.character == "," || glyph.isWhitespace {
                    continue
                } else if glyph.character == "." && !digits.contains(".") {
                    digits += "."
                } else {
                    switch glyph.character {
                    case "K":
                        multiplier = 1e3
                    case "M":
                        multiplier = 1e6
                    case "B":
                        multiplier = 1e9
                    default:
                        break
                    }
                    break scan
                }
            }
            return Double(digits).map { $0 * multiplier }
        }
        guard let lhs = value(old), let rhs = value(new), lhs != rhs else {
            return .up
        }
        return rhs > lhs ? .up : .down
    }

    private func spring(_ keyPath: String, from: Any, to: Any, delay: Double) -> CAAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.mass = 1
        animation.stiffness = springStiffness
        animation.damping = springDamping
        animation.initialVelocity = 0
        animation.duration = springSettlingDuration
        if delay > 0 {
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
        }
        animation.isRemovedOnCompletion = true
        return animation
    }

    private func fade(from: Float, to: Float, duration: Double, delay: Double, timing: CAMediaTimingFunctionName = .easeOut) -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        if delay > 0 {
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
        }
        animation.isRemovedOnCompletion = true
        return animation
    }
}
