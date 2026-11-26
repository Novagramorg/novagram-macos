import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows
import CurrencyFormat

struct WalletSendRatePill: Equatable {
    let text: String
    let mode: WalletSendInputMode
}

final class WalletSendMotionClock {
    var timing: WalletSendAmountMotionTiming?

    func sharedTiming(at now: Double) -> WalletSendAmountMotionTiming? {
        return self.timing.flatMap { now - $0.start < $0.duration ? $0 : nil }
    }
}

@available(macOS 10.15, *)
final class WalletSendRatePillRowItem: GeneralRowItem {
    fileprivate let pill: WalletSendRatePill?
    fileprivate let clock: WalletSendMotionClock
    fileprivate let toggle: () -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, pill: WalletSendRatePill?, clock: WalletSendMotionClock, toggle: @escaping () -> Void) {
        self.pill = pill
        self.clock = clock
        self.toggle = toggle
        super.init(initialSize, height: walletSendRatePillHeight, stableId: stableId, inset: NSEdgeInsets(left: 20, right: 20))
    }

    override func viewClass() -> AnyClass {
        return WalletSendRatePillRowView.self
    }

    override var accessibilityLabel: String? {
        guard let pill, !pill.text.isEmpty else {
            return nil
        }
        switch pill.mode {
        case .fiat:
            return walletTonAccessibilityText(pill.text)
        case .gram:
            return pill.text
        }
    }

    override var accessibilityIsSpacer: Bool {
        return pill == nil
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        guard pill != nil else {
            return false
        }
        toggle()
        return true
    }
}

let walletSendRatePillHeight: CGFloat = 26
private let walletSendRateArrowSize: CGFloat = 18
private let walletSendRateArrowWeights: [CGFloat] = [0.45, 0.8625, 1.0, 0.8625, 0.45]
private let walletSendRateVisibilityDuration: Double = 0.2

private struct WalletSendRateArrow {
    let side: Int
    let travel: CGFloat
    let alpha: CGFloat
}

private final class WalletSendRateOverlayView: NSView {
    var arrowImage: CGImage?
    private let gramImage = NSImage(named: "Wallet_TopGram")
    private var gramAlpha: CGFloat = 0
    private var arrows: [WalletSendRateArrow] = []
    private var arrowStretch: CGFloat = 1

    override var isFlipped: Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func update(gramAlpha: CGFloat, arrows: [WalletSendRateArrow], arrowStretch: CGFloat) {
        self.gramAlpha = gramAlpha
        self.arrows = arrows
        self.arrowStretch = arrowStretch
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        if gramAlpha > 0.001, let gramImage {
            gramImage.draw(in: NSMakeRect(8, 5, 16, 16), from: .zero, operation: .sourceOver, fraction: min(1, gramAlpha), respectFlipped: true, hints: nil)
        }

        guard let arrowImage else {
            return
        }
        let half = walletSendRateArrowSize / 2
        for arrow in arrows {
            context.saveGState()
            context.translateBy(x: bounds.width - 26 + half, y: 4 + half + arrow.travel)
            context.scaleBy(x: 1, y: arrowStretch)
            context.translateBy(x: -half, y: -half)
            context.clip(to: NSMakeRect(CGFloat(arrow.side) * half, 0, half, walletSendRateArrowSize))
            context.setAlpha(arrow.alpha)
            context.translateBy(x: 0, y: walletSendRateArrowSize)
            context.scaleBy(x: 1, y: -1)
            context.draw(arrowImage, in: NSMakeRect(0, 0, walletSendRateArrowSize, walletSendRateArrowSize))
            context.restoreGState()
        }
    }
}

private final class WalletSendRateContainerView: NSView {
    override var isFlipped: Bool {
        return true
    }
}

