import Cocoa
import TGUIKit

final class WalletSendButtonContentView: NSView {
    struct Content: Equatable {
        let title: String
        let titlePrefix: String?
        let subtitle: String?
        let color: NSColor
        let isVisible: Bool
        let mode: WalletSendInputMode
        let timing: WalletSendAmountMotionTiming?
    }

    private let title = WalletSendAnimatedTextView(frame: .zero)
    private var subtitle: WalletSendAnimatedTextView?
    private var content: Content?
    private let titleFont: NSFont = .medium(.text)
    private let subtitleFont: NSFont = .medium(.small)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.addSubview(self.title)
        self.title.animationFrameUpdated = { [weak self] in
            guard let self else { return }
            self.updateTextScale(self.title)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    static func install(in button: TextButton) -> WalletSendButtonContentView {
        if let view = button.subviews.first(where: { $0 is WalletSendButtonContentView }) as? WalletSendButtonContentView {
            return view
        }
        let view = WalletSendButtonContentView(frame: button.bounds)
        view.autoresizingMask = [.width, .height]
        button.addSubview(view)
        return view
    }

    static func remove(from button: TextButton) {
        for view in button.subviews where view is WalletSendButtonContentView {
            view.removeFromSuperview()
        }
    }

    func update(_ content: Content) {
        let previous = self.content
        var transition: ContainedViewLayoutTransition = .immediate
        if let previous, previous.isVisible, content.isVisible, self.window != nil,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           previous.title != content.title || previous.subtitle != content.subtitle {
            transition = .animated(duration: 0.22, curve: .easeInOut)
        }
        self.content = content
        self.setAccessibilityLabel([content.title, content.subtitle].compactMap { $0 }.joined(separator: ", "))
        let now = CACurrentMediaTime()
        let sharedStart = content.timing.flatMap { now - $0.start < $0.duration ? $0.start : nil }
        let timing = WalletSendAmountMotionTiming(
            spin: previous != nil && previous?.mode != content.mode,
            up: content.timing?.up ?? true,
            start: sharedStart ?? now
        )

        let titleSize = self.title.update(WalletSendAnimatedTextView.Content(text: content.title, numberPrefix: content.titlePrefix, font: self.titleFont, color: content.color, isVisible: content.isVisible, timing: timing, centered: true))

        var subtitleSize = CGSize.zero
        if let subtitleText = content.subtitle ?? previous?.subtitle {
            let subtitle: WalletSendAnimatedTextView
            if let current = self.subtitle {
                subtitle = current
            } else {
                subtitle = WalletSendAnimatedTextView(frame: .zero)
                subtitle.layer?.opacity = 0
                subtitle.animationFrameUpdated = { [weak self, weak subtitle] in
                    guard let self, let subtitle else { return }
                    self.updateTextScale(subtitle)
                }
                self.addSubview(subtitle)
                self.subtitle = subtitle
            }
            let measuredSubtitleSize = subtitle.update(WalletSendAnimatedTextView.Content(text: subtitleText, numberPrefix: nil, font: self.subtitleFont, color: content.color.withAlphaComponent(0.8), isVisible: content.isVisible && content.subtitle != nil, timing: timing, centered: true))
            if content.subtitle != nil {
                subtitleSize = measuredSubtitleSize
            }
        }
        self.layoutLines(titleSize: titleSize, subtitleSize: subtitleSize, transition: transition)
    }

    private var titleSize = CGSize.zero
    private var subtitleSize = CGSize.zero

    override func layout() {
        super.layout()
        self.layoutLines(titleSize: self.titleSize, subtitleSize: self.subtitleSize, transition: .immediate)
    }

    private func layoutLines(titleSize: CGSize, subtitleSize: CGSize, transition: ContainedViewLayoutTransition) {
        self.titleSize = titleSize
        self.subtitleSize = subtitleSize
        let availableWidth = self.bounds.width
        let titleScale = min(1.0, availableWidth / max(1.0, titleSize.width))
        let subtitleScale = min(1.0, availableWidth / max(1.0, subtitleSize.width))
        let hasSubtitle = self.content?.subtitle != nil
        let titleHeight = titleSize.height * titleScale
        let subtitleHeight = subtitleSize.height * subtitleScale
        let spacing: CGFloat = hasSubtitle ? 1.0 : 0.0
        let contentHeight = titleHeight + spacing + subtitleHeight
        let contentY = floorToScreenPixels(self.backingScaleFactor, (self.bounds.height - contentHeight) / 2.0)
        transition.updateFrame(view: self.title, frame: CGRect(x: (availableWidth - titleSize.width) / 2.0, y: contentY + (titleHeight - titleSize.height) / 2.0, width: titleSize.width, height: titleSize.height))
        self.updateTextScale(self.title)
        if let subtitle = self.subtitle {
            if hasSubtitle {
                let subtitleTransition: ContainedViewLayoutTransition = subtitle.layer?.opacity == 0 ? .immediate : transition
                subtitleTransition.updateFrame(view: subtitle, frame: CGRect(x: (availableWidth - subtitleSize.width) / 2.0, y: contentY + titleHeight + spacing + (subtitleHeight - subtitleSize.height) / 2.0, width: subtitleSize.width, height: subtitleSize.height))
                self.updateTextScale(subtitle)
            }
            transition.updateAlpha(view: subtitle, alpha: hasSubtitle ? 1.0 : 0.0)
        }
    }

    private func updateTextScale(_ view: WalletSendAnimatedTextView) {
        guard let layer = view.layer else { return }
        let scale = min(1.0, self.bounds.width / max(1.0, view.currentWidth))
        let transform = walletAmountCenteredTransform(CATransform3DMakeScale(scale, scale, 1.0), layer: layer)
        if !CATransform3DEqualToTransform(layer.transform, transform) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = transform
            CATransaction.commit()
        }
    }
}
