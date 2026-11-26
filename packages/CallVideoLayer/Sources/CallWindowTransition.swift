import Cocoa
import TGUIKit

public final class CallWindowSource {
    private static let maxControlSize = NSMakeSize(200, 120)
    private static let pointSize: CGFloat = 36

    private weak var sourceView: NSView?
    private let rect: NSRect
    private let isControl: Bool

    private init(view: NSView, rect: NSRect, isControl: Bool) {
        self.sourceView = view
        self.rect = rect
        self.isControl = isControl
    }

    public static func view(_ view: NSView) -> CallWindowSource {
        return CallWindowSource(view: view, rect: view.bounds, isControl: true)
    }

    public var view: NSView? {
        return self.sourceView
    }

    public static func underCursor() -> CallWindowSource? {
        guard NSApp.isActive else {
            return nil
        }
        let location = NSEvent.mouseLocation
        let windowNumber = NSWindow.windowNumber(at: location, belowWindowWithWindowNumber: 0)
        guard let window = NSApp.window(withWindowNumber: windowNumber), window.isVisible, let root = window.contentView?.superview else {
            return nil
        }
        let point = window.convertPoint(fromScreen: location)
        guard let hit = root.hitTest(point), hit !== root else {
            return nil
        }
        var current: NSView? = hit
        while let view = current, view !== root {
            if view is Control || view is NSControl, view.bounds.width <= maxControlSize.width, view.bounds.height <= maxControlSize.height {
                return CallWindowSource(view: view, rect: view.bounds, isControl: true)
            }
            current = view.superview
        }
        let local = hit.convert(point, from: nil)
        return CallWindowSource(view: hit, rect: NSMakeRect(local.x - pointSize / 2, local.y - pointSize / 2, pointSize, pointSize), isControl: false)
    }

    public var screenRect: NSRect? {
        guard let view = self.sourceView, let window = view.window else {
            return nil
        }
        guard window.isVisible, !window.isMiniaturized, window.isOnActiveSpace, !window.styleMask.contains(.fullScreen), window.occlusionState.contains(.visible) else {
            return nil
        }
        guard !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty else {
            return nil
        }
        return window.convertToScreen(view.convert(rect, to: nil))
    }

    fileprivate var control: NSView? {
        return self.isControl ? self.sourceView : nil
    }
}

private final class CallTransitionWindow: NSWindow {
    var allowsKey = false

    override var canBecomeKey: Bool {
        return self.allowsKey
    }
}

public final class CallWindowTransition {
    private static let margin: CGFloat = 100
    private static let sampleRate: Double = 120
    private static let maximumDuration: Double = 2
    private static let geometryTolerance: CGFloat = 0.2
    private static let unitTolerance: CGFloat = 0.002
    private static let shadowOpacity: CGFloat = 0.69
    private static let shadowRadius: CGFloat = 20.5
    private static let shadowOffset = NSMakeSize(0, -18)
    private static let snapshotMaxSide: CGFloat = 72
    private static let fadeDuration: Double = 0.2
    private static let revealOpenness: CGFloat = 0.85
    private static let revealScale: CGFloat = 0.6
    private static let revealFade: CGFloat = 0.12
    private static let landingOpenness: CGFloat = 0.05
    private static let bounceDepth: CGFloat = 0.14
    private static let zoomInset: CGFloat = 0.04
    private static let animationKeys = ["position", "bounds", "cornerRadius", "opacity", "transform", "shadowPath", "shadowOpacity"]