@available(macOS 10.15, *)
private final class WalletSendRatePillRowView: GeneralRowView {
    private let container = WalletSendRateContainerView()
    private let control = Control()
    private let pillBackground = WalletSendCommentBackgroundView(frame: .zero)
    private let title = WalletSendAnimatedTextView(frame: .zero)
    private let overlay = WalletSendRateOverlayView()
    private let rateFont = walletCardRoundedFont(13, monospacedDigits: false)
    private lazy var animator = ConstantDisplayLinkAnimator(update: { [weak self] in
        self?.renderFrame()
    }, fps: 120)
    private var titleSize = CGSize.zero
    private var arrowColor: NSColor?
    private var arrowTiming: WalletSendAmountMotionTiming?
    private var arrowFrom: CGFloat = 0
    private var arrowTo: CGFloat = 0
    private var arrowPhase: CGFloat = 0
    private var arrowPaceFrom: CGFloat = 0
    private var arrowPace: CGFloat = 0
    private var geometryTiming: WalletSendAmountMotionTiming?
    private var previousMode: WalletSendInputMode?
    private var previousText = ""
    private var lastPill: WalletSendRatePill?
    private var widthFrom: CGFloat = 22
    private var widthTo: CGFloat = 22
    private var currentWidth: CGFloat = 22
    private var gramFrom: CGFloat = 0
    private var gramTo: CGFloat = 0
    private var currentGram: CGFloat = 0
    private var visible = false
    private var shown: Bool?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        container.wantsLayer = true
        control.layer?.cornerRadius = walletSendRatePillHeight / 2
        control.layer?.masksToBounds = true
        control.scaleOnClick = true
        control.addSubview(pillBackground)
        control.addSubview(title)
        control.addSubview(overlay)
        control.set(handler: { [weak self] _ in
            (self?.item as? WalletSendRatePillRowItem)?.toggle()
        }, for: .Click)
        container.addSubview(control)
        addSubview(container)

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reduceMotionChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override var backdorColor: NSColor {
        return .clear
    }

