import Foundation
import Cocoa
import QuartzCore
import TGUIKit

private func qrStudioParsePath(_ string: String) -> CGPath {
    let path = CGMutablePath()
    var numbers: [CGFloat] = []
    var command: Character?
    var current = ""

    func flushNumber() {
        if !current.isEmpty, let value = Double(current) {
            numbers.append(CGFloat(value))
        }
        current = ""
    }

    func apply() {
        guard let command = command else {
            return
        }
        switch command {
        case "M":
            var i = 0
            while i + 1 < numbers.count {
                if i == 0 {
                    path.move(to: CGPoint(x: numbers[i], y: numbers[i + 1]))
                } else {
                    path.addLine(to: CGPoint(x: numbers[i], y: numbers[i + 1]))
                }
                i += 2
            }
        case "L":
            var i = 0
            while i + 1 < numbers.count {
                path.addLine(to: CGPoint(x: numbers[i], y: numbers[i + 1]))
                i += 2
            }
        case "C":
            var i = 0
            while i + 5 < numbers.count {
                path.addCurve(to: CGPoint(x: numbers[i + 4], y: numbers[i + 5]), control1: CGPoint(x: numbers[i], y: numbers[i + 1]), control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
                i += 6
            }
        case "Z":
            path.closeSubpath()
        default:
            break
        }
        numbers.removeAll()
    }

    for character in string {
        if character.isLetter {
            flushNumber()
            apply()
            command = character
        } else if character == "-" {
            flushNumber()
            current.append(character)
        } else if character == " " || character == "," {
            flushNumber()
        } else if character == "." && current.contains(".") {
            flushNumber()
            current.append(character)
        } else {
            current.append(character)
        }
    }
    flushNumber()
    apply()
    return path
}

private enum QrStudioStarGlyph {
    static let star = qrStudioParsePath("M5.72902 8.83283L3.37965 10.2721C3.13537 10.4217 2.81601 10.345 2.66636 10.1007C2.59327 9.9814 2.57148 9.83762 2.60593 9.70201L2.96961 8.27055C3.10089 7.75382 3.45449 7.32187 3.93512 7.09112L6.49815 5.86056C6.61764 5.80319 6.668 5.65982 6.61063 5.54033C6.56417 5.44356 6.45911 5.38941 6.35334 5.40772L3.50035 5.90164C2.9204 6.00205 2.32567 5.8419 1.87456 5.46386L0.973277 4.70856C0.753702 4.52455 0.724871 4.19737 0.908881 3.9778C0.998378 3.871 1.12707 3.8047 1.26599 3.79383L4.01967 3.57833C4.21421 3.56311 4.38375 3.43999 4.45843 3.25971L5.52076 0.695335C5.6304 0.430662 5.93384 0.304986 6.19851 0.414629C6.3256 0.467277 6.42657 0.568248 6.47922 0.695335L7.54154 3.25971C7.61622 3.43999 7.78576 3.56311 7.9803 3.57833L10.7491 3.79502C11.0347 3.81737 11.2481 4.06702 11.2258 4.35263C11.215 4.49003 11.1501 4.6175 11.0452 4.70691L8.93352 6.50715C8.78486 6.63388 8.72001 6.83338 8.76573 7.02329L9.41492 9.72017C9.48196 9.99869 9.31052 10.2788 9.03199 10.3459C8.89816 10.3781 8.75701 10.3558 8.63962 10.2839L6.27096 8.83283C6.10467 8.73097 5.8953 8.73097 5.72902 8.83283Z")
    static let slashed = qrStudioParsePath("M5.52052 0.695024C5.63025 0.430602 5.93372 0.305263 6.19826 0.41475C6.32528 0.467369 6.42684 0.568033 6.47951 0.695024L7.54201 3.25948C7.61673 3.43966 7.78601 3.56262 7.98048 3.57784L10.749 3.79463C11.0345 3.81702 11.2477 4.06682 11.2256 4.35225C11.2149 4.48955 11.1497 4.61734 11.0449 4.70674L8.93361 6.50655C8.78502 6.63322 8.72004 6.8333 8.76564 7.02315L8.77638 7.06905L11.3535 9.6462C11.5487 9.84141 11.5486 10.158 11.3535 10.3532C11.1583 10.5485 10.8418 10.5485 10.6465 10.3532L1.6465 1.35323C1.45137 1.15795 1.45128 0.841412 1.6465 0.646195C1.84173 0.451131 2.15831 0.451121 2.35353 0.646195L4.60744 2.9001L5.52052 0.695024ZM9.26955 10.2106C9.20511 10.2734 9.12597 10.3228 9.03224 10.3454C8.89844 10.3776 8.75703 10.3558 8.63966 10.2839L6.2715 8.83272C6.10536 8.73096 5.89571 8.73111 5.72951 8.83272L3.3799 10.2722C3.13562 10.4218 2.81567 10.3446 2.66603 10.1003C2.59316 9.98108 2.57206 9.8373 2.60646 9.70186L2.96974 8.27022C3.10109 7.75364 3.45504 7.32124 3.93556 7.09053L5.43068 6.37178L9.26955 10.2106ZM4.74416 5.68526L3.50002 5.90108C2.92028 6.00133 2.326 5.84141 1.87502 5.46358L0.973648 4.7087C0.754138 4.52467 0.725205 4.1968 0.909195 3.97725C0.998577 3.87085 1.12711 3.80462 1.26564 3.79366L2.73634 3.67745L4.74416 5.68526Z")
}

private final class QrStudioPillLabelView: View {
    struct Content: Equatable {
        var slashed: Bool
        var title: String
        var detail: String
    }

    static let padding: CGFloat = 12.0
    private static let starSide: CGFloat = 12.0
    private static let starSpacing: CGFloat = 3.0
    private static let dotSide: CGFloat = 3.0
    private static let dotSpacing: CGFloat = 5.0
    private static let titleFont: NSFont = .medium(12.0)
    private static let detailFont: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)

    private let starLayer = SimpleShapeLayer()
    private let titleView = TextView()
    private let dotLayer = SimpleLayer()
    private let detailView = TextView()
    private var content: Content?
    private var color: NSColor?
    private var titleLayout: TextViewLayout?
    private var detailLayout: TextViewLayout?

    override init() {
        super.init(frame: .zero)
        self.setup()
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        self.isEventLess = true
        self.userInteractionEnabled = false
        self.layer?.masksToBounds = false
        self.starLayer.anchorPoint = CGPoint()
        self.starLayer.fillRule = .evenOdd
        self.layer?.addSublayer(self.starLayer)
        for textView in [self.titleView, self.detailView] {
            textView.isSelectable = false
            textView.userInteractionEnabled = false
            textView.isEventLess = true
            self.addSubview(textView)
        }
        self.dotLayer.anchorPoint = CGPoint()
        self.layer?.addSublayer(self.dotLayer)
    }

    private static func textLayout(_ text: String, font: NSFont, color: NSColor) -> TextViewLayout {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: -0.24])
        let layout = TextViewLayout(attributed, maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        return layout
    }

    private static func title(_ content: Content, color: NSColor) -> TextViewLayout {
        return self.textLayout(content.title, font: content.slashed ? self.titleFont : .normal(12.0), color: color)
    }

    private static func detail(_ content: Content, color: NSColor) -> TextViewLayout {
        return self.textLayout(content.detail, font: content.slashed ? self.detailFont : .normal(12.0), color: color)
    }

    private static func width(title: TextViewLayout, detail: TextViewLayout, slashed: Bool) -> CGFloat {
        let spacing = slashed ? self.starSpacing + self.dotSpacing * 2.0 + self.dotSide : self.starSpacing * 2.0
        return self.starSide + ceil(title.layoutSize.width) + spacing + ceil(detail.layoutSize.width)
    }

    static func width(_ content: Content) -> CGFloat {
        return self.width(title: self.title(content, color: .white), detail: self.detail(content, color: .white), slashed: content.slashed)
    }

    func update(content: Content, color: NSColor, size: CGSize, transition: ContainedViewLayoutTransition) {
        let colorChanged = self.color.map { !$0.isEqual(color) } ?? true
        if self.content?.slashed != content.slashed || colorChanged {
            self.starLayer.path = content.slashed ? QrStudioStarGlyph.slashed : QrStudioStarGlyph.star
            self.starLayer.fillColor = color.cgColor
        }
        if self.content?.title != content.title || self.content?.slashed != content.slashed || colorChanged || self.titleLayout == nil {
            let layout = QrStudioPillLabelView.title(content, color: color)
            self.titleLayout = layout
            self.titleView.update(layout)
        }
        if self.content?.detail != content.detail || self.content?.slashed != content.slashed || colorChanged || self.detailLayout == nil {
            let layout = QrStudioPillLabelView.detail(content, color: color)
            self.detailLayout = layout
            self.detailView.update(layout)
        }
        self.dotLayer.backgroundColor = color.withAlphaComponent(color.alphaComponent * 0.5).cgColor
        self.dotLayer.isHidden = !content.slashed
        self.content = content
        self.color = color

        guard let titleLayout = self.titleLayout, let detailLayout = self.detailLayout else {
            return
        }

        let midY = size.height * 0.5
        var x = floor((size.width - QrStudioPillLabelView.width(title: titleLayout, detail: detailLayout, slashed: content.slashed)) * 0.5)
        let starSide = QrStudioPillLabelView.starSide

        func place(_ textView: TextView, layout: TextViewLayout) {
            let textSize = CGSize(width: ceil(layout.layoutSize.width), height: ceil(layout.layoutSize.height))
            transition.updateFrame(view: textView, frame: CGRect(x: x, y: floorToScreenPixels((size.height - textSize.height) * 0.5), width: textSize.width, height: textSize.height))
            x += textSize.width
        }
        if !content.slashed {
            place(self.titleView, layout: titleLayout)
            x += QrStudioPillLabelView.starSpacing
        }
        transition.updateFrame(layer: self.starLayer, frame: CGRect(x: x, y: midY - starSide * 0.5, width: starSide, height: starSide))
        x += starSide + QrStudioPillLabelView.starSpacing
        if content.slashed {
            place(self.titleView, layout: titleLayout)
            x += QrStudioPillLabelView.dotSpacing
            let dotSide = QrStudioPillLabelView.dotSide
            transition.updateFrame(layer: self.dotLayer, frame: CGRect(x: x, y: midY - dotSide * 0.5, width: dotSide, height: dotSide))
            self.dotLayer.cornerRadius = dotSide * 0.5
            x += dotSide + QrStudioPillLabelView.dotSpacing
        }
        place(self.detailView, layout: detailLayout)
    }
}

