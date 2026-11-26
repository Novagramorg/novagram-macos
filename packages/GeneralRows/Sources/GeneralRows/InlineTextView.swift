import Cocoa
import TGUIKit
import TelegramContext

public final class InlineTextView: TextView {
    private var inlineRenderer: InlineTextRenderer?
    private var animatableContentObserver: AnimatableContentObserver?
    private var isLite: Bool = false

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.userInteractionEnabled = false
        self.isSelectable = false
    }

    public convenience override init() {
        self.init(frame: .zero)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func set(text: TextViewLayout?, context: (any AccountContextProtocol)?, insetEmoji: CGFloat = 0, decreaseAvatar: CGFloat = 0, emojiOffset: NSPoint = .init()) {
        let hasInlineContent = context != nil && text?.embeddedItems.isEmpty == false
        if !hasInlineContent {
            self.inlineRenderer?.updateAnimatableContent(window: nil, isLite: true)
            self.inlineRenderer?.clear()
            self.inlineRenderer = nil
            self.animatableContentObserver = nil
        }
        self.update(text)
        if let context, text != nil {
            self.isLite = context.isLite(.emoji)
        }
        if hasInlineContent, let context, let text {
            if self.inlineRenderer == nil {
                self.inlineRenderer = GeneralRowsHooks.shared.makeInlineTextRenderer()
            }
            self.inlineRenderer?.update(textView: self, layout: text, context: context, insetEmoji: insetEmoji, emojiOffset: emojiOffset, decreaseAvatar: decreaseAvatar)
        }
        self.updateListeners()
        self.updateAnimatableContent()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateListeners()
        self.updateAnimatableContent()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updateListeners()
        self.updateAnimatableContent()
    }

    @objc private func updateAnimatableContent() {
        guard let inlineRenderer = inlineRenderer else { return }
        inlineRenderer.updateAnimatableContent(window: self.window, isLite: self.isLite)
    }

    private func updateListeners() {
        guard window != nil, inlineRenderer != nil else {
            animatableContentObserver = nil
            return
        }
        if animatableContentObserver == nil {
            animatableContentObserver = AnimatableContentObserver()
        }
        self.animatableContentObserver?.update(for: self, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }
}