    @objc private func reduceMotionChanged() {
        finishMotion()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            finishMotion()
        }
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletSendRatePillRowItem else {
            return
        }
        if arrowColor != theme.colors.grayText {
            arrowColor = theme.colors.grayText
            overlay.arrowImage = NSImage(named: "Wallet_Swap")?.precomposed(theme.colors.grayText)
        }
        if let pill = item.pill {
            lastPill = pill
        }
        let isVisible = window != nil && item.pill != nil
        if let pill = lastPill {
            update(text: pill.text, displaysGramIcon: pill.mode == .fiat, mode: pill.mode, isVisible: isVisible, timing: item.clock.timing, maxWidth: max(1, item.width - 64))
        }
        setShown(item.pill != nil, animated: animated && shown != nil && window != nil)
    }

    private func setShown(_ shown: Bool, animated: Bool) {
        guard self.shown != shown else {
            return
        }
        self.shown = shown
        guard let layer = container.layer else {
            container.isHidden = !shown
            return
        }
        container.isHidden = false
        let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
        let fromScale = layer.presentation()?.value(forKeyPath: "transform.scale.x") as? CGFloat ?? (shown ? 0.01 : 1.0)
        let toScale: CGFloat = shown ? 1.0 : 0.01
        layer.removeAnimation(forKey: "opacity")
        layer.removeAnimation(forKey: "transform")
        layer.opacity = shown ? 1.0 : 0.0
        layer.transform = walletAmountCenteredTransform(CATransform3DMakeScale(toScale, toScale, 1.0), layer: layer)
        control.isEnabled = shown
        guard animated else {
            return
        }
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = fromOpacity
        opacity.toValue = layer.opacity
        opacity.duration = walletSendRateVisibilityDuration
        opacity.timingFunction = timing
        layer.add(opacity, forKey: "opacity")
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: walletAmountCenteredTransform(CATransform3DMakeScale(fromScale, fromScale, 1.0), layer: layer))
        transform.toValue = NSValue(caTransform3D: layer.transform)
        transform.duration = walletSendRateVisibilityDuration
        transform.timingFunction = timing
        layer.add(transform, forKey: "transform")
    }

    private func update(text: String, displaysGramIcon: Bool, mode: WalletSendInputMode, isVisible: Bool, timing sharedTiming: WalletSendAmountMotionTiming?, maxWidth: CGFloat) {
        let wasVisible = visible
        visible = isVisible
        control.setAccessibilityLabel(displaysGramIcon ? "GRAM " + text : text)
        let now = CACurrentMediaTime()
        let switched = previousMode != nil && previousMode != mode
        let previousProgress = geometryTiming?.layoutProgress(at: now) ?? 1.0
        let previousWidth = widthFrom + (widthTo - widthFrom) * previousProgress + title.widthAdjustment(at: now)
        let sharedStart = sharedTiming.flatMap { now - $0.start < $0.duration ? $0.start : nil }
        let timing: WalletSendAmountMotionTiming?
        if previousMode != nil && wasVisible && isVisible && title.canAnimate {
            timing = WalletSendAmountMotionTiming(spin: switched, up: !(sharedTiming?.up ?? true), start: sharedStart ?? now)
        } else {
            timing = nil
        }
        titleSize = title.update(WalletSendAnimatedTextView.Content(text: text, numberPrefix: nil, font: rateFont, color: theme.colors.grayText, isVisible: isVisible, timing: timing, centered: false))
        let gramWidth: CGFloat = displaysGramIcon ? 19 : 0
        let width = min(maxWidth, max(22, 16 + gramWidth + titleSize.width + 3 + walletSendRateArrowSize))
        if text != previousText || widthTo != width || gramTo != (displaysGramIcon ? 1 : 0) {
            widthFrom = previousWidth
            widthTo = width
            gramFrom = gramFrom + (gramTo - gramFrom) * previousProgress
            gramTo = displaysGramIcon ? 1 : 0
            geometryTiming = timing
            if switched {
                arrowTiming = timing
                arrowFrom = arrowPhase
                arrowTo = floor(arrowPhase) + 1
                arrowPaceFrom = arrowPace
            }
        }
        previousMode = mode
        previousText = text
        if !isVisible {
            finishMotion()
        }
        renderFrame()
        if isAnimating {
            animator.isPaused = false
        }
    }

    private var isAnimating: Bool {
        let now = CACurrentMediaTime()
        return visible && (title.isAnimating || (geometryTiming?.progress(at: now) ?? 1) < 1 || (arrowTiming?.progress(at: now) ?? 1) < 1)
    }

    override func layout() {
        super.layout()
        renderFrame()
    }

    private func renderFrame() {
        let now = CACurrentMediaTime()
        if !isAnimating {
            geometryTiming = nil
            arrowTiming = nil
        }
        let p = geometryTiming?.layoutProgress(at: now) ?? 1
        currentWidth = widthFrom + (widthTo - widthFrom) * p + title.widthAdjustment(at: now)
        currentGram = gramFrom + (gramTo - gramFrom) * p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        control.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - currentWidth) / 2), 0, currentWidth, walletSendRatePillHeight)
        pillBackground.frame = control.bounds
        pillBackground.update(size: control.bounds.size, hasTail: false)
        title.frame = NSMakeRect(8 + 19 * currentGram, floorToScreenPixels(backingScaleFactor, (walletSendRatePillHeight - titleSize.height) / 2), titleSize.width, titleSize.height)
        overlay.frame = control.bounds
        CATransaction.commit()
        let arrows = advanceArrows(at: now)
        overlay.update(gramAlpha: currentGram, arrows: arrows.arrows, arrowStretch: arrows.stretch)
        if !isAnimating {
            animator.isPaused = true
        }
    }

    private func finishMotion() {
        title.finishMotion()
        geometryTiming = nil
        arrowTiming = nil
        animator.isPaused = true
        renderFrame()
    }

    private func advanceArrows(at now: Double) -> (arrows: [WalletSendRateArrow], stretch: CGFloat) {
        let raw = arrowTiming?.progress(at: now) ?? 1
        arrowPhase = arrowFrom + (arrowTo - arrowFrom) * WalletSendAmountMotionTiming.ease(raw)
        let phase = arrowPhase.truncatingRemainder(dividingBy: 1)
        let speed = pow(1 - raw, 1.2)
        arrowPace = arrowPaceFrom + (speed - arrowPaceFrom) * WalletSendAmountMotionTiming.ease(min(1, raw / 0.15))
        let pace: CGFloat = arrowTiming?.reduced == true ? 0 : arrowPace
        let loop = phase < 0.5 ? phase * 2 : phase * 2 - 2
        let smear = 8 * pace
        let multiple = smear > 1
        let total = walletSendRateArrowWeights.reduce(0, +)
        var arrows: [WalletSendRateArrow] = []
        for side in 0 ..< 2 {
            let direction: CGFloat = side == 0 ? -1 : 1
            for sample in multiple ? Array(walletSendRateArrowWeights.indices) : [0] {
                let k: CGFloat = multiple ? CGFloat(sample) / 4 - 0.5 : 0
                arrows.append(WalletSendRateArrow(
                    side: side,
                    travel: arrowTiming?.reduced == true ? 0 : direction * (22 * loop + k * smear),
                    alpha: multiple ? walletSendRateArrowWeights[sample] / total : 1
                ))
            }
        }
        return (arrows, 1 + 0.55 * pace)
    }
}
