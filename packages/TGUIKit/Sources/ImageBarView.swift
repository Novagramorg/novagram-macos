import Cocoa

public class ImageBarView: BarView {

    public static let pillSize: CGFloat = 40

    public var button: ImageButton = ImageButton()

    public func set(image: CGImage, highlightImage: CGImage? = nil) {
        button.set(image: image, for: .Normal)
        if let highlight = highlightImage {
            button.set(image: highlight, for: .Highlight)
        }
    }

    public init(controller: ViewController, _ image: CGImage, _ highlight: CGImage? = nil) {
        super.init(controller: controller)

        button.scaleOnClick = true
        button.disableActions()
        button.animates = false
        button.autohighlight = false
        button.layer?.cornerRadius = ImageBarView.pillSize / 2
        button.layer?.masksToBounds = true
        button.setGlassEffect()

        addSubview(button)
        self.layer?.masksToBounds = false
        set(image: image, highlightImage: highlight)
    }

    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func fit(to maxWidth: CGFloat, transition: ContainedViewLayoutTransition = .immediate) -> CGFloat {
        let size = ImageBarView.pillSize
        button.sizeToFit(.zero, NSMakeSize(size, size), thatFit: true, transition: transition)
        return size
    }

    open override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    open override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let pillSize = ImageBarView.pillSize
        let x = floorToScreenPixels(backingScaleFactor, (size.width - pillSize) / 2)
        let y = floorToScreenPixels(backingScaleFactor, (size.height - pillSize) / 2)
        transition.updateFrame(view: button, frame: NSMakeRect(x, y, pillSize, pillSize))
        button.updateLayout(size: NSMakeSize(pillSize, pillSize), transition: transition)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        button.updateLocalizationAndTheme(theme: theme)
    }
}
