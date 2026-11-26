import Cocoa
import TGUIKit

private final class InstantPageV2ThinkingContentView: View {
    private var item: InstantPageV2TextItem
    private var theme: InstantPageTheme
    private let clippingInset: CGFloat

    public init(item: InstantPageV2TextItem, theme: InstantPageTheme, clippingInset: CGFloat) {
        self.item = item
        self.theme = theme
        self.clippingInset = clippingInset
        super.init(frame: .zero)
        self.backgroundColor = .clear
        self.userInteractionEnabled = false
        self.isEventLess = true
        self.layer?.masksToBounds = false
        self.layer?.isOpaque = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public func update(item: InstantPageV2TextItem, theme: InstantPageTheme) {
        self.item = item
        self.theme = theme
        self.setNeedsDisplay()
    }

    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        if self.item.textItem.hasButtons {
            self.item.textItem.instantPageTheme = self.theme
        }
        ctx.saveGState()
        ctx.translateBy(
            x: self.clippingInset - self.item.textItem.frame.minX,
            y: self.clippingInset - self.item.textItem.frame.minY
        )
        self.item.textItem.drawInTile(context: ctx)
        ctx.restoreGState()
    }
}

public final class InstantPageV2ThinkingView: View {
    private static let clippingInset: CGFloat = 4.0
    private static let peakAlpha: CGFloat = 0.3
    private static let duration: Double = 1.0
    private static let gradientWidth: CGFloat = 200.0
    private static let animationKey = "thinkingShimmer"

    public var topLevelItemIndex: Int = 0
    public var emojiContainerView: View {
        return self.contentView
    }

    private let contentView: InstantPageV2ThinkingContentView
    private let maskLayer = CAGradientLayer()
    private var maskSize: CGSize = .zero
    private(set) var isRevealed: Bool = false

    public init(item: InstantPageV2TextItem, theme: InstantPageTheme) {
        self.contentView = InstantPageV2ThinkingContentView(
            item: item,
            theme: theme,
            clippingInset: Self.clippingInset
        )
        super.init(frame: .zero)
        self.backgroundColor = .clear
        self.userInteractionEnabled = false
        self.isEventLess = true
        self.layer?.masksToBounds = false
        self.layer?.isOpaque = false
        self.layer?.opacity = 0.0
        self.isHidden = true

        self.maskLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.maskLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.maskLayer.colors = [
            NSColor(white: 1.0, alpha: 1.0).cgColor,
            NSColor(white: 1.0, alpha: Self.peakAlpha).cgColor,
            NSColor(white: 1.0, alpha: 1.0).cgColor
        ]
        self.maskLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.maskLayer.contentsScale = System.backingScale

        self.addSubview(self.contentView)
        self.contentView.layer?.mask = self.maskLayer
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateShimmerAnimation()
    }

    public func update(item: InstantPageV2TextItem, theme: InstantPageTheme) {
        let expandedFrame = item.frame.insetBy(
            dx: -Self.clippingInset,
            dy: -Self.clippingInset
        )
        self.frame = expandedFrame
        self.contentView.frame = self.bounds
        self.contentView.update(item: item, theme: theme)
        self.updateMask(size: expandedFrame.size)
    }

    public func setContentNeedsDisplay() {
        self.contentView.setNeedsDisplay()
    }

    public func setRevealed(_ revealed: Bool, animated: Bool) {
        guard self.isRevealed != revealed else {
            return
        }
        self.isRevealed = revealed
        let targetOpacity: Float = revealed ? 1.0 : 0.0
        if animated, let layer = self.layer {
            let sourceOpacity = layer.presentation()?.opacity ?? layer.opacity
            self.isHidden = false
            layer.opacity = targetOpacity
            layer.animateAlpha(
                from: CGFloat(sourceOpacity),
                to: CGFloat(targetOpacity),
                duration: 0.12
            )
        } else {
            self.layer?.opacity = targetOpacity
            self.isHidden = !revealed
        }
    }

    private func updateMask(size: CGSize) {
        guard self.maskSize != size else {
            self.updateShimmerAnimation()
            return
        }
        self.maskSize = size

        let travelDistance = size.width + Self.gradientWidth
        let maskWidth = size.width + 2.0 * travelDistance
        let dipHalfFraction = maskWidth > 0.0 ? (Self.gradientWidth * 0.5) / maskWidth : 0.0
        self.maskLayer.locations = [
            (0.5 - dipHalfFraction) as NSNumber,
            0.5 as NSNumber,
            (0.5 + dipHalfFraction) as NSNumber
        ]
        self.maskLayer.bounds = CGRect(origin: .zero, size: CGSize(width: maskWidth, height: size.height))
        self.maskLayer.position = CGPoint(x: -Self.gradientWidth * 0.5, y: size.height * 0.5)
        self.maskLayer.removeAnimation(forKey: Self.animationKey)
        self.updateShimmerAnimation()
    }

    private func updateShimmerAnimation() {
        guard self.window != nil, self.maskSize.width > 0.0, self.maskSize.height > 0.0 else {
            self.maskLayer.removeAnimation(forKey: Self.animationKey)
            return
        }
        guard self.maskLayer.animation(forKey: Self.animationKey) == nil else {
            return
        }
        let travelDistance = self.maskSize.width + Self.gradientWidth
        let animation = self.maskLayer.makeAnimation(
            from: 0.0 as NSNumber,
            to: travelDistance as NSNumber,
            keyPath: "position.x",
            timingFunction: .easeOut,
            duration: Self.duration,
            removeOnCompletion: true,
            additive: true
        )
        animation.repeatCount = Float.infinity
        self.maskLayer.add(animation, forKey: Self.animationKey)
    }
}