final class QrStudioCodePillView: View {
    struct Texts: Equatable {
        let free: String
        let removeFee: String
        let permanent: String
        let expiresIn: (String) -> String

        static func ==(lhs: Texts, rhs: Texts) -> Bool {
            return lhs.free == rhs.free && lhs.removeFee == rhs.removeFee && lhs.permanent == rhs.permanent
        }
    }

    static let height: CGFloat = 24.0
    static let resizeDuration: Double = 0.5
    static let resizeDamping: CGFloat = 0.82

    var tapPaid: (() -> Void)?
    var openMenu: ((NSView) -> Void)?
    var needsNextCode: (() -> Void)?

    private let containerView = View()
    private let glass = LiquidGlassView(frame: .zero, cornerRadius: QrStudioCodePillView.height * 0.5, hasShadow: false, hasBorder: true, tintAlpha: 0.0, forceAppearance: .forceDark)
    private let contentView = View()
    private let glyphLabel = QrStudioPillLabelView()
    private let foregroundView = View()
    private let whiteClipView = View()
    private let whiteMask = SimpleShapeLayer()
    private let flashView = View()
    private let flashMask = SimpleShapeLayer()
    private let inkLabel = QrStudioPillLabelView()
    private let inkMask = SimpleShapeLayer()
    private let particlesLayer = SimpleLayer()
    private let haloLayer = SimpleShapeLayer()
    private var coreLayers: [SimpleShapeLayer] = []

