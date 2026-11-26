import Cocoa

open class BackNavigationBar: TextButtonBarView {

    private static let size: CGFloat = 40

    public init(_ controller:ViewController, glassForceAppearance: LiquidGlassAppearance? = nil) {
        let backSettings = controller.backSettings()
        super.init(controller: controller, text: "", style: controller.barPresentation, glassForceAppearance: glassForceAppearance)

        if let image = backSettings.1 {
            set(image: image, for: .Normal)
        }
        set(handler: { [weak self] _ in
            self?.controller?.executeReturn()
        }, for: .Click)

        requestUpdate()
    }

    override var isFitted: Bool {
        return super.isFitted
    }

    public func requestUpdate() {
        guard let controller = self.controller else {
            return
        }
        let backSettings = controller.backSettings()
        set(text: "", for: .Normal)
        if let image = backSettings.1 {
             set(image: image, for: .Normal)
        } else {
            removeImage(for: .Normal)
        }
        style = controller.barPresentation
        needsLayout = true
    }

    open override func fit(to maxWidth: CGFloat, transition: ContainedViewLayoutTransition = .immediate) -> CGFloat {
        let size = BackNavigationBar.size
        button.sizeToFit(.zero, NSMakeSize(BackNavigationBar.size, BackNavigationBar.size), thatFit: true, transition: transition)
        return size
    }
    
    open override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        transition.updateFrame(view: button, frame: button.centerFrameY(x: 0))
        button.updateLayout(size: button.frame.size, transition: transition)
    }

    open override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
}
