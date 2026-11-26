import Cocoa

public final class ShimmerTooltipView: View {
    private static let horizontalInset: CGFloat = 11
    private static let verticalInset: CGFloat = 3
    private static let cornerRadius: CGFloat = 10
    private static let arrowSize = NSMakeSize(18, 7)
    private static let anchorSpacing: CGFloat = 3
    private static let sideInset: CGFloat = 10
    private static let shimmerWidth: CGFloat = 60

    private let backgroundView = View()
    private let textView = TextView()
    private let fillLayer = CAShapeLayer()
    private let shimmerClip = CAShapeLayer()
    private let shimmerContainer = CALayer()
    private let shimmerOutline = CAShapeLayer()
    private let shimmerBand = CAGradientLayer()
    private var arrowX: CGFloat = 0
    private var isDismissed = false

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false

        shimmerOutline.fillColor = nil
        shimmerOutline.strokeColor = NSColor.black.cgColor
        shimmerOutline.lineWidth = 3
        shimmerContainer.mask = shimmerOutline
        shimmerBand.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerBand.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerBand.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.4).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        shimmerContainer.addSublayer(shimmerBand)
        let shimmerHolder = CALayer()
        shimmerHolder.mask = shimmerClip
        shimmerHolder.addSublayer(shimmerContainer)
        backgroundView.layer?.addSublayer(fillLayer)
        backgroundView.layer?.addSublayer(shimmerHolder)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public convenience init(text: NSAttributedString, color: NSColor) {
        self.init(frame: .zero)
        let layout = TextViewLayout(text, maximumNumberOfLines: 1)
        layout.measure(width: 300)
        textView.update(layout)
        fillLayer.fillColor = color.cgColor
        setFrameSize(NSMakeSize(textView.frame.width + ShimmerTooltipView.horizontalInset * 2, textView.frame.height + ShimmerTooltipView.verticalInset * 2 + ShimmerTooltipView.arrowSize.height))
    }

    public func show(in container: NSView, pointingAt anchor: NSRect, timeout: Double = 5) {
        container.addSubview(self)
        update(anchor: anchor)
        layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        layer?.animateScaleSpringFrom(anchor: NSMakePoint(arrowX, frame.height), from: 0.01, to: 1, duration: 0.4, bounce: false)

        if let window = window as? Window {
            let hide: (NSEvent) -> KeyHandlerResult = { [weak self] _ in
                self?.hide()
                return .rejected
            }
            window.set(mouseHandler: hide, with: self, for: .leftMouseDown, priority: .supreme)
            window.set(mouseHandler: hide, with: self, for: .rightMouseDown, priority: .supreme)
            window.set(mouseHandler: hide, with: self, for: .scrollWheel, priority: .supreme)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.hide()
        }
    }

    public func update(anchor: NSRect) {
        guard let container = superview else {
            return
        }
        let size = frame.size
        let x = min(max(ShimmerTooltipView.sideInset, anchor.midX - size.width / 2), container.frame.width - size.width - ShimmerTooltipView.sideInset)
        let y = container.isFlipped ? anchor.minY - ShimmerTooltipView.anchorSpacing - size.height : anchor.maxY + ShimmerTooltipView.anchorSpacing
        setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, x), floorToScreenPixels(backingScaleFactor, y)))
        arrowX = anchor.midX - frame.minX
        needsLayout = true
    }

    public func hide() {
        guard superview != nil, !isDismissed else {
            return
        }
        isDismissed = true
        (window as? Window)?.removeAllHandlers(for: self)
        performSubviewRemoval(self, animated: true, scale: true)
    }

    public override func layout() {
        super.layout()
        backgroundView.frame = bounds
        let bodyHeight = frame.height - ShimmerTooltipView.arrowSize.height
        textView.setFrameOrigin(NSMakePoint(ShimmerTooltipView.horizontalInset, floorToScreenPixels(backingScaleFactor, (bodyHeight - textView.frame.height) / 2)))

        let path = outlinePath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = bounds
        fillLayer.path = path
        shimmerClip.path = path
        shimmerContainer.superlayer?.frame = bounds
        shimmerContainer.frame = bounds
        shimmerOutline.path = path
        shimmerBand.frame = NSMakeRect(-ShimmerTooltipView.shimmerWidth, 0, ShimmerTooltipView.shimmerWidth, frame.height)
        CATransaction.commit()

        if shimmerBand.animation(forKey: "shimmer") == nil, frame.width > 0 {
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = -ShimmerTooltipView.shimmerWidth / 2
            animation.toValue = frame.width + ShimmerTooltipView.shimmerWidth / 2
            animation.duration = 2.2
            animation.repeatCount = .infinity
            shimmerBand.add(animation, forKey: "shimmer")
        }
    }

    private func outlinePath() -> CGPath {
        let arrow = ShimmerTooltipView.arrowSize
        let width = frame.width
        let height = frame.height - arrow.height
        let radius = min(ShimmerTooltipView.cornerRadius, height / 2)
        let tip = min(max(arrowX, radius + arrow.width / 2), width - radius - arrow.width / 2)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: width - radius, y: 0))
        path.addArc(tangent1End: CGPoint(x: width, y: 0), tangent2End: CGPoint(x: width, y: radius), radius: radius)
        path.addLine(to: CGPoint(x: width, y: height - radius))
        path.addArc(tangent1End: CGPoint(x: width, y: height), tangent2End: CGPoint(x: width - radius, y: height), radius: radius)
        path.addLine(to: CGPoint(x: tip + arrow.width / 2, y: height))
        path.addLine(to: CGPoint(x: tip + 1.4, y: height + arrow.height - 0.8))
        path.addQuadCurve(to: CGPoint(x: tip - 1.4, y: height + arrow.height - 0.8), control: CGPoint(x: tip, y: height + arrow.height + 0.4))
        path.addLine(to: CGPoint(x: tip - arrow.width / 2, y: height))
        path.addLine(to: CGPoint(x: radius, y: height))
        path.addArc(tangent1End: CGPoint(x: 0, y: height), tangent2End: CGPoint(x: 0, y: height - radius), radius: radius)
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: radius, y: 0), radius: radius)
        path.closeSubpath()
        return path
    }
}
