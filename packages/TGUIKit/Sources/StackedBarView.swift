import Cocoa

public final class StackedBarView: BarView {

    public static let pillHeight: CGFloat = 40
    private static let spacing: CGFloat = 10

    public private(set) var buttons: [ImageButton] = []

    private let glassWrapper: GlassContainerView
    private var ghosts: [ObjectIdentifier: LiquidGlassView] = [:]
    private var validLayout: NSSize?

    public init(controller: ViewController) {
        self.glassWrapper = GlassContainerView(frame: .zero, flipped: true, spacing: 0)
        super.init(controller: controller)
        self.layer?.masksToBounds = false
        self.glassWrapper.glassContent.backgroundColor = .clear
        addSubview(glassWrapper)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private func createButton(image: CGImage? = nil, text: String? = nil, glassForceAppearance: LiquidGlassAppearance? = nil, handler: (() -> Void)? = nil) -> ImageButton {
        let btn: ImageButton
        if let text = text {
            let textBtn = TextButton()
            textBtn.autoSizeToFit = false
            textBtn.set(font: .normal(.title), for: .Normal)
            textBtn.set(color: presentation.colors.text, for: .Normal)
            textBtn.set(text: text, for: .Normal)
            textBtn.set(background: .clear, for: .Normal)
            btn = textBtn
        } else {
            btn = ImageButton()
        }
        if let image = image {
            btn.set(image: image, for: .Normal)
        }
        btn.scaleOnClick = true
        btn.disableActions()
        btn.animates = false
        btn.autohighlight = false
        btn.shadow = nil
        btn.layer?.masksToBounds = false

        if let handler {
            btn.set(handler: { _ in handler() }, for: .Click)
        }
        addSubview(btn)
        let ghost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true, forceAppearance: glassForceAppearance)
        glassWrapper.addGhost(ghost)
        ghosts[ObjectIdentifier(btn)] = ghost
        btn.interactiveGlassView = ghost
        btn.additionalGlassEffectView = ghost
        return btn
    }

    @discardableResult
    public func addButton(image: CGImage? = nil, text: String? = nil, glassForceAppearance: LiquidGlassAppearance? = nil, handler: (() -> Void)? = nil) -> ImageButton {
        let btn = createButton(image: image, text: text, glassForceAppearance: glassForceAppearance, handler: handler)
        buttons.append(btn)
        validLayout = nil
        return btn
    }

    @discardableResult
    public func insertButton(at index: Int, image: CGImage? = nil, text: String? = nil, glassForceAppearance: LiquidGlassAppearance? = nil, handler: (() -> Void)? = nil) -> ImageButton {
        let btn = createButton(image: image, text: text, glassForceAppearance: glassForceAppearance, handler: handler)
        let clamped = max(0, min(index, buttons.count))
        buttons.insert(btn, at: clamped)
        validLayout = nil
        return btn
    }

    public func removeButton(_ btn: ImageButton) {
        btn.removeFromSuperview()
        buttons.removeAll(where: { $0 === btn })
        if let ghost = ghosts.removeValue(forKey: ObjectIdentifier(btn)) {
            glassWrapper.removeGhost(ghost)
        }
        validLayout = nil
    }

    public func set(hidden: Bool, for button: ImageButton) {
        guard button.isHidden != hidden else {
            return
        }
        button.isHidden = hidden
        validLayout = nil
        superview?.needsLayout = true
    }

    /// Animate the button's icon opacity, and toggle the corresponding glass
    /// ghost's visibility instantly. The merged glass surface lives in the
    /// container's SDF compositor and animating opacity on the wrapper layer
    /// doesn't reach it; toggling `isHidden` is what makes the compositor
    /// release / reinstate the surface.
    public func change(opacity: CGFloat, for button: ImageButton, animated: Bool = true) {
        button.change(opacity: opacity, animated: animated)
        ghosts[ObjectIdentifier(button)]?.isHidden = opacity <= 0
    }

    private var visibleButtons: [ImageButton] {
        return buttons.filter { !$0.isHidden }
    }

    override var isFitted: Bool {
        return true
    }

    public override func fit(to maxWidth: CGFloat, transition: ContainedViewLayoutTransition = .immediate) -> CGFloat {
        let pillHeight = StackedBarView.pillHeight
        let spacing = StackedBarView.spacing
        var totalWidth: CGFloat = 0
        validLayout = .zero
        for btn in visibleButtons {
            if let textBtn = btn as? TextButton, !textBtn.isEmpty {
                _ = textBtn.sizeToFit(NSMakeSize(20, 0), NSMakeSize(maxWidth, pillHeight), thatFit: false, transition: transition)
            } else {
                btn.sizeToFit(.zero, NSMakeSize(pillHeight, pillHeight), thatFit: true, transition: transition)
            }
            let w = btn.frame.width
            if totalWidth > 0, btn != visibleButtons.last { totalWidth += spacing }
            totalWidth += w
        }
        return totalWidth
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        for btn in buttons {
            if let textBtn = btn as? TextButton {
                textBtn.set(color: presentation.colors.text, for: .Normal)
                textBtn.set(background: .clear, for: .Normal)
            }
        }
        // Forward to each ghost so its forceAppearance.didSet rebuilds the
        // inner NSGlassEffectView at the new dark/light boundary.
        for (_, ghost) in ghosts {
            ghost.updateLocalizationAndTheme(theme: theme)
        }
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        // Bail when size matches the cache. The synchronous `layout()` pass
        // that runs after an animator-driven resize enters here with
        // `.immediate`; without this guard, transition.updateFrame on each
        // ghost / button would clobber the in-flight CABasicAnimations.
        if size == validLayout { return }
        validLayout = size

        let pillHeight = StackedBarView.pillHeight
        let spacing = StackedBarView.spacing
        let y = floorToScreenPixels(backingScaleFactor, (size.height - pillHeight) / 2)
        let visible = visibleButtons


        let totalWidth = visible.reduce(CGFloat(0)) { sum, btn in
            return sum + btn.frame.width
        } + CGFloat(max(0, visible.count - 1)) * spacing

        transition.updateFrame(view: glassWrapper, frame: size.bounds)
        glassWrapper.updateLayout(size: size, transition: transition)

        var x = size.width - totalWidth
        for btn in visible {
            let w = btn.frame.width
            let btnSize = NSMakeSize(w, pillHeight)
            let btnFrame = NSRect(origin: NSMakePoint(x, y), size: btnSize)
            transition.updateFrame(view: btn, frame: btnFrame)
            btn.updateLayout(size: btnSize, transition: transition)
            if let ghost = ghosts[ObjectIdentifier(btn)] {
                // Track the button's target opacity so a faded-out button
                // doesn't leave its glass blob behind when layout re-runs.
                let buttonOpacity = btn.layer?.opacity ?? 1
                ghost.isHidden = buttonOpacity <= 0.01
                glassWrapper.setGhostFrame(ghost, frame: btnFrame, transition: transition)
            }
            x += w + spacing
        }

        // Hide ghosts whose buttons are hidden.
        for btn in buttons where btn.isHidden {
            ghosts[ObjectIdentifier(btn)]?.isHidden = true
        }
    }
}
