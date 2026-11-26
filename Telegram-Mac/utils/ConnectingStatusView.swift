import Cocoa
import TGUIKit
import TelegramTheme

public final class ConnectingStatusView: Control {

    public static let collapsedSize = NSMakeSize(40, 40)

    private let glassView: LiquidGlassView
    private let progressView: InfiniteProgressView
    private let textClippingView: View = View()
    private let textView: TextView = TextView()

    private static let progressSize = NSMakeSize(20, 20)
    private static let leadingInset: CGFloat = 10
    private static let textGap: CGFloat = 8
    private static let trailingInset: CGFloat = 14

    private var status: NetworkConnectingStatus? {
        didSet {
            if oldValue != status {
                applyStatus()
            }
        }
    }

    private var isExpanded: Bool = false
    private(set) var expandedSize: NSSize = ConnectingStatusView.collapsedSize

    public required init(frame frameRect: NSRect) {
        self.glassView = LiquidGlassView(frame: frameRect.size.bounds, cornerRadius: frameRect.height / 2, hasShadow: true, hasBorder: true, tintAlpha: 0.5)
        self.progressView = InfiniteProgressView(color: theme.colors.text, lineWidth: 2.0)
        super.init(frame: frameRect)

        self.backgroundColor = .clear
        self.layer?.masksToBounds = false

        addSubview(glassView)
        addSubview(textClippingView)
        addSubview(progressView)

        textClippingView.wantsLayer = true
        textClippingView.layer?.masksToBounds = true
        textClippingView.backgroundColor = .clear
        textClippingView.addSubview(textView)

        progressView.progress = nil
        progressView.setFrameSize(ConnectingStatusView.progressSize)

        textView.userInteractionEnabled = false
        textView.isSelectable = false

        set(handler: { [weak self] _ in
            self?.setExpanded(true, animated: true)
        }, for: .Hover)

        set(handler: { [weak self] _ in
            self?.setExpanded(false, animated: true)
        }, for: .Normal)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.progressView.color = theme.colors.text
        self.applyStatus()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(status: NetworkConnectingStatus?, animated: Bool) {
        self.status = status
    }

    private func applyStatus() {
        guard let status = status else { return }

        progressView.isHidden = !status.shouldAddProgress
        progressView.color = theme.colors.text

        let layout = TextViewLayout(.initialize(string: status.text, color: theme.colors.text, font: .medium(.text)))
        layout.measure(width: 200)
        textView.update(layout)

        let textWidth = layout.layoutSize.width
        let expandedWidth = ConnectingStatusView.leadingInset + ConnectingStatusView.progressSize.width + ConnectingStatusView.textGap + textWidth + ConnectingStatusView.trailingInset
        self.expandedSize = NSMakeSize(max(ConnectingStatusView.collapsedSize.width, expandedWidth), ConnectingStatusView.collapsedSize.height)

        if isExpanded {
            let transition: ContainedViewLayoutTransition = window != nil ? .animated(duration: 0.3, curve: .spring) : .immediate
            transition.updateFrame(view: self, frame: NSRect(origin: frame.origin, size: expandedSize))
            updateLayout(size: expandedSize, transition: transition)
        }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard self.isExpanded != expanded else { return }
        guard status != nil else { return }
        self.isExpanded = expanded

        let target: NSSize = expanded ? expandedSize : ConnectingStatusView.collapsedSize
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.3, curve: .spring) : .immediate

        transition.updateFrame(view: self, frame: NSRect(origin: frame.origin, size: target))
        updateLayout(size: target, transition: transition)
    }

    public override func layout() {
        super.layout()
        updateLayout(size: bounds.size, transition: .immediate)
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: glassView, frame: CGRect(origin: .zero, size: size))
        glassView.cornerRadius = size.height / 2
        glassView.updateLayout(size: size, transition: transition)

        let progressSize = progressView.frame.size
        let textSize = textView.frame.size

        if isExpanded {
            let progressFrame = NSMakeRect(ConnectingStatusView.leadingInset, (size.height - progressSize.height) / 2, progressSize.width, progressSize.height)
            transition.updateFrame(view: progressView, frame: progressFrame)

            let textClipX = progressFrame.maxX + ConnectingStatusView.textGap
            let clipWidth = max(0, size.width - textClipX - ConnectingStatusView.trailingInset)
            let clipFrame = NSMakeRect(textClipX, 0, clipWidth, size.height)
            transition.updateFrame(view: textClippingView, frame: clipFrame)

            let textFrame = NSMakeRect(0, (clipFrame.height - textSize.height) / 2, textSize.width, textSize.height)
            transition.updateFrame(view: textView, frame: textFrame)
        } else {
            let progressFrame = NSMakeRect((size.width - progressSize.width) / 2, (size.height - progressSize.height) / 2, progressSize.width, progressSize.height)
            transition.updateFrame(view: progressView, frame: progressFrame)

            let collapsedClipX = progressFrame.maxX + ConnectingStatusView.textGap
            let clipFrame = NSMakeRect(collapsedClipX, 0, 0, size.height)
            transition.updateFrame(view: textClippingView, frame: clipFrame)

            let textFrame = NSMakeRect(0, (clipFrame.height - textSize.height) / 2, textSize.width, textSize.height)
            transition.updateFrame(view: textView, frame: textFrame)
        }
    }
}