    public static var windowCornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 16
        } else {
            return 10
        }
    }

    private struct Spring {
        let omega: Double
        let damping: Double

        static let position = Spring(omega: 21.0, damping: 0.84)
        static let width = Spring(omega: 22.5, damping: 0.74)
        static let height = Spring(omega: 19.0, damping: 0.76)
        static let openness = Spring(omega: 21.0, damping: 1.0)
        static let collapse = Spring(omega: 23.56, damping: 1.0)
        static let reveal = Spring(omega: 18.0, damping: 0.62)
        static let bounce = Spring(omega: 20.0, damping: 0.45)

        func remaining(at time: Double) -> CGFloat {
            if self.damping < 1 {
                let dampedOmega = self.omega * sqrt(1 - self.damping * self.damping)
                return CGFloat(exp(-self.damping * self.omega * time) * (cos(dampedOmega * time) + self.damping * self.omega / dampedOmega * sin(dampedOmega * time)))
            }
            return CGFloat((1 + self.omega * time) * exp(-self.omega * time))
        }

        func impulse(at time: Double) -> CGFloat {
            let dampedOmega = self.omega * sqrt(1 - self.damping * self.damping)
            let peak = atan(dampedOmega / (self.damping * self.omega)) / dampedOmega
            return CGFloat(exp(-self.damping * self.omega * (time - peak)) * sin(dampedOmega * time) / sin(dampedOmega * peak))
        }
    }

    private struct Channel {
        let from: CGFloat
        let to: CGFloat
        let spring: Spring
        let tolerance: CGFloat

        func value(at time: Double) -> CGFloat {
            return self.to + (self.from - self.to) * self.spring.remaining(at: time)
        }

        var settlingTime: Double {
            let distance = abs(self.from - self.to)
            let step = 1 / CallWindowTransition.sampleRate
            var time = CallWindowTransition.maximumDuration
            while time > 0, distance * abs(self.spring.remaining(at: time)) <= self.tolerance {
                time -= step
            }
            return min(CallWindowTransition.maximumDuration, max(0, time + step))
        }
    }

    private let transitionWindow: CallTransitionWindow
    private let shadowView: NSView
    private let bubbleView: NSView
    private let snapshotView: NSView
    private let snapshotLayer: CALayer
    private weak var content: NSView?
    private var frameSize: NSSize = .zero
    private var contentFrame: NSRect = .zero
    private var hasSnapshot = false
    private var isCancelled = false

    private init(frame: NSRect, level: NSWindow.Level, backgroundColor: NSColor, appearance: NSAppearance?) {
        let transitionWindow = CallTransitionWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        transitionWindow.isOpaque = false
        transitionWindow.backgroundColor = .clear
        transitionWindow.hasShadow = false
        transitionWindow.ignoresMouseEvents = true
        transitionWindow.isReleasedWhenClosed = false
        transitionWindow.animationBehavior = .none
        transitionWindow.collectionBehavior = [.transient, .ignoresCycle]
        transitionWindow.level = level
        transitionWindow.appearance = appearance

        let bounds = NSMakeRect(0, 0, frame.width, frame.height)
        let root = NSView(frame: bounds)
        root.wantsLayer = true
        transitionWindow.contentView = root

        let shadowView = NSView(frame: bounds)
        shadowView.wantsLayer = true
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowRadius = CallWindowTransition.shadowRadius
        shadowView.layer?.shadowOffset = CallWindowTransition.shadowOffset
        shadowView.layer?.shadowOpacity = 0

        let bubbleView = NSView()
        bubbleView.wantsLayer = true
        bubbleView.layer?.masksToBounds = true
        bubbleView.layer?.backgroundColor = backgroundColor.cgColor
        if #available(macOS 10.15, *) {
            bubbleView.layer?.cornerCurve = .continuous
        }

        let snapshotView = NSView(frame: bounds)
        snapshotView.wantsLayer = true
        let snapshotLayer = CALayer()
        snapshotLayer.anchorPoint = .zero
        snapshotLayer.contentsGravity = .resize
        snapshotLayer.opacity = 0
        snapshotLayer.contentsScale = transitionWindow.backingScaleFactor
        snapshotView.layer?.addSublayer(snapshotLayer)

        root.addSubview(shadowView)
        root.addSubview(bubbleView)
        root.addSubview(snapshotView)

        self.transitionWindow = transitionWindow
        self.shadowView = shadowView
        self.bubbleView = bubbleView
        self.snapshotView = snapshotView
        self.snapshotLayer = snapshotLayer
    }

    @discardableResult
    public static func present(window: NSWindow, content: NSView, source: CallWindowSource?, cornerRadius: CGFloat, attach: @escaping () -> Void, completion: (() -> Void)? = nil) -> CallWindowTransition? {
        if content.window === window {
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            } else {
                popIn(window: window, content: content)
            }
            completion?()
            return nil
        }
        let frame = window.frame
        let source = source?.screenRect != nil ? source : nil
        let rect = source?.screenRect ?? frame.insetBy(dx: frame.width * CallWindowTransition.zoomInset, dy: frame.height * CallWindowTransition.zoomInset)
        guard let screen = commonScreen(rect, frame), !reduceMotion else {
            content.removeFromSuperview()
            attach()
            popIn(window: window, content: content)
            completion?()
            return nil
        }
        let transition = CallWindowTransition(frame: transitionFrame(rect, frame, screen), level: window.level, backgroundColor: window.backgroundColor, appearance: window.appearance)
        transition.transitionWindow.disableScreenUpdatesUntilFlush()
        source?.control?.window?.disableScreenUpdatesUntilFlush()
        transition.transitionWindow.allowsKey = true
        transition.transitionWindow.orderFrontRegardless()
        transition.transitionWindow.makeKey()
        transition.host(content, in: window, at: frame, cornerRadius: cornerRadius)
        if let source {
            transition.capture(source)
        }
        transition.animate(from: transition.local(rect), to: transition.local(frame), cornerRadius: cornerRadius, opening: true, sourceView: source?.control, completion: {
            window.disableScreenUpdatesUntilFlush()
            content.removeFromSuperview()
            attach()
            if content.window === window {
                let buttons = CallWindowTransition.titlebarViews(window).map { ($0, $0.alphaValue) }
                buttons.forEach { $0.0.alphaValue = 0 }
                window.alphaValue = 1
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = CallWindowTransition.fadeDuration
                    buttons.forEach { $0.0.animator().alphaValue = $0.1 }
                }, completionHandler: nil)
            }
            transition.transitionWindow.orderOut(nil)
            completion?()
        })
        return transition
    }

    public static func dismiss(window: NSWindow, content: NSView, source: CallWindowSource?, cornerRadius: CGFloat, completion: (() -> Void)? = nil) {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue, false, 1_999_999, { _, _ in
            CallWindowTransition.collapse(window: window, content: content, source: source, cornerRadius: cornerRadius, completion: completion)
        })
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func collapse(window: NSWindow, content: NSView, source: CallWindowSource?, cornerRadius: CGFloat, completion: (() -> Void)?) {
        guard window.isVisible else {
            window.orderOut(nil)
            completion?()
            return
        }
        let frame = window.frame
        guard let source, let rect = source.screenRect, let screen = commonScreen(rect, frame), !reduceMotion else {
            popOut(window: window, content: content, completion: completion)
            return
        }
        let transition = CallWindowTransition(frame: transitionFrame(rect, frame, screen), level: window.level, backgroundColor: window.backgroundColor, appearance: window.appearance)
        transition.transitionWindow.orderFrontRegardless()
        transition.transitionWindow.disableScreenUpdatesUntilFlush()
        if window.contentView === content {
            window.contentView = nil
        }
        transition.host(content, in: window, at: frame, cornerRadius: cornerRadius)
        window.orderOut(nil)
        transition.animate(from: transition.local(frame), to: transition.local(rect), cornerRadius: cornerRadius, opening: false, sourceView: source.control, completion: {
            transition.transitionWindow.orderOut(nil)
            content.removeFromSuperview()
            completion?()
        })
    }

    public func cancel() {
        guard !self.isCancelled else {
            return
        }
        self.isCancelled = true
        for layer in [self.shadowView.layer, self.bubbleView.layer, self.content?.layer, self.snapshotLayer] {
            for key in CallWindowTransition.animationKeys {
                layer?.removeAnimation(forKey: "callWindow.\(key)")
            }
        }
        self.content?.removeFromSuperview()
        self.transitionWindow.orderOut(nil)
    }

    private func host(_ content: NSView, in window: NSWindow, at frame: NSRect, cornerRadius: CGFloat) {
        let rect = self.local(frame)
        let contentRect = window.contentRect(forFrameRect: frame)
        self.bubbleView.frame = rect
        self.bubbleView.layer?.cornerRadius = cornerRadius
        self.shadowView.layer?.shadowPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        self.frameSize = frame.size
        self.contentFrame = NSMakeRect(contentRect.minX - frame.minX, contentRect.minY - frame.minY, contentRect.width, contentRect.height)

        content.removeFromSuperview()
        content.frame = self.contentFrame
        self.bubbleView.addSubview(content)
        self.content = content
    }

    private func capture(_ source: CallWindowSource) {
        guard let control = source.control else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.snapshotLayer.contents = control.snapshot
        CATransaction.commit()
        self.hasSnapshot = true
    }

    private func local(_ rect: NSRect) -> NSRect {
        let origin = self.transitionWindow.frame.origin
        return rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func animate(from start: NSRect, to end: NSRect, cornerRadius: CGFloat, opening: Bool, sourceView: NSView?, completion: @escaping () -> Void) {
        guard let bubble = self.bubbleView.layer, let shadow = self.shadowView.layer, let content = self.content, let contentLayer = content.layer else {
            completion()
            return
        }
        let geometry = CallWindowTransition.geometryTolerance
        let springs: [Spring] = opening ? [.position, .position, .width, .height, .openness] : Array(repeating: .collapse, count: 5)
        let channels = [
            Channel(from: start.midX, to: end.midX, spring: springs[0], tolerance: geometry),
            Channel(from: start.midY, to: end.midY, spring: springs[1], tolerance: geometry),
            Channel(from: start.width, to: end.width, spring: springs[2], tolerance: geometry),
            Channel(from: start.height, to: end.height, spring: springs[3], tolerance: geometry),
            Channel(from: opening ? 0 : 1, to: opening ? 1 : 0, spring: springs[4], tolerance: CallWindowTransition.unitTolerance)
        ]
        let duration = channels.map { $0.settlingTime }.max() ?? 0
        let count = max(2, Int(ceil(duration * CallWindowTransition.sampleRate)) + 1)
        let frameSize = self.frameSize
        let contentFrame = self.contentFrame
        let contentAnchor = contentLayer.anchorPoint
        let bubbleAnchor = bubble.anchorPoint
        let sourceSize = (opening ? start : end).size
        let hasSnapshot = self.hasSnapshot

        var keyTimes: [NSNumber] = []
        var bubblePositions: [Any] = []
        var bubbleBounds: [Any] = []
        var radii: [Any] = []
        var bubbleOpacities: [Any] = []
        var contentPositions: [Any] = []
        var contentTransforms: [Any] = []
        var shadowPaths: [Any] = []
        var shadowOpacities: [Any] = []
        var snapshotPositions: [Any] = []
        var snapshotBounds: [Any] = []
        var snapshotOpacities: [Any] = []
        var sourceDelay: Double?

        for index in 0 ..< count {
            let fraction = Double(index) / Double(count - 1)
            let values = index == count - 1 ? channels.map { $0.to } : channels.map { $0.value(at: fraction * duration) }
            let width = max(1, values[2])
            let height = max(1, values[3])
            let rect = NSMakeRect(values[0] - width / 2, values[1] - height / 2, width, height)
            let radius = min(cornerRadius, min(width, height) / 2)
            let openness = max(0, min(1, values[4]))
            let bubbleAlpha = opening ? CallWindowTransition.smoothstep(0, 0.2, openness) : CallWindowTransition.smoothstep(0, 0.35, openness)
            let snapshotAlpha = hasSnapshot ? 1 - CallWindowTransition.smoothstep(0.15, 0.7, openness) : 0
            if sourceDelay == nil, opening ? openness >= CallWindowTransition.revealOpenness : openness <= CallWindowTransition.landingOpenness {
                sourceDelay = fraction * duration
            }
            let scale = max(width / frameSize.width, height / frameSize.height)
            let frameOrigin = NSMakePoint((width - frameSize.width * scale) / 2, (height - frameSize.height * scale) / 2)
            let snapshotScale = min(max(1, CallWindowTransition.snapshotMaxSide / max(1, sourceSize.width, sourceSize.height)), width / max(1, sourceSize.width), height / max(1, sourceSize.height))
            let snapshotSize = NSMakeSize(sourceSize.width * snapshotScale, sourceSize.height * snapshotScale)

            keyTimes.append(NSNumber(value: fraction))
            bubblePositions.append(NSValue(point: NSMakePoint(rect.minX + bubbleAnchor.x * width, rect.minY + bubbleAnchor.y * height)))
            bubbleBounds.append(NSValue(rect: NSMakeRect(0, 0, width, height)))
            radii.append(NSNumber(value: Double(radius)))
            bubbleOpacities.append(NSNumber(value: Double(bubbleAlpha)))
            contentPositions.append(NSValue(point: NSMakePoint(frameOrigin.x + (contentFrame.minX + contentAnchor.x * contentFrame.width) * scale, frameOrigin.y + (contentFrame.minY + contentAnchor.y * contentFrame.height) * scale)))
            contentTransforms.append(NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)))
            shadowPaths.append(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            shadowOpacities.append(NSNumber(value: Double(CallWindowTransition.shadowOpacity * openness * bubbleAlpha)))
            snapshotPositions.append(NSValue(point: NSMakePoint(rect.midX - snapshotSize.width / 2, rect.midY - snapshotSize.height / 2)))
            snapshotBounds.append(NSValue(rect: NSMakeRect(0, 0, snapshotSize.width, snapshotSize.height)))
            snapshotOpacities.append(NSNumber(value: Double(snapshotAlpha)))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bubble.opacity = (bubbleOpacities.last as? NSNumber)?.floatValue ?? 0
        shadow.shadowOpacity = (shadowOpacities.last as? NSNumber)?.floatValue ?? 0
        self.snapshotLayer.position = (snapshotPositions.last as? NSValue)?.pointValue ?? .zero
        self.snapshotLayer.bounds = (snapshotBounds.last as? NSValue)?.rectValue ?? .zero
        self.snapshotLayer.opacity = (snapshotOpacities.last as? NSNumber)?.floatValue ?? 0
        CATransaction.commit()

        let move = CallWindowTransition.keyframes("position", values: bubblePositions, keyTimes: keyTimes, duration: duration)
        move.delegate = CALayerAnimationDelegate(completion: { [weak self] _ in
            if self?.isCancelled == false {
                completion()
            }
        })
        bubble.add(move, forKey: "callWindow.position")
        bubble.add(CallWindowTransition.keyframes("bounds", values: bubbleBounds, keyTimes: keyTimes, duration: duration), forKey: "callWindow.bounds")
        bubble.add(CallWindowTransition.keyframes("cornerRadius", values: radii, keyTimes: keyTimes, duration: duration), forKey: "callWindow.cornerRadius")
        bubble.add(CallWindowTransition.keyframes("opacity", values: bubbleOpacities, keyTimes: keyTimes, duration: duration), forKey: "callWindow.opacity")
        contentLayer.add(CallWindowTransition.keyframes("position", values: contentPositions, keyTimes: keyTimes, duration: duration), forKey: "callWindow.position")
        contentLayer.add(CallWindowTransition.keyframes("transform", values: contentTransforms, keyTimes: keyTimes, duration: duration), forKey: "callWindow.transform")
        shadow.add(CallWindowTransition.keyframes("shadowPath", values: shadowPaths, keyTimes: keyTimes, duration: duration), forKey: "callWindow.shadowPath")
        shadow.add(CallWindowTransition.keyframes("shadowOpacity", values: shadowOpacities, keyTimes: keyTimes, duration: duration), forKey: "callWindow.shadowOpacity")
        if hasSnapshot {
            self.snapshotLayer.add(CallWindowTransition.keyframes("position", values: snapshotPositions, keyTimes: keyTimes, duration: duration), forKey: "callWindow.position")
            self.snapshotLayer.add(CallWindowTransition.keyframes("bounds", values: snapshotBounds, keyTimes: keyTimes, duration: duration), forKey: "callWindow.bounds")
            self.snapshotLayer.add(CallWindowTransition.keyframes("opacity", values: snapshotOpacities, keyTimes: keyTimes, duration: duration), forKey: "callWindow.opacity")
        }
        if let sourceView {
            self.animateSource(sourceView, delay: sourceDelay ?? duration, opening: opening)
        }
    }

    private func animateSource(_ view: NSView, delay: Double, opening: Bool) {
        guard let layer = view.layer, layer.bounds.width > 0, layer.bounds.height > 0 else {
            return
        }
        let spring: Spring = opening ? .reveal : .bounce
        let center = NSMakePoint(layer.bounds.width * (0.5 - layer.anchorPoint.x), layer.bounds.height * (0.5 - layer.anchorPoint.y))
        let alpha = Double(layer.opacity)
        let duration = delay + Channel(from: 0, to: 1, spring: spring, tolerance: CallWindowTransition.unitTolerance).settlingTime
        let count = max(2, Int(ceil(duration * CallWindowTransition.sampleRate)) + 1)

        var keyTimes: [NSNumber] = []
        var transforms: [Any] = []
        var opacities: [Any] = []
        for index in 0 ..< count {
            let fraction = Double(index) / Double(count - 1)
            let time = fraction * duration - delay
            let scale: CGFloat
            if index == count - 1 {
                scale = 1
            } else if opening {
                scale = time < 0 ? CallWindowTransition.revealScale : 1 - (1 - CallWindowTransition.revealScale) * spring.remaining(at: time)
            } else {
                scale = time < 0 ? 1 : 1 - CallWindowTransition.bounceDepth * spring.impulse(at: time)
            }
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            keyTimes.append(NSNumber(value: fraction))
            transforms.append(NSValue(caTransform3D: transform))
            opacities.append(NSNumber(value: time < 0 ? 0 : alpha * Double(CallWindowTransition.smoothstep(0, CallWindowTransition.revealFade, CGFloat(time)))))
        }

        layer.add(CallWindowTransition.keyframes("transform", values: transforms, keyTimes: keyTimes, duration: duration), forKey: "callWindow.sourceTransform")
        if opening {
            layer.add(CallWindowTransition.keyframes("opacity", values: opacities, keyTimes: keyTimes, duration: duration), forKey: "callWindow.sourceOpacity")
        }
    }

    private static func keyframes(_ keyPath: String, values: [Any], keyTimes: [NSNumber], duration: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = duration
        animation.calculationMode = .linear
        return animation
    }

    private static func titlebarViews(_ window: NSWindow) -> [NSView] {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        guard window.titleVisibility == .visible, !window.title.isEmpty, let titlebar = buttons.first?.superview else {
            return buttons
        }
        return buttons + titlebar.subviews.filter { $0 is NSTextField }
    }

    private static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private static func popIn(window: NSWindow, content: NSView) {
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if !reduceMotion {
            content.layer?.animateScaleCenter(from: 1.04, to: 1, duration: 0.3)
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }, completionHandler: nil)
    }

    private static func popOut(window: NSWindow, content: NSView, completion: (() -> Void)?) {
        if !reduceMotion {
            content.layer?.animateScaleCenter(from: 1, to: 1.04, duration: 0.3, removeOnCompletion: false)
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
            content.layer?.removeAnimation(forKey: "transform")
            completion?()
        })
    }

    private static var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static func commonScreen(_ rect: NSRect, _ frame: NSRect) -> NSScreen? {
        let rectCenter = NSMakePoint(rect.midX, rect.midY)
        let frameCenter = NSMakePoint(frame.midX, frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(rectCenter) && $0.frame.contains(frameCenter) })
    }

    private static func transitionFrame(_ rect: NSRect, _ frame: NSRect, _ screen: NSScreen) -> NSRect {
        return rect.union(frame).insetBy(dx: -margin, dy: -margin).intersection(screen.frame)
    }
}
