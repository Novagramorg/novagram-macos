import Cocoa
import TGUIKit
import CurrencyFormat

func walletSendGroupGlyphs(_ glyphs: inout [WalletSendAmountGlyph], decimalSeparator: String, groupingSeparator: String, numberPrefix: String? = nil) {
    let firstDigit = glyphs.firstIndex(where: { $0.text.first?.wholeNumberValue != nil })
    let lastDigit = glyphs.lastIndex(where: { $0.text.first?.wholeNumberValue != nil })
    let prefixCharacterCount = numberPrefix.map { $0.filter { !$0.isWhitespace }.count }
    var characterIndex = 0
    var inFraction = false
    for i in glyphs.indices {
        guard let firstDigit, let lastDigit else {
            if let prefixCharacterCount, characterIndex >= prefixCharacterCount {
                glyphs[i].group = .suffix
            } else {
                glyphs[i].group = .prefix
            }
            characterIndex += glyphs[i].text.filter { !$0.isWhitespace }.count
            continue
        }
        if i < firstDigit {
            glyphs[i].group = .prefix
        } else if i > lastDigit {
            glyphs[i].group = .suffix
        } else if glyphs[i].text == decimalSeparator {
            inFraction = true
            glyphs[i].group = .fraction
        } else if !inFraction && glyphs[i].text == groupingSeparator {
            glyphs[i].group = .grouping
        } else {
            glyphs[i].group = inFraction ? .fraction : .integer
        }
    }
}

struct WalletSendAnimatedTextLine {
    let glyphs: [WalletSendAmountGlyph]
    let size: CGSize

    init(text: String, font: NSFont, color: NSColor, backingScale: CGFloat) {
        let spaceWidth = ceil(NSAttributedString(string: " ", attributes: [.font: font]).boundingRect(with: NSMakeSize(100, 100), options: .usesLineFragmentOrigin).width)
        let baseline = floorToScreenPixels(backingScale, font.ascender)
        var glyphs: [WalletSendAmountGlyph] = []
        var x: CGFloat = 0
        for character in text {
            let string = String(character)
            if string == " " {
                x += spaceWidth
                continue
            }
            let width = WalletSendAmountGlyphMetrics.width(string, font: font)
            glyphs.append(WalletSendAmountGlyph(text: string, font: font, color: color, position: CGPoint(x: x + width / 2, y: baseline), group: .integer))
            x += ceil(width)
        }
        self.glyphs = glyphs
        self.size = CGSize(width: x, height: floor(font.ascender - font.descender))
    }
}

private final class WalletSendStaticGlyphsView: NSView {
    var glyphs: [WalletSendAmountGlyph] = [] {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for glyph in glyphs {
            NSAttributedString(string: glyph.text, attributes: [.font: glyph.font, .foregroundColor: glyph.color]).draw(at: NSMakePoint(glyph.leadingEdge, glyph.position.y - glyph.font.ascender))
        }
    }
}

final class WalletSendAnimatedTextView: NSView {
    struct Content: Equatable {
        let text: String
        let numberPrefix: String?
        let font: NSFont
        let color: NSColor
        let isVisible: Bool
        let timing: WalletSendAmountMotionTiming?
        let centered: Bool
    }

    private let canvas = WalletSendAmountCanvas(frame: .zero)
    private let fallback = WalletSendStaticGlyphsView()
    private let motion = WalletSendAmountMotion()
    private lazy var animator = ConstantDisplayLinkAnimator(update: { [weak self] in
        self?.tick()
    }, fps: 120)
    private var content: Content?
    private var textSize = CGSize.zero
    private var widthFrom: CGFloat = 0.0
    private var frameDuration = 1.0 / 120.0
    private var lastFrameTime: Double?
    private var glyphsAvailable = false
    var animationFrameUpdated: (() -> Void)?

    var currentWidth: CGFloat {
        return self.presentationWidth(at: CACurrentMediaTime())
    }

    var canAnimate: Bool {
        return self.content?.isVisible == true && self.window != nil && self.glyphsAvailable
    }

    var isAnimating: Bool {
        return self.canAnimate && self.motion.isAnimating(at: CACurrentMediaTime())
    }

    func widthAdjustment(at time: Double) -> CGFloat {
        return self.motion.widthAdjustment(at: time)
    }