    private var state = QrStudioCodeState()
    private var price: Int64 = 0
    private var ink = QrStudioColor(0.5, 0.5, 0.5)
    private var isLight = false
    private var texts: Texts?
    private var shatter: QrStudioShatter?
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var lastShapeTick: Double = -1.0
    private var isPressed = false
    private var isMouseDown = false
    private var pillWidth: CGFloat = 0.0
    private var appliedSize = CGSize()
    private var appliedSizeOnce = false

    private static let heatLevels = 3
    private static let alphaLevels = 5
    private static let particleMargin = CGSize(width: 90.0, height: 76.0)

    override init() {
        super.init(frame: .zero)
        self.setup()
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        self.layer?.masksToBounds = false

        self.containerView.layer?.masksToBounds = false
        self.addSubview(self.containerView)

        self.containerView.addSubview(self.glass)

        self.contentView.isEventLess = true
        self.contentView.layer?.masksToBounds = false
        self.containerView.addSubview(self.contentView)

        self.contentView.addSubview(self.glyphLabel)

        self.whiteClipView.isEventLess = true
        self.whiteClipView.layer?.masksToBounds = true
        self.whiteClipView.layer?.cornerRadius = QrStudioCodePillView.height * 0.5
        self.whiteClipView.layer?.mask = self.whiteMask
        self.contentView.addSubview(self.whiteClipView)

        self.flashView.isEventLess = true
        self.flashView.backgroundColor = .white
        self.flashView.layer?.masksToBounds = true
        self.flashView.layer?.cornerRadius = QrStudioCodePillView.height * 0.5
        self.flashView.layer?.mask = self.flashMask
        self.flashView.layer?.opacity = 0.0
        self.contentView.addSubview(self.flashView)

        self.inkLabel.layer?.mask = self.inkMask
        self.contentView.addSubview(self.inkLabel)

        self.foregroundView.isEventLess = true
        self.foregroundView.layer?.masksToBounds = false
        self.containerView.addSubview(self.foregroundView)

        self.particlesLayer.isHidden = true
        self.foregroundView.layer?.addSublayer(self.particlesLayer)
        self.haloLayer.compositingFilter = "plusL"
        self.particlesLayer.addSublayer(self.haloLayer)
        for _ in 0 ..< QrStudioCodePillView.heatLevels * QrStudioCodePillView.alphaLevels {
            let layer = SimpleShapeLayer()
            self.particlesLayer.addSublayer(layer)
            self.coreLayers.append(layer)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !self.isHidden, self.userInteractionEnabled, self.alphaValue > 0.01, (self.layer?.opacity ?? 1.0) > 0.01 else {
            return nil
        }
        let local = self.convert(point, from: self.superview)
        return self.bounds.insetBy(dx: -10.0, dy: -10.0).contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard self.userInteractionEnabled else {
            super.mouseDown(with: event)
            return
        }
        self.isMouseDown = true
        if !self.state.removeFee {
            self.setPressed(true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard self.isMouseDown else {
            super.mouseUp(with: event)
            return
        }
        self.isMouseDown = false
        self.setPressed(false)
        let point = self.convert(event.locationInWindow, from: nil)
        guard self.userInteractionEnabled, self.bounds.insetBy(dx: -10.0, dy: -10.0).contains(point) else {
            return
        }
        if self.state.removeFee {
            self.openMenu?(self)
        } else {
            self.tapPaid?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard self.userInteractionEnabled, self.state.removeFee else {
            super.rightMouseDown(with: event)
            return
        }
        self.openMenu?(self)
    }

    private static func scaleTransform(_ scale: CGFloat, layer: CALayer) -> CATransform3D {
        let dx = layer.bounds.width * (0.5 - layer.anchorPoint.x)
        let dy = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        var transform = CATransform3DMakeTranslation(dx, dy, 0.0)
        transform = CATransform3DScale(transform, scale, scale, 1.0)
        transform = CATransform3DTranslate(transform, -dx, -dy, 0.0)
        return transform
    }

    private func setPressed(_ isPressed: Bool) {
        guard self.isPressed != isPressed, let layer = self.layer else {
            return
        }
        self.isPressed = isPressed
        let scale: CGFloat = isPressed ? 0.93 : 1.0
        let from = layer.presentation()?.transform ?? QrStudioCodePillView.scaleTransform(isPressed ? 1.0 : 0.93, layer: layer)
        let animation = CASpringAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: QrStudioCodePillView.scaleTransform(scale, layer: layer))
        animation.stiffness = 438.0
        animation.damping = 23.0
        animation.duration = 0.5
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = !isPressed
        layer.add(animation, forKey: "press")
    }

    func animatePourBump() {
        guard let layer = self.containerView.layer else {
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        let scales: [CGFloat] = [1.0, 1.0, 1.08, 1.0]
        animation.values = scales.map { NSValue(caTransform3D: QrStudioCodePillView.scaleTransform($0, layer: layer)) }
        animation.keyTimes = [0.0, NSNumber(value: QrStudioBurn.refill / 0.74), NSNumber(value: (QrStudioBurn.refill + 0.06) / 0.74), 1.0]
        animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        animation.duration = 0.74
        layer.add(animation, forKey: "pourBump")
    }

    func startShatter(at time: Double) {
        self.startShatter(at: time, level: QrStudioBurn.level(self.state, at: time))
    }

    func startShatter(at time: Double, level: Double) {
        guard level > 0.005, self.pillWidth > 0.0 else {
            return
        }
        self.shatter = QrStudioShatter(at: time, width: self.pillWidth, level: level)
        self.updateDisplayLink()
    }

    private func labelContent(at time: Double) -> QrStudioPillLabelView.Content? {
        guard let texts = self.texts else {
            return nil
        }
        if !self.state.removeFee {
            let text = String(format: texts.removeFee, "\(self.price)")
            let parts = text.components(separatedBy: "⭐")
            return QrStudioPillLabelView.Content(slashed: false, title: parts[0].trimmingCharacters(in: .whitespaces), detail: parts.dropFirst().joined().trimmingCharacters(in: .whitespaces))
        }
        let detail: String
        if self.state.expires {
            detail = texts.expiresIn(QrStudioBurn.clock(self.state.remaining(at: time)))
        } else {
            detail = texts.permanent
        }
        return QrStudioPillLabelView.Content(slashed: true, title: texts.free, detail: detail)
    }

    private var glyphColor: NSColor {
        return self.isLight ? QrStudioColor(0.1, 0.1, 0.1).nsColor : QrStudioColor(0.96, 0.96, 0.96).nsColor
    }

    private var inkLabelColor: NSColor {
        return self.isLight ? QrStudioColor(1.0, 1.0, 1.0).nsColor : self.ink.nsColor
    }

    private func updateLabels(at time: Double, size: CGSize, transition: ContainedViewLayoutTransition) {
        guard let content = self.labelContent(at: time) else {
            return
        }
        self.glyphLabel.update(content: content, color: self.glyphColor, size: size, transition: transition)
        self.inkLabel.update(content: content, color: self.inkLabelColor, size: size, transition: transition)
    }

    private(set) var isTaken = false

    func setTaken(_ isTaken: Bool, animated: Bool = true) {
        guard self.isTaken != isTaken, let layer = self.foregroundView.layer else {
            return
        }
        self.isTaken = isTaken
        let alpha: Float = isTaken ? 0.0 : 1.0
        guard animated else {
            layer.removeAllAnimations()
            layer.opacity = alpha
            return
        }
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = alpha
        layer.animate(from: NSNumber(value: from), to: NSNumber(value: alpha), keyPath: "opacity", timingFunction: .easeInEaseOut, duration: isTaken ? 0.16 / 3.0 : 0.25, delay: isTaken ? 0.0 : 0.2)
    }

    func update(state: QrStudioCodeState, price: Int64, ink: QrStudioColor, isLight: Bool, texts: Texts, transition: ContainedViewLayoutTransition) -> CGSize {
        let previousState = self.state
        let colorsChanged = self.appliedSizeOnce && (self.isLight != isLight || self.ink != ink)
        if self.appliedSizeOnce && self.isLight != isLight && transition.isAnimated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.45
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.glass.layer?.add(fade, forKey: "appearance")
        }
        self.state = state
        self.price = price
        self.ink = ink
        self.isLight = isLight
        self.texts = texts

        let time = QrStudioClock.now
        let contentWidth = self.labelContent(at: time).map { QrStudioPillLabelView.width($0) } ?? 0.0
        let size = CGSize(width: ceil(contentWidth) + QrStudioPillLabelView.padding * 2.0, height: QrStudioCodePillView.height)
        self.pillWidth = size.width

        if previousState.removeFee != state.removeFee || previousState.expires != state.expires {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            self.glyphLabel.layer?.add(fade, forKey: "text")
            self.inkLabel.layer?.add(fade, forKey: "text")
        }
        if colorsChanged && transition.isAnimated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.35
            self.glyphLabel.layer?.add(fade, forKey: "colors")
            self.inkLabel.layer?.add(fade, forKey: "colors")
        }

        let sizeChanged = self.appliedSize != size
        self.appliedSize = size
        if sizeChanged && transition.isAnimated && self.appliedSizeOnce {
            self.applyLayout(size: size, time: time, transition: .animated(duration: QrStudioCodePillView.resizeDuration, curve: .spring))
        } else {
            self.applyLayout(size: size, time: time, transition: transition)
        }
        self.appliedSizeOnce = true

        self.lastShapeTick = -1.0
        self.applyFrame(time: time)
        self.updateDisplayLink()
        return size
    }

    override func layout() {
        super.layout()
        let size = self.bounds.size
        guard self.appliedSizeOnce, size.width > 0.0, size != self.appliedSize else {
            return
        }
        self.appliedSize = size
        self.pillWidth = size.width
        let time = QrStudioClock.now
        self.applyLayout(size: size, time: time, transition: .immediate)
        self.lastShapeTick = -1.0
        self.applyFrame(time: time)
    }

    private func applyLayout(size: CGSize, time: Double, transition: ContainedViewLayoutTransition) {
        let isLight = self.isLight
        let ink = self.ink
        let bounds = CGRect(origin: CGPoint(), size: size)

        transition.updateFrame(view: self.containerView, frame: bounds)
        let appearance: LiquidGlassAppearance = isLight ? .forceLight : .forceDark
        if self.glass.forceAppearance != appearance {
            self.glass.forceAppearance = appearance
            self.glass.updateLocalizationAndTheme(theme: presentation)
        }
        self.glass.cornerRadius = size.height * 0.5
        transition.updateFrame(view: self.glass, frame: bounds)
        self.glass.updateLayout(size: size, transition: transition)
        transition.updateFrame(view: self.contentView, frame: bounds)
        transition.updateFrame(view: self.glyphLabel, frame: bounds)

        let tint = isLight ? ink.nsColor.withAlphaComponent(0.85) : QrStudioColor(1.0, 1.0, 1.0).nsColor.withAlphaComponent(0.82)
        transition.updateFrame(view: self.foregroundView, frame: bounds)
        transition.updateFrame(view: self.whiteClipView, frame: bounds)
        self.whiteClipView.layer?.cornerRadius = size.height * 0.5
        self.whiteClipView.backgroundColor = tint
        transition.updateFrame(view: self.inkLabel, frame: bounds)
        self.updateLabels(at: time, size: size, transition: transition)
        transition.updateFrame(view: self.flashView, frame: bounds)
        self.flashView.layer?.cornerRadius = size.height * 0.5

        let margin = QrStudioCodePillView.particleMargin
        self.particlesLayer.frame = bounds.insetBy(dx: -margin.width, dy: -margin.height)
    }

    var isActive: Bool = true {
        didSet {
            if self.isActive != oldValue {
                self.updateDisplayLink()
            }
        }
    }

    private var needsDisplayLink: Bool {
        if let shatter = self.shatter, QrStudioClock.now - shatter.at < QrStudioShatter.duration {
            return true
        }
        return self.isActive && self.state.removeFee && self.state.expires && self.window != nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateDisplayLink()
    }

    private func updateDisplayLink() {
        if self.needsDisplayLink {
            if self.displayLink == nil {
                self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60), { [weak self] _ in
                    self?.tick()
                })
            }
        } else if let displayLink = self.displayLink {
            displayLink.invalidate()
            self.displayLink = nil
        }
    }

