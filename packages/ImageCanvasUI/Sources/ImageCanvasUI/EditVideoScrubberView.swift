import Cocoa
import TGUIKit
import Localization

private final class EditVideoTrimFrameView: View {
    var color: NSColor = .white {
        didSet {
            if color != oldValue {
                needsDisplay = true
            }
        }
    }
    private let lineWidth: CGFloat = 1.5

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            needsDisplay = true
        }
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let radius = EditVideoScrubberView.radius
        guard bounds.width >= radius * 2, bounds.height >= radius * 2 else {
            return
        }
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        let inner = bounds.insetBy(dx: EditVideoScrubberView.handleWidth - 1, dy: lineWidth)
        if inner.width >= 4, inner.height >= 4 {
            ctx.setBlendMode(.clear)
            ctx.addPath(CGPath(roundedRect: inner, cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.fillPath()
        }
    }
}

final class EditVideoScrubberView: View {
    static let height: CGFloat = 48
    static let stripHeight: CGFloat = 40
    static let radius: CGFloat = 9
    static let handleWidth: CGFloat = 12
    private static let trimmingColor = EditVideoToolsView.color(0xf8d74a)
    private static let hitSlop: CGFloat = 12
    private static let snapDistance: CGFloat = 3

    private enum Drag {
        case left(originX: CGFloat, value: Double)
        case right(originX: CGFloat, value: Double)
        case seek
    }

    private let strip = View()
    private let thumbnails = View()
    private let curtainLeft = View()
    private let curtainRight = View()
    private let trimFrame = EditVideoTrimFrameView()
    private let leftGrip = View()
    private let rightGrip = View()
    private let playhead = View()

    private(set) var duration: Double = 0
    private(set) var trimStart: Double = 0
    private(set) var trimEnd: Double = 0
    private(set) var position: Double = 0
    private var drag: Drag?

    var minimumDuration: Double = 1.0
    var isTrimmingEnabled: Bool = true {
        didSet {
            needsLayout = true
        }
    }

