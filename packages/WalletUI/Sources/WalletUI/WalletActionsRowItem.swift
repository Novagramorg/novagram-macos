import Cocoa
import TGUIKit
import TelegramTheme
import TelegramContext
import GeneralRows

@available(macOS 10.15, *)
public final class WalletActionsRowItem: GeneralRowItem {
    fileprivate let leftTitle: String
    fileprivate let rightTitle: String
    fileprivate let leftEnabled: Bool
    fileprivate let rightEnabled: Bool
    fileprivate let leftAction: ((() -> NSView?)?) -> Void
    fileprivate let rightAction: ((() -> NSView?)?) -> Void
    fileprivate let intro: WalletOpenIntro?

    init(_ initialSize: NSSize, stableId: AnyHashable, leftTitle: String, leftEnabled: Bool = true, rightEnabled: Bool = true, rightTitle: String, viewType: GeneralViewType, intro: WalletOpenIntro? = nil, leftAction: @escaping ((() -> NSView?)?) -> Void, rightAction: @escaping ((() -> NSView?)?) -> Void) {
        self.leftTitle = leftTitle
        self.intro = intro
        self.rightTitle = rightTitle
        self.leftEnabled = leftEnabled
        self.rightEnabled = rightEnabled
        self.leftAction = leftAction
        self.rightAction = rightAction
        super.init(initialSize, height: 44, stableId: stableId, viewType: viewType)
    }

    public override func viewClass() -> AnyClass {
        return WalletActionsRowView.self
    }

    public override var accessibilityLabel: String? {
        return [leftTitle, rightTitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

@available(macOS 10.15, *)
private final class WalletActionsRowView: TableRowView, WalletIntroParticipant {
    private let leftButton = TextButton()
    private let rightButton = TextButton()
    private var shimmerViews: [ShimmerEffectView] = []
    private var shimmerStart: CFTimeInterval?
    private var shimmerAnimator: ConstantDisplayLinkAnimator?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        layer?.zPosition = 10

        for button in [leftButton, rightButton] {
            button.autoSizeToFit = false
            button.scaleOnClick = true
            addSubview(button)
        }

        leftButton.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletActionsRowItem else {
                return
            }
            item.leftAction({ [weak self] in self?.leftButton })
        }, for: .Click)

        rightButton.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletActionsRowItem else {
                return
            }
            item.rightAction({ [weak self] in self?.rightButton })
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func updateColors() {
        super.updateColors()
        for button in [leftButton, rightButton] {
            button.set(background: .clear, for: .Normal)
            button.set(background: .clear, for: .Hover)
            button.set(background: .clear, for: .Highlight)
            button.setGlassEffect(tintColor: walletClassicAccent)
            button.glassTintColor = walletClassicAccent
            let textColor = walletClassicAccent.lightness > 0.8 ? NSColor.black : NSColor.white
            button.set(color: textColor, for: .Normal)
        }
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletActionsRowItem else {
            return
        }

        item.intro?.attach(self)

        for button in [leftButton, rightButton] {
            button.set(font: .medium(.title), for: .Normal)
        }
        leftButton.set(text: item.leftTitle, for: .Normal)
        rightButton.set(text: item.rightTitle, for: .Normal)
        leftButton.isEnabled = item.leftEnabled
        rightButton.isEnabled = item.rightEnabled
        leftButton.alphaValue = item.leftEnabled ? 1 : 0.6
        rightButton.alphaValue = item.rightEnabled ? 1 : 0.6

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        guard let item = item as? WalletActionsRowItem else {
            return
        }

        let blockWidth = item.blockWidth
        let startX = floorToScreenPixels(backingScaleFactor, (frame.width - blockWidth) / 2)
        let spacing: CGFloat = 10
        let buttonHeight = item.height
        let buttonWidth = floorToScreenPixels(backingScaleFactor, (blockWidth - spacing) / 2)

        leftButton.frame = NSMakeRect(startX, 0, buttonWidth, buttonHeight)
        rightButton.frame = NSMakeRect(startX + blockWidth - buttonWidth, 0, buttonWidth, buttonHeight)

        for button in [leftButton, rightButton] {
            button.layer?.cornerRadius = buttonHeight / 2
        }

        layoutShimmer()
    }

    func prepareIntro() {
    }

    func cancelIntro() {
    }

    func playIntro(at time: CFTimeInterval, pace: Double) {
        let start = time + WalletHomeIntro.shimmerDelay * pace
        guard shimmerStart == nil, start + WalletHomeIntro.shimmerDuration > CACurrentMediaTime(), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        shimmerStart = start
        let animator = ConstantDisplayLinkAnimator(update: { [weak self] in
            self?.shimmerTick()
        }, fps: 60)
        animator.isPaused = false
        shimmerAnimator = animator
        shimmerTick()
    }

    private func shimmerTick() {
        guard let start = shimmerStart else {
            stopShimmer()
            return
        }
        let now = CACurrentMediaTime()
        if now >= start + WalletHomeIntro.shimmerDuration {
            stopShimmer()
        } else if now >= start, shimmerViews.isEmpty {
            shimmerViews = [leftButton, rightButton].map { _ in
                let view = ShimmerEffectView()
                view.isStatic = true
                view.isEventLess = true
                addSubview(view)
                return view
            }
            layoutShimmer()
        }
    }

    private func layoutShimmer() {
        for (view, button) in zip(shimmerViews, [leftButton, rightButton]) {
            view.frame = button.frame
            view.layer?.cornerRadius = button.frame.height / 2
            view.updateAbsoluteRect(button.frame, within: bounds.size)
            view.update(backgroundColor: .clear, foregroundColor: .clear, shimmeringColor: NSColor.white.withAlphaComponent(0.3), shapes: [.roundedRect(rect: view.bounds, cornerRadius: view.bounds.height / 2)], horizontal: true, size: view.bounds.size)
        }
    }

    private func stopShimmer() {
        shimmerAnimator?.invalidate()
        shimmerAnimator = nil
        for view in shimmerViews {
            view.removeFromSuperview()
        }
        shimmerViews = []
    }
}