    private func presentationWidth(at time: Double) -> CGFloat {
        let progress = self.motion.timing?.layoutProgress(at: time) ?? 1.0
        return self.widthFrom + (self.textSize.width - self.widthFrom) * progress + self.motion.widthAdjustment(at: time)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.addSubview(self.fallback)
        self.addSubview(self.canvas)
        self.canvas.onFrameReady = { [weak self] in
            self?.updateRendererVisibility()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.finishMotion), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override var isFlipped: Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window == nil {
            self.finishMotion()
        } else {
            self.renderFrame()
        }
    }

    override func layout() {
        super.layout()
        self.renderFrame()
    }

    @discardableResult
    func update(_ content: Content) -> CGSize {
        let mayAnimate = self.canAnimate && content.isVisible
        let now = CACurrentMediaTime()
        let previousWidth = self.presentationWidth(at: now)
        self.content = content
        self.setAccessibilityLabel(content.text)
        let separators = walletDecimalSeparator + walletGroupingSeparator
        self.canvas.prepareGlyphs(text: content.text, font: content.font, separators: separators)
        let line = WalletSendAnimatedTextLine(text: content.text, font: content.font, color: content.color, backingScale: self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
        var glyphs = line.glyphs
        walletSendGroupGlyphs(&glyphs, decimalSeparator: walletDecimalSeparator, groupingSeparator: walletGroupingSeparator, numberPrefix: content.numberPrefix)
        self.fallback.glyphs = glyphs
        self.fallback.frame = CGRect(origin: .zero, size: line.size)
        self.glyphsAvailable = self.canvas.isAvailable && glyphs.allSatisfy { glyph in
            glyph.text.allSatisfy(\.isWhitespace) || self.canvas.glyphMask(for: glyph) != nil
        }
        if glyphs != self.motion.target || line.size != self.textSize {
            self.widthFrom = previousWidth
            self.textSize = line.size
            self.motion.update(glyphs, width: line.size.width, timing: mayAnimate && self.glyphsAvailable ? content.timing : nil, at: now, frameDuration: self.frameDuration)
        }
        if !self.canAnimate {
            self.finishMotion()
        } else {
            self.renderFrame()
        }
        if self.isAnimating {
            self.animator.isPaused = false
        }
        return line.size
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if let lastFrameTime {
            self.frameDuration += (min(max(now - lastFrameTime, 1.0 / 240.0), 1.0 / 30.0) - self.frameDuration) * 0.3
        }
        self.lastFrameTime = now
        self.renderFrame()
    }

    private func updateRendererVisibility() {
        let usesMetal = self.glyphsAvailable && self.canvas.hasFrame && self.content?.isVisible == true && self.window != nil
        self.canvas.isHidden = !usesMetal
        self.fallback.isHidden = usesMetal
    }

    private func renderFrame() {
        let now = CACurrentMediaTime()
        let isAnimating = self.canAnimate && self.motion.isAnimating(at: now)
        if !isAnimating {
            self.motion.finish()
            self.animator.isPaused = true
            self.lastFrameTime = nil
        }
        let width = self.presentationWidth(at: now)
        let sprites = self.motion.frame(at: now, frameDuration: self.frameDuration)
        let padding = ceil(sprites.reduce(self.content.map { walletSendLineHeight($0.font) } ?? 0.0) { height, sprite in
            max(height, walletSendLineHeight(sprite.glyph.font), sprite.morph.map { walletSendLineHeight($0.from.font) } ?? 0.0)
        })
        let offsetX = self.content?.centered == true ? (self.textSize.width - width) * 0.5 : 0.0
        let originX = min(0.0, offsetX) - padding
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.canvas.frame = CGRect(
            x: originX, y: -padding,
            width: ceil((max(self.widthFrom, self.textSize.width, width) + max(0.0, offsetX) + 2.0 * padding) / 64.0) * 64.0,
            height: self.textSize.height + 2.0 * padding
        )
        CATransaction.commit()
        self.canvas.isRenderingEnabled = self.content?.isVisible == true && self.window != nil
        self.canvas.frameDuration = self.frameDuration
        let canvasSprites = sprites.map { sprite -> WalletSendAmountSprite in
            var sprite = sprite
            sprite.glyph.position.x += offsetX - originX
            sprite.glyph.position.y += padding
            return sprite
        }
        self.canvas.update(sprites: canvasSprites, isAnimating: isAnimating)
        self.updateRendererVisibility()
        self.animationFrameUpdated?()
    }

    @objc func finishMotion() {
        self.motion.finish()
        self.animator.isPaused = true
        self.lastFrameTime = nil
        self.renderFrame()
    }
}

func walletSendLineHeight(_ font: NSFont) -> CGFloat {
    return ceil(font.ascender - font.descender + font.leading)
}