    var onBeginTrimming: (() -> Void)?
    var onTrim: ((Double, Double, Bool) -> Void)?
    var onEndTrimming: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onEndSeeking: (() -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        strip.layer?.cornerRadius = EditVideoScrubberView.radius
        strip.layer?.masksToBounds = true
        strip.backgroundColor = NSColor.white.withAlphaComponent(0.1)
        strip.isEventLess = true
        thumbnails.isEventLess = true
        strip.addSubview(thumbnails)
        for curtain in [curtainLeft, curtainRight] {
            curtain.isEventLess = true
            curtain.backgroundColor = NSColor.black.withAlphaComponent(0.8)
            strip.addSubview(curtain)
        }
        for view in [trimFrame, leftGrip, rightGrip, playhead] {
            view.isEventLess = true
        }
        for grip in [leftGrip, rightGrip] {
            grip.backgroundColor = NSColor.black.withAlphaComponent(0.8)
            grip.layer?.cornerRadius = 1
        }
        playhead.backgroundColor = .white
        playhead.layer?.cornerRadius = 1
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 3
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = .zero
        playhead.shadow = shadow

        addSubview(strip)
        addSubview(trimFrame)
        trimFrame.addSubview(leftGrip)
        trimFrame.addSubview(rightGrip)
        addSubview(playhead)
        setAccessibilityLabel(strings().voiceOverMediaTrimmedRange)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(duration: Double, trimStart: Double, trimEnd: Double, position: Double) {
        self.duration = duration
        if drag == nil {
            self.trimStart = trimStart
            self.trimEnd = trimEnd
        }
        self.position = position
        updateColors()
        needsLayout = true
    }

    func setPosition(_ position: Double) {
        self.position = position
        layoutPlayhead()
    }

    func setThumbnails(_ images: [CGImage], width: CGFloat) {
        while thumbnails.subviews.count > images.count {
            thumbnails.subviews.last?.removeFromSuperview()
        }
        while thumbnails.subviews.count < images.count {
            let view = ImageView()
            view.isEventLess = true
            view.isAccessibilityDecorative = true
            view.contentGravity = .resizeAspectFill
            view.layer?.masksToBounds = true
            thumbnails.addSubview(view)
        }
        for (i, image) in images.enumerated() {
            if let view = thumbnails.subviews[i] as? ImageView {
                view.image = image
                view.frame = NSMakeRect(CGFloat(i) * width, 0, width, EditVideoScrubberView.stripHeight)
            }
        }
    }

    var stripWidth: CGFloat {
        return max(1, frame.width)
    }

    private var stripRect: NSRect {
        return NSMakeRect(0, floor((frame.height - EditVideoScrubberView.stripHeight) / 2), stripWidth, EditVideoScrubberView.stripHeight)
    }

    private var timelineRect: NSRect {
        return stripRect.insetBy(dx: EditVideoScrubberView.handleWidth, dy: 0)
    }

    private var leftHandleRect: NSRect {
        return NSMakeRect(x(for: trimStart) - EditVideoScrubberView.handleWidth, stripRect.minY, EditVideoScrubberView.handleWidth, stripRect.height)
    }

    private var rightHandleRect: NSRect {
        return NSMakeRect(x(for: trimEnd), stripRect.minY, EditVideoScrubberView.handleWidth, stripRect.height)
    }

    private func x(for value: Double) -> CGFloat {
        guard duration > 0 else {
            return timelineRect.minX
        }
        return timelineRect.minX + timelineRect.width * CGFloat(min(1, max(0, value / duration)))
    }

    private func value(for x: CGFloat) -> Double {
        let rect = timelineRect
        return Double(min(1, max(0, (x - rect.minX) / rect.width))) * duration
    }

    private var isTrimmed: Bool {
        return duration > 0 && (trimStart > 0.01 || trimEnd < duration - 0.01)
    }

    private func updateColors() {
        let active = drag.map { drag -> Bool in
            if case .seek = drag {
                return false
            }
            return true
        } ?? false
        let color: NSColor = (active || isTrimmed) ? EditVideoScrubberView.trimmingColor : .white
        trimFrame.color = color
    }

    private func layoutPlayhead() {
        let rect = timelineRect
        let clamped = min(trimEnd, max(trimStart, position))
        let px = min(x(for: trimEnd), max(x(for: trimStart), x(for: clamped)))
        playhead.frame = NSMakeRect(floor(px - 1), 0, 2, frame.height)
        let hidden: Bool
        if let drag = drag, case .seek = drag {
            hidden = false
        } else {
            hidden = drag != nil
        }
        playhead.isHidden = hidden || rect.width <= 1
    }

    override func layout() {
        super.layout()
        let rect = stripRect
        strip.frame = rect
        thumbnails.frame = strip.bounds
        let startX = x(for: trimStart)
        let endX = x(for: trimEnd)
        curtainLeft.frame = NSMakeRect(0, 0, max(0, startX - 1), rect.height)
        curtainRight.frame = NSMakeRect(endX + 1, 0, max(0, rect.width - endX - 1), rect.height)
        let handle = EditVideoScrubberView.handleWidth
        trimFrame.frame = NSMakeRect(startX - handle, rect.minY, endX - startX + handle * 2, rect.height)
        let gripX = (handle - 1 - 2) / 2
        leftGrip.frame = NSMakeRect(gripX, floor((rect.height - 11) / 2), 2, 11)
        rightGrip.frame = NSMakeRect(trimFrame.frame.width - gripX - 2, leftGrip.frame.minY, 2, 11)
        trimFrame.isHidden = !isTrimmingEnabled
        curtainLeft.isHidden = !isTrimmingEnabled
        curtainRight.isHidden = !isTrimmingEnabled
        layoutPlayhead()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isTrimmingEnabled else {
            return
        }
        let slop = EditVideoScrubberView.hitSlop
        addCursorRect(leftHandleRect.insetBy(dx: -slop / 2, dy: 0), cursor: .resizeLeftRight)
        addCursorRect(rightHandleRect.insetBy(dx: -slop / 2, dy: 0), cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        guard duration > 0 else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let slop = EditVideoScrubberView.hitSlop
        let leftArea = leftHandleRect.insetBy(dx: -slop, dy: -slop)
        let rightArea = rightHandleRect.insetBy(dx: -slop, dy: -slop)
        let inLeft = isTrimmingEnabled && leftArea.contains(point)
        let inRight = isTrimmingEnabled && rightArea.contains(point)
        if inLeft && (!inRight || abs(point.x - leftHandleRect.midX) <= abs(point.x - rightHandleRect.midX)) {
            drag = .left(originX: point.x, value: trimStart)
            onBeginTrimming?()
        } else if inRight {
            drag = .right(originX: point.x, value: trimEnd)
            onBeginTrimming?()
        } else if point.x >= x(for: trimStart) - 2 && point.x <= x(for: trimEnd) + 2 {
            drag = .seek
            seek(at: point.x)
        } else {
            return
        }
        updateColors()
        needsLayout = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag = drag, duration > 0 else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let perPoint = duration / Double(timelineRect.width)
        let minimum = min(duration, minimumDuration)
        switch drag {
        case let .left(originX, value):
            trimStart = min(trimEnd - minimum, max(0, value + Double(point.x - originX) * perPoint))
            onTrim?(trimStart, trimEnd, false)
        case let .right(originX, value):
            trimEnd = max(trimStart + minimum, min(duration, value + Double(point.x - originX) * perPoint))
            onTrim?(trimStart, trimEnd, true)
        case .seek:
            seek(at: point.x)
        }
        needsLayout = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag = drag else {
            return
        }
        self.drag = nil
        switch drag {
        case .left:
            if x(for: trimStart) - timelineRect.minX <= EditVideoScrubberView.snapDistance {
                trimStart = 0
                onTrim?(trimStart, trimEnd, false)
            }
            onEndTrimming?()
        case .right:
            if timelineRect.maxX - x(for: trimEnd) <= EditVideoScrubberView.snapDistance {
                trimEnd = duration
                onTrim?(trimStart, trimEnd, true)
            }
            onEndTrimming?()
        case .seek:
            onEndSeeking?()
        }
        updateColors()
        needsLayout = true
    }

    private func seek(at x: CGFloat) {
        position = min(trimEnd, max(trimStart, value(for: x)))
        onSeek?(position)
        layoutPlayhead()
    }
}