    private func tick() {
        let time = QrStudioClock.now
        if self.state.needsNextCode(at: time) {
            self.needsNextCode?()
        }
        if let shatter = self.shatter, time - shatter.at >= QrStudioShatter.duration {
            self.shatter = nil
        }
        self.applyFrame(time: time)
        self.updateDisplayLink()
    }

    private func applyFrame(time: Double) {
        let size = CGSize(width: self.pillWidth, height: QrStudioCodePillView.height)
        guard size.width > 0.0 else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let rect = CGRect(origin: CGPoint(), size: size)
        let pouring = QrStudioBurn.isPouring(self.state, at: time)
        let shapeTick = pouring ? time : floor(time * 20.0) / 20.0
        if shapeTick != self.lastShapeTick {
            self.lastShapeTick = shapeTick
            let front = QrStudioBurn.front(self.state, width: size.width, at: shapeTick)
            let path = QrStudioBurn.cutPath(front: front, rect: rect, time: shapeTick, liquid: QrStudioBurn.liquid(self.state, at: shapeTick))
            self.whiteMask.path = path
            self.inkMask.path = path
            self.flashMask.path = path
            let hasWhite = path != nil
            self.whiteClipView.isHidden = !hasWhite
            self.inkLabel.isHidden = !hasWhite

            if self.state.removeFee && self.state.expires {
                self.updateLabels(at: time, size: size, transition: .immediate)
            }
        }

        if let shatter = self.shatter {
            let since = time - shatter.at
            let snap = Float(max(0.0, 1.0 - since / 0.06))
            self.whiteClipView.layer?.opacity = snap
            self.inkLabel.layer?.opacity = snap
        } else {
            self.whiteClipView.layer?.opacity = 1.0
            self.inkLabel.layer?.opacity = 1.0
        }
        self.flashView.layer?.opacity = Float(0.7 * QrStudioBurn.flash(self.state, at: time))

        var particles = QrStudioBurn.timerParticles(self.state, pill: size, at: time)
        if let shatter = self.shatter {
            particles.append(contentsOf: QrStudioBurn.shatterParticles(shatter, at: time))
        }
        self.drawParticles(particles)

        CATransaction.commit()
    }

