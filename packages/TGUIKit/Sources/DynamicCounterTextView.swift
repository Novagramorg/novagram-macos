import Foundation
import AppKit

final class DynamicCounterDigitWidthCache {
    private struct Entry {
        let font: NSFont
        let width: CGFloat
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func width(for font: NSFont) -> CGFloat {
        lock.lock()
        let cached = entries.first(where: { $0.font === font })?.width
        lock.unlock()
        if let cached {
            return cached
        }

        var width: CGFloat = 0
        var usesRequestedFont = true
        for digit in 0...9 {
            let line = CTLineCreateWithAttributedString(NSAttributedString.initialize(string: "\(digit)", color: nil, font: font))
            width = max(width, ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))))
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                if let runFont = attributes[kCTFontAttributeName] {
                    usesRequestedFont = usesRequestedFont && CFEqual(runFont as CFTypeRef, font)
                } else {
                    usesRequestedFont = false
                }
            }
        }

        if usesRequestedFont {
            lock.lock()
            if !entries.contains(where: { $0.font === font }) {
                if entries.count == 16 {
                    entries.removeFirst()
                }
                entries.append(Entry(font: font, width: width))
            }
            lock.unlock()
        }
        return width
    }
}

public final class DynamicCounterTextView : View {
    private static let digitWidthCache = DynamicCounterDigitWidthCache()
    
    public struct Value {
        public let values: [(TextViewLayout, DynamicCounterTextView.Text)]
        public let size: NSSize
        public let numSize: CGFloat
        var offsets: [CGFloat]? = nil
        var rolling: Bool = false
    }
    
    public static func make(for text: String, count: String, font: NSFont, textColor: NSColor, width: CGFloat, onlyFade: Bool = false, kerned: Bool = false, rolling: Bool = false) -> Value {
        var title: [(String, DynamicCounterTextView.Text.Animation, Int)] = []
        if count.isEmpty {
            title = [(text, .crossFade, 0)]
        } else {
            var text = text
            let range = text.nsstring.range(of: count)
            if range.location != NSNotFound {
                title.append((text.nsstring.substring(to: range.location), .crossFade, 0))
                var index: Int = 0
                for _ in range.lowerBound ..< range.upperBound {
                    let symbol = text.nsstring.substring(with: NSMakeRange(range.location + index, 1))
                    let animation: Text.Animation
                    if Int(symbol) != nil {
                        animation = onlyFade ? .crossFade : .numeric
                    } else {
                        animation = .crossFade
                    }
                    title.append((symbol, animation, index + 1))
                    index += 1
                }
                title.append((text.nsstring.substring(from: range.upperBound), .crossFade, range.length + 1))
            } else {
                title.append((text, .crossFade, 0))
                text = ""
            }
        }
        title = title.filter { !$0.0.isEmpty }
        let texts:[DynamicCounterTextView.Text] = title.map {
            return .init(text: .initialize(string: $0.0, color: textColor, font: font), animation: $0.1, index: $0.2)
        }
        
        let layouts = texts.map {
            return (TextViewLayout($0.text, maximumNumberOfLines: 1, truncationType: .end, alignment: .center), $0)
        }
        
        let numeroSize = digitWidthCache.width(for: font)
        
        var mw: CGFloat = width
        for layout in layouts {
            layout.0.measure(width: mw)
            var w = layout.0.layoutSize.width
            if Int(layout.0.attributedString.string) != nil {
                w = max(w, numeroSize)
            }
            mw -= max(w, 4) - 2
        }
        
        let size = layouts.reduce(NSZeroSize, { current, value in
            var current = current
            if value.0.attributedString.string == " " {
                current.width += 4
            } else {
                var w = value.0.layoutSize.width
                if Int(value.0.attributedString.string) != nil {
                    w = max(w, numeroSize)
                }
                current.width += w
            }
            current.height = max(current.height, value.0.layoutSize.height)
            return current
        })
        
        var resultSize = size
        var offsets: [CGFloat]? = nil
        if kerned {
            let full = TextViewLayout(.initialize(string: title.map { $0.0 }.joined(), color: textColor, font: font), maximumNumberOfLines: 1)
            full.measure(width: .greatestFiniteMagnitude)
            if let line = full.lines.first {
                var values: [CGFloat] = []
                var utf16Index = 0
                for segment in title {
                    values.append(CTLineGetOffsetForStringIndex(line.line, utf16Index, nil) + line.frame.minX)
                    utf16Index += segment.0.utf16.count
                }
                offsets = values
                resultSize = NSMakeSize(full.layoutSize.width, max(size.height, full.layoutSize.height))
            }
        }
        return Value(values: layouts, size: resultSize, numSize: numeroSize, offsets: offsets, rolling: rolling)
    }
    
    
    private static let duration: TimeInterval = 0.4
    private static let timingFunction: CAMediaTimingFunctionName = .spring
    
