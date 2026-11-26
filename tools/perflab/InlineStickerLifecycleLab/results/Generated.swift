import Cocoa
import TGUIKit
public final class ReferenceInlineStickerView: Control {
    private let isPlayable: Bool
    public let controlContent: Bool
    public let animateLayer: InlineStickerItemLayer
    public init(account: Account, inlinePacksContext: InlineStickersContext?, emoji: ChatTextCustomEmojiAttribute, size: NSSize, getColors:((TelegramMediaFile)->[LottieColor])? = nil, shimmerColor: InlineStickerItemLayer.Shimmer = .init(circle: false), isPlayable: Bool = true, playPolicy: LottiePlayPolicy = .loop, controlContent: Bool = true) {
        let layer = InlineStickerItemLayer(account: account, inlinePacksContext: inlinePacksContext, emoji: emoji, size: size, playPolicy: playPolicy, getColors: getColors, shimmerColor: shimmerColor)
        self.isPlayable = isPlayable
        self.animateLayer = layer
        self.controlContent = controlContent
        super.init(frame: size.bounds)
        self.layer?.addSublayer(layer)
        layer.superview = self
        userInteractionEnabled = false
    }
    public init(account: Account, file: TelegramMediaFile, size: NSSize, getColors:((TelegramMediaFile)->[LottieColor])? = nil, shimmerColor: InlineStickerItemLayer.Shimmer = .init(circle: false), isPlayable: Bool = true, playPolicy: LottiePlayPolicy = .loop, controlContent: Bool = true, ignorePreview: Bool = false, synchronyous: Bool = false) {
        let layer = InlineStickerItemLayer(account: account, file: file, size: size, playPolicy: playPolicy, getColors: getColors, shimmerColor: shimmerColor, ignorePreview: ignorePreview, synchronyous: synchronyous)
        layer.isPlayable = isPlayable
        self.isPlayable = isPlayable
        self.animateLayer = layer
        self.controlContent = controlContent
        super.init(frame: size.bounds)
        self.layer?.addSublayer(layer)
        layer.superview = self
        userInteractionEnabled = false
    }


    @objc func updateAnimatableContent() -> Void {
        if controlContent {
            var isKeyWindow: Bool = false
            if let window = window {
                if !window.canBecomeKey {
                    isKeyWindow = true
                } else {
                    isKeyWindow = window.isKeyWindow
                }
            }
            animateLayer.isPlayable = isKeyWindow && isPlayable && self.visibleRect != .zero
        }
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

    deinit {
        contentObserver.removeObservers()
        NotificationCenter.default.removeObserver(self)
    }

    private let contentObserver = AnimatableContentTokenObserver()

    private func updateListeners() {
        contentObserver.update(for: self, handler: { [weak self] _ in
            self?.updateAnimatableContent()
        })
    }


    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

}


public final class CandidateInlineStickerView: Control {
    private let isPlayable: Bool
    public let controlContent: Bool
    public let animateLayer: InlineStickerItemLayer
    public init(account: Account, inlinePacksContext: InlineStickersContext?, emoji: ChatTextCustomEmojiAttribute, size: NSSize, getColors:((TelegramMediaFile)->[LottieColor])? = nil, shimmerColor: InlineStickerItemLayer.Shimmer = .init(circle: false), isPlayable: Bool = true, playPolicy: LottiePlayPolicy = .loop, controlContent: Bool = true) {
        let layer = InlineStickerItemLayer(account: account, inlinePacksContext: inlinePacksContext, emoji: emoji, size: size, playPolicy: playPolicy, getColors: getColors, shimmerColor: shimmerColor)
        self.isPlayable = isPlayable
        self.animateLayer = layer
        self.controlContent = controlContent
        super.init(frame: size.bounds)
        self.layer?.addSublayer(layer)
        layer.superview = self
        userInteractionEnabled = false
    }
    public init(account: Account, file: TelegramMediaFile, size: NSSize, getColors:((TelegramMediaFile)->[LottieColor])? = nil, shimmerColor: InlineStickerItemLayer.Shimmer = .init(circle: false), isPlayable: Bool = true, playPolicy: LottiePlayPolicy = .loop, controlContent: Bool = true, ignorePreview: Bool = false, synchronyous: Bool = false) {
        let layer = InlineStickerItemLayer(account: account, file: file, size: size, playPolicy: playPolicy, getColors: getColors, shimmerColor: shimmerColor, ignorePreview: ignorePreview, synchronyous: synchronyous)
        layer.isPlayable = isPlayable
        self.isPlayable = isPlayable
        self.animateLayer = layer
        self.controlContent = controlContent
        super.init(frame: size.bounds)
        self.layer?.addSublayer(layer)
        layer.superview = self
        userInteractionEnabled = false
    }


    @objc func updateAnimatableContent() -> Void {
        if controlContent {
            var isKeyWindow: Bool = false
            if let window = window {
                if !window.canBecomeKey {
                    isKeyWindow = true
                } else {
                    isKeyWindow = window.isKeyWindow
                }
            }
            animateLayer.isPlayable = isKeyWindow && isPlayable && self.visibleRect != .zero
        }
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

    deinit {
        contentObserver?.removeObservers()
        NotificationCenter.default.removeObserver(self)
    }

    private var contentObserver: AnimatableContentTokenObserver?

    private func updateListeners() {
        guard controlContent, window != nil else {
            contentObserver = nil
            return
        }
        if contentObserver == nil {
            contentObserver = AnimatableContentTokenObserver()
        }
        contentObserver?.update(for: self, handler: { [weak self] _ in
            self?.updateAnimatableContent()
        })
    }


    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

}