    private func drawParticles(_ particles: [QrStudioParticle]) {
        self.particlesLayer.isHidden = particles.isEmpty
        guard !particles.isEmpty else {
            return
        }
        let margin = QrStudioCodePillView.particleMargin
        let heatLevels = QrStudioCodePillView.heatLevels
        let alphaLevels = QrStudioCodePillView.alphaLevels
        let halo = CGMutablePath()
        var cores: [CGMutablePath] = []
        for _ in 0 ..< heatLevels * alphaLevels {
            cores.append(CGMutablePath())
        }
        var haloAlpha = 0.0
        for particle in particles {
            let rect = CGRect(x: particle.x + margin.width - particle.radius, y: particle.y + margin.height - particle.radius, width: particle.radius * 2.0, height: particle.radius * 2.0)
            if particle.halo {
                halo.addEllipse(in: rect)
                haloAlpha = max(haloAlpha, particle.alpha)
            } else {
                let heatIndex = max(0, min(heatLevels - 1, Int(particle.heat * Double(heatLevels))))
                let alphaIndex = max(0, min(alphaLevels - 1, Int(particle.alpha * Double(alphaLevels))))
                cores[heatIndex * alphaLevels + alphaIndex].addEllipse(in: rect)
            }
        }
        let hot = self.isLight ? self.ink.pastel : QrStudioColor(1.0, 1.0, 1.0)
        let ash = self.isLight ? self.ink : QrStudioColor(1.0, 1.0, 1.0)
        self.haloLayer.frame = self.particlesLayer.bounds
        self.haloLayer.path = halo
        self.haloLayer.fillColor = hot.cgColor
        self.haloLayer.opacity = Float(min(1.0, haloAlpha * 2.0))
        self.haloLayer.compositingFilter = self.isLight ? nil : "plusL"
        for heatIndex in 0 ..< heatLevels {
            let heat = (Double(heatIndex) + 0.5) / Double(heatLevels)
            let tone = QrStudioColor.mix(ash, hot, CGFloat(heat))
            for alphaIndex in 0 ..< alphaLevels {
                let layer = self.coreLayers[heatIndex * alphaLevels + alphaIndex]
                layer.frame = self.particlesLayer.bounds
                layer.path = cores[heatIndex * alphaLevels + alphaIndex]
                layer.fillColor = tone.cgColor
                layer.opacity = Float((Double(alphaIndex) + 0.5) / Double(alphaLevels))
            }
        }
    }
}