    public struct Text : Hashable, Comparable {
        public enum Animation : Equatable {
            case crossFade
            case numeric
        }
        let text: NSAttributedString
        let animation: Animation
        let index: Int
        
        public init(text: NSAttributedString, animation: Animation, index: Int) {
            self.text = text
            self.animation = animation
            self.index = index
        }
        
        public static func <(lhs: Text, rhs: Text) -> Bool {
            let lhsInt: Int? = Int(lhs.text.string)
            let rhsInt: Int? = Int(rhs.text.string)
            
            if let lhsInt = lhsInt, let rhsInt = rhsInt {
                return lhsInt < rhsInt
            }
            return false
        }
        
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(index)
        }
    }
    
    public var effectiveSubviews: [TextView] {
        return isRolling ? Array(rollingViews.values) : Array(textViews.values)
    }
    
    fileprivate var textViews: [Int : TextView] = [:]
    private var isRolling = false
    fileprivate var rollingViews: [Text : TextView] = [:]
    private var texts: [Text] = []

    public var accessibilityText: String {
        return texts.sorted(by: { $0.index < $1.index }).map { $0.text.string }.joined()
    }

    public override func isAccessibilityElement() -> Bool {
        return TGUIKitAccessibility.isEnabled && !isHidden && !accessibilityText.isEmpty
    }

    public override func accessibilityRole() -> NSAccessibility.Role? {
        return TGUIKitAccessibility.isEnabled ? .staticText : super.accessibilityRole()
    }

    public override func accessibilityValue() -> Any? {
        return TGUIKitAccessibility.isEnabled ? accessibilityText : super.accessibilityValue()
    }

    public override func accessibilityChildren() -> [Any]? {
        return TGUIKitAccessibility.isEnabled ? [] : super.accessibilityChildren()
    }
    private static func numericValue<S: Sequence>(_ texts: S) -> Int where S.Element == Text {
        var digits = ""
        for text in texts {
            if let number = Int(text.text.string) {
                digits += String(number)
            }
        }
        return Int(digits) ?? 0
    }

    public func update(_ value: Value, animated: Bool, reversed: Bool = false) {
        if isRolling != value.rolling {
            for case let view as TextView in subviews {
                view.layer?.removeAllAnimations()
                view.removeFromSuperview()
            }
            textViews.removeAll()
            rollingViews.removeAll()
            texts.removeAll()
            isRolling = value.rolling
        }
        if value.rolling {
            updateRolling(value, animated: animated)
            return
        }

        enum NumericAnimation {
            case forward
            case backward
        }
        let layouts = value.values
        let textChanged = !texts.elementsEqual(layouts, by: { $0 == $1.1 })
        if !textChanged {
            updateRegularLayouts(value, animated: animated)
            return
        }
        var numberAnimation = NumericAnimation.forward
        if animated {
            let previous = Self.numericValue(texts)
            let current = Self.numericValue(layouts.lazy.map { $0.1 })
            numberAnimation = (reversed ? current > previous : current < previous) ? .backward : .forward
        }
        let previousTexts = texts
        texts = layouts.map { $0.1 }

        var replacedIndices = Set<Int>()
        var incomingIndex = 0
        for key in previousTexts {
            guard let textView = textViews[key.index] else { continue }
            while incomingIndex < layouts.count && layouts[incomingIndex].1.index < key.index {
                incomingIndex += 1
            }
            let title = incomingIndex < layouts.count && layouts[incomingIndex].1.index == key.index ? layouts[incomingIndex].1 : nil
            if key != title {
                textViews[key.index] = nil
                if animated {
                    if title != nil {
                        replacedIndices.insert(key.index)
                    }
                    textView.layer?.animateAlpha(from: 1, to: 0, duration: Self.duration - 0.1, timingFunction: Self.timingFunction, removeOnCompletion: false, completion: { [weak textView] _ in
                        textView?.removeFromSuperview()
                    })
                    if (title ?? key).animation == .numeric, title != nil {
                        switch numberAnimation {
                        case .forward:
                            textView.layer?.animatePosition(from: textView.frame.origin, to: NSMakePoint(textView.frame.minX, textView.frame.maxY), timingFunction: Self.timingFunction, removeOnCompletion: false)
                        case .backward:
                            textView.layer?.animatePosition(from: textView.frame.origin, to: NSMakePoint(textView.frame.minX, textView.frame.minY - textView.frame.height), timingFunction: Self.timingFunction, removeOnCompletion: false)
                        }
                    }
                } else {
                    textView.removeFromSuperview()
                }
            }
        }
        var pos: NSPoint = .zero
        for (index, layout) in layouts.enumerated() {
            if let offsets = value.offsets, index < offsets.count {
                pos.x = offsets[index]
            }
            if let view = textViews[layout.1.index] {
                let from = view.frame.origin
                updateRegularLayout(view, layout: layout.0, origin: pos)
                if animated, from != pos {
                    view.layer?.animatePosition(from: NSMakePoint(from.x - pos.x, from.y - pos.y), to: .zero, timingFunction: Self.timingFunction, removeOnCompletion: true, additive: true)
                }
            } else {
                let current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                current.disableBackgroundDrawing = true
                textViews[layout.1.index] = current
                current.update(layout.0, origin: pos)
                addSubview(current)
                if animated {
                    if layout.1.animation == .numeric, replacedIndices.contains(layout.1.index) {
                        switch numberAnimation {
                        case .forward:
                            current.layer?.animatePosition(from: NSMakePoint(pos.x, pos.y - layout.0.layoutSize.height), to: pos, timingFunction: Self.timingFunction)
                        case .backward:
                            current.layer?.animatePosition(from: NSMakePoint(pos.x, pos.y + layout.0.layoutSize.height), to: pos, timingFunction: Self.timingFunction)
                        }
                    }
                    current.layer?.animateAlpha(from: 0, to: 1, duration: Self.duration)
                }
            }
            pos.x += layout.0.attributedString.string == " " ? 4 : layout.0.layoutSize.width
        }
    }

    private func updateRegularLayout(_ view: TextView, layout: TextViewLayout, origin: NSPoint) {
        if let current = view.textLayout,
           current.constrainedWidth == layout.constrainedWidth,
           current.layoutSize == layout.layoutSize,
           current.penFlush == layout.penFlush,
           view.frame.size == layout.layoutSize,
           current.lines.elementsEqual(layout.lines, by: { $0.frame == $1.frame && $0.range == $1.range && $0.penFlush == $1.penFlush && $0.isRTL == $1.isRTL }) {
            if view.frame.origin != origin {
                view.setFrameOrigin(origin)
            }
        } else {
            view.update(layout, origin: origin)
        }
    }

    private func updateRegularLayouts(_ value: Value, animated: Bool) {
        var x: CGFloat = 0
        for (index, layout) in value.values.enumerated() {
            if let offsets = value.offsets, index < offsets.count {
                x = offsets[index]
            }
            let origin = NSMakePoint(x, 0)
            if let view = textViews[layout.1.index] {
                let from = view.frame.origin
                updateRegularLayout(view, layout: layout.0, origin: origin)
                if animated, from != origin {
                    view.layer?.animatePosition(from: NSMakePoint(from.x - origin.x, from.y - origin.y), to: .zero, timingFunction: Self.timingFunction, removeOnCompletion: true, additive: true)
                }
            }
            x += layout.0.attributedString.string == " " ? 4 : layout.0.layoutSize.width
        }
    }

    private static let rollingMotionDuration: Double = 0.4
    private static let rollingAlphaDuration: Double = 0.18
    private static let rollingBlurRadius: CGFloat = 6
    private static let rollingOffset: CGFloat = 0.4
    private static let rollingDelayPerPoint: Double = 0.002

    private func animateRollingBlur(_ layer: CALayer?, from: CGFloat, to: CGFloat, duration: Double, delay: Double, removeOnCompletion: Bool) {
        guard let layer = layer, let blur = ee2_makeBlurFilter() else {
            return
        }
        blur.setValue(to as NSNumber, forKey: "inputRadius")
        layer.filters = [blur]
        layer.animate(from: NSNumber(value: Double(from)), to: NSNumber(value: Double(to)), keyPath: "filters.gaussianBlur.inputRadius", timingFunction: .easeInEaseOut, duration: duration, delay: delay, removeOnCompletion: removeOnCompletion, completion: { [weak layer] _ in
            if to == 0 {
                layer?.filters = nil
            }
        })
    }

    private func updateRolling(_ value: Value, animated: Bool) {
        let layouts = value.values
        let contentChanged = !texts.elementsEqual(layouts, by: { $0 == $1.1 })
        let removed: [Text: TextView]
        if !contentChanged {
            removed = [:]
        } else if !texts.elementsEqual(layouts, by: { $0.text.string == $1.1.text.string }) {
            removed = rollingViews
        } else {
            let valid = Set(layouts.lazy.map { $0.1 })
            removed = rollingViews.filter { !valid.contains($0.key) }
        }
        texts = layouts.map { $0.1 }
        let outFirstX = animated ? removed.values.map { $0.frame.midX }.min() : nil
        for (key, view) in removed {
            rollingViews[key] = nil
            guard animated, let layer = view.layer else {
                view.removeFromSuperview()
                continue
            }
            let delay = Double(max(0, view.frame.midX - (outFirstX ?? view.frame.midX))) * DynamicCounterTextView.rollingDelayPerPoint
            let shift = view.frame.height * DynamicCounterTextView.rollingOffset
            layer.animate(from: NSValue(point: .zero), to: NSValue(point: NSMakePoint(0, -shift)), keyPath: "position", timingFunction: .spring, duration: DynamicCounterTextView.rollingMotionDuration, delay: delay, removeOnCompletion: false, additive: true)
            layer.animate(from: NSNumber(value: 1.0), to: NSNumber(value: 0.01), keyPath: "transform.scale", timingFunction: .spring, duration: DynamicCounterTextView.rollingMotionDuration, delay: delay, removeOnCompletion: false)
            animateRollingBlur(layer, from: 0, to: DynamicCounterTextView.rollingBlurRadius, duration: DynamicCounterTextView.rollingAlphaDuration, delay: delay, removeOnCompletion: false)
            layer.animate(from: NSNumber(value: 1.0), to: NSNumber(value: 0.0), keyPath: "opacity", timingFunction: .easeInEaseOut, duration: DynamicCounterTextView.rollingAlphaDuration, delay: delay, removeOnCompletion: false, completion: { [weak view] _ in
                view?.removeFromSuperview()
            })
        }

        var inFirstX: CGFloat?
        var x: CGFloat = 0
        for (index, layout) in layouts.enumerated() {
            if let offsets = value.offsets, index < offsets.count {
                x = offsets[index]
            }
            let origin = NSMakePoint(x, 0)
            x += layout.0.attributedString.string == " " ? 4 : layout.0.layoutSize.width
            if let view = rollingViews[layout.1] {
                let from = view.frame.origin
                view.update(layout.0, origin: origin)
                if animated, from != origin {
                    view.layer?.animatePosition(from: NSMakePoint(from.x - origin.x, from.y - origin.y), to: .zero, duration: DynamicCounterTextView.rollingMotionDuration, timingFunction: .spring, removeOnCompletion: true, additive: true)
                }
                continue
            }
            let view = TextView()
            view.userInteractionEnabled = false
            view.isSelectable = false
            view.disableBackgroundDrawing = true
            view.update(layout.0, origin: origin)
            addSubview(view)
            rollingViews[layout.1] = view
            guard animated, let layer = view.layer else {
                continue
            }
            let firstX = inFirstX ?? origin.x
            inFirstX = firstX
            let delay = Double(max(0, origin.x - firstX)) * DynamicCounterTextView.rollingDelayPerPoint
            let shift = view.frame.height * DynamicCounterTextView.rollingOffset
            layer.animate(from: NSNumber(value: 0.001), to: NSNumber(value: 1.0), keyPath: "transform.scale", timingFunction: .spring, duration: DynamicCounterTextView.rollingMotionDuration, delay: delay)
            layer.animate(from: NSValue(point: NSMakePoint(0, shift)), to: NSValue(point: .zero), keyPath: "position", timingFunction: .spring, duration: DynamicCounterTextView.rollingMotionDuration, delay: delay, additive: true)
            animateRollingBlur(layer, from: DynamicCounterTextView.rollingBlurRadius, to: 0, duration: 0.2, delay: delay, removeOnCompletion: true)
            layer.animate(from: NSNumber(value: 0.0), to: NSNumber(value: 1.0), keyPath: "opacity", timingFunction: .easeInEaseOut, duration: DynamicCounterTextView.rollingAlphaDuration, delay: delay)
        }
    }
}
