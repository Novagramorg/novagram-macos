import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
@_exported import UniqueGiftRenderer

public enum UniqueGiftBackgroundStyle: Equatable {
    case item(giftCenterY: CGFloat, cornerRadius: CGFloat)
    case message(patternCenterY: CGFloat, cornerRadius: CGFloat)
    case header(patternCenterY: CGFloat)
    case animatedHeader(patternCenterY: CGFloat)
    case profile(avatarCenter: CGPoint, avatarSize: CGFloat, defaultHeight: CGFloat, gradientCenter: CGPoint)

    public func geometry(size: CGSize) -> UniqueGiftBackgroundGeometry {
        switch self {
        case let .item(giftCenterY, cornerRadius):
            return .item(size: size, giftCenterY: giftCenterY, cornerRadius: cornerRadius)
        case let .message(patternCenterY, cornerRadius):
            return .message(size: size, patternCenterY: patternCenterY, cornerRadius: cornerRadius)
        case let .header(patternCenterY), let .animatedHeader(patternCenterY):
            return .header(size: size, patternCenterY: patternCenterY)
        case let .profile(avatarCenter, avatarSize, defaultHeight, gradientCenter):
            return .profile(size: size, avatarCenter: avatarCenter, avatarSize: avatarSize, defaultHeight: defaultHeight, gradientCenter: gradientCenter)
        }
    }

    var hasLivePattern: Bool {
        switch self {
        case .profile, .animatedHeader:
            return true
        default:
            return false
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case let .item(_, cornerRadius), let .message(_, cornerRadius):
            return cornerRadius
        case .header, .animatedHeader, .profile:
            return 0.0
        }
    }
}

private final class UniqueGiftRenderTarget {
    private let lock = NSLock()
    private var key: UniqueGiftBackgroundKey?

    func set(_ key: UniqueGiftBackgroundKey?) {
        self.lock.lock()
        self.key = key
        self.lock.unlock()
    }

    func isWanted(_ key: UniqueGiftBackgroundKey) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.key == key
    }
}

public final class UniqueGiftBackgroundLayer: CALayer {
    public var onContentReady: (() -> Void)?

    private static let renderQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "org.telegram.uniqueGiftBackground"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
        return queue
    }()

    private var context: (any AccountContextProtocol)?
    private var content: UniqueGiftBackgroundContent?
    private var backgroundStyle: UniqueGiftBackgroundStyle = .item(giftCenterY: 0.0, cornerRadius: 0.0)
    private var glyph: UniqueGiftGlyph?
    private var glyphFileId: Int64?
    private let glyphDisposable = MetaDisposable()
    private var image: CGImage?
    private var displayedKey: UniqueGiftBackgroundKey?
    private let renderTarget = UniqueGiftRenderTarget()
    private var requestedKey: UniqueGiftBackgroundKey? {
        didSet {
            if self.requestedKey != oldValue {
                self.renderTarget.set(self.requestedKey)
            }
        }
    }
    private var failedKey: UniqueGiftBackgroundKey?
    private var fadesNextImage = false

    private var gradientLayer: CAGradientLayer?
    private var patternTintLayer: CAGradientLayer?
    private var patternItemLayers: [CALayer] = []

    public var renderScale: CGFloat? {
        didSet {
            if self.renderScale != oldValue {
                self.updateImage()
            }
        }
    }

    public var renderColorSpace: CGColorSpace? {
        didSet {
            if self.renderColorSpace != oldValue {
                self.updateImage()
            }
        }
    }

    public var patternTransitionFraction: CGFloat = 0.0 {
        didSet {
            if self.patternTransitionFraction != oldValue {
                self.updateLiveLayers()
            }
        }
    }

    public override init() {
        super.init()
        self.contentsGravity = .resize
    }

    public override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.glyphDisposable.dispose()
    }

    public override func action(forKey event: String) -> CAAction? {
        return nil
    }

    public override var bounds: CGRect {
        didSet {
            if self.bounds.size != oldValue.size {
                self.setNeedsLayout()
            }
        }
    }

    public override func layoutSublayers() {
        super.layoutSublayers()
        self.updateImage()
        self.updateLiveLayers()
    }

    public func update(context: any AccountContextProtocol, content: UniqueGiftBackgroundContent?, style: UniqueGiftBackgroundStyle, animated: Bool = false) {
        self.context = context
        if animated && content != nil && self.content != nil && content != self.content {
            if style.hasLivePattern {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.25
                self.add(transition, forKey: "contents")
            } else if self.image != nil {
                self.fadesNextImage = true
            }
        }
        if content?.pattern?.fileId != self.content?.pattern?.fileId {
            self.glyphFileId = nil
            self.glyph = nil
            self.glyphDisposable.set(nil)
        }
        self.content = content
        self.backgroundStyle = style
        self.masksToBounds = style.hasLivePattern
        self.loadGlyphIfNeeded()
        self.updateImage()
        self.updateLiveLayers()
    }

    private var effectiveScale: CGFloat {
        return self.renderScale ?? System.backingScale
    }

    private func key(glyphId: Int64?) -> UniqueGiftBackgroundKey? {
        guard let content = self.content, self.bounds.width > 0.0, self.bounds.height > 0.0 else {
            return nil
        }
        return UniqueGiftBackgroundKey(geometry: self.backgroundStyle.geometry(size: self.bounds.size), colors: content.colors, glyphId: glyphId, scale: self.effectiveScale, colorSpace: UniqueGiftBackgroundRenderer.renderColorSpace(self.renderColorSpace))
    }

    private func loadGlyphIfNeeded() {
        guard let context = self.context, let pattern = self.content?.pattern else {
            self.glyphDisposable.set(nil)
            return
        }
        if self.glyphFileId == pattern.fileId {
            return
        }
        self.glyphFileId = pattern.fileId
        if let glyph = UniqueGiftPatternGlyphs.shared.cachedGlyph(fileId: pattern.fileId) {
            self.glyph = glyph
            self.glyphDisposable.set(nil)
            return
        }
        self.glyphDisposable.set((UniqueGiftPatternGlyphs.shared.glyph(context: context, pattern: pattern) |> deliverOnMainQueue).start(next: { [weak self] glyph in
            guard let self = self, self.glyphFileId == pattern.fileId else {
                return
            }
            self.glyph = glyph
            self.updateImage()
            self.updateLiveLayers()
        }))
    }

    private func updateImage() {
        if self.backgroundStyle.hasLivePattern {
            self.requestedKey = nil
            self.show(nil, key: nil)
            self.backgroundColor = self.content.flatMap { UniqueGiftBackgroundRenderer.color($0.colors.edge) }
            return
        }
        let patternId = self.content?.pattern?.fileId
        guard let full = self.key(glyphId: patternId) else {
            self.requestedKey = nil
            self.show(nil, key: nil)
            return
        }
        if full == self.displayedKey {
            return
        }
        if let image = UniqueGiftBackgroundCache.shared.cachedImage(for: full) {
            self.requestedKey = nil
            self.show(image, key: full)
            return
        }
        let glyphReady = patternId == nil || self.glyph != nil
        let target = glyphReady ? full : UniqueGiftBackgroundKey(geometry: full.geometry, colors: full.colors, glyphId: nil, scale: full.scale, colorSpace: full.colorSpace)
        if target == self.displayedKey || target == self.requestedKey || target == self.failedKey {
            return
        }
        if let image = UniqueGiftBackgroundCache.shared.cachedImage(for: target) {
            self.requestedKey = nil
            self.show(image, key: target)
            return
        }
        if self.displayedKey?.colors != target.colors && !self.fadesNextImage {
            self.showPlaceholder(colors: target.colors)
        }
        self.requestedKey = target
        let glyph = target.glyphId != nil ? self.glyph?.mask : nil
        let renderTarget = self.renderTarget
        UniqueGiftBackgroundLayer.renderQueue.addOperation { [weak self] in
            guard renderTarget.isWanted(target) else {
                return
            }
            let image = UniqueGiftBackgroundCache.shared.image(for: target, glyph: glyph)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.requestedKey == target else {
                    return
                }
                self.requestedKey = nil
                guard let image = image else {
                    self.failedKey = target
                    return
                }
                self.show(image, key: target)
                self.updateImage()
            }
        }
    }

    private func showPlaceholder(colors: UniqueGiftColors) {
        self.image = nil
        self.displayedKey = nil
        self.contents = nil
        self.backgroundColor = UniqueGiftBackgroundRenderer.color(colors.edge)
        self.cornerRadius = self.backgroundStyle.cornerRadius
    }

    private func show(_ image: CGImage?, key: UniqueGiftBackgroundKey?) {
        if self.fadesNextImage && image != nil {
            self.fadesNextImage = false
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.25
            self.add(transition, forKey: "contents")
        }
        self.image = image
        self.displayedKey = key
        self.backgroundColor = nil
        self.cornerRadius = 0.0
        self.contentsScale = key?.scale ?? self.effectiveScale
        self.contents = image
        if image != nil, key?.glyphId == self.content?.pattern?.fileId {
            self.onContentReady?()
        }
    }

    private func updateLiveLayers() {
        guard self.backgroundStyle.hasLivePattern, let content = self.content, self.bounds.width > 0.0, self.bounds.height > 0.0 else {
            self.gradientLayer?.removeFromSuperlayer()
            self.gradientLayer = nil
            self.removePatternLayers()
            return
        }
        let geometry = self.backgroundStyle.geometry(size: self.bounds.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let gradientLayer: CAGradientLayer
        if let current = self.gradientLayer {
            gradientLayer = current
        } else {
            gradientLayer = CAGradientLayer()
            gradientLayer.type = .radial
            self.insertSublayer(gradientLayer, at: 0)
            self.gradientLayer = gradientLayer
        }
        let gradientFrame = geometry.gradientFrame
        let ellipse = geometry.gradientEllipse
        gradientLayer.frame = gradientFrame
        gradientLayer.colors = [
            UniqueGiftBackgroundRenderer.color(content.colors.center),
            UniqueGiftBackgroundRenderer.color(content.colors.edge)
        ]
        let start = CGPoint(x: (ellipse.center.x - gradientFrame.minX) / max(gradientFrame.width, 1.0), y: (ellipse.center.y - gradientFrame.minY) / max(gradientFrame.height, 1.0))
        if gradientLayer.contentsAreFlipped() {
            gradientLayer.startPoint = start
            gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        } else {
            gradientLayer.startPoint = CGPoint(x: start.x, y: 1.0 - start.y)
            gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.0)
        }
        CATransaction.commit()
        self.updatePatternLayers(geometry: geometry, content: content)
        if content.pattern == nil || self.glyph != nil {
            self.onContentReady?()
        }
    }

    public func animatePatternTransition() {
        guard let mask = patternTintLayer?.mask else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1, 1.14, 1]
        animation.keyTimes = [0, 0.45, 1]
        animation.duration = 0.4
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        mask.add(animation, forKey: "giftBuilder.pattern")
    }

    private func removePatternLayers() {
        self.patternTintLayer?.removeFromSuperlayer()
        self.patternTintLayer = nil
        self.patternItemLayers.removeAll()
    }

    private func updatePatternLayers(geometry: UniqueGiftBackgroundGeometry, content: UniqueGiftBackgroundContent) {
        guard let glyph = self.glyph else {
            self.removePatternLayers()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let tintLayer: CAGradientLayer
        if let current = self.patternTintLayer {
            tintLayer = current
        } else {
            tintLayer = CAGradientLayer()
            tintLayer.type = .radial
            tintLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            tintLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
            tintLayer.mask = CALayer()
            self.addSublayer(tintLayer)
            self.patternTintLayer = tintLayer
        }
        let tintFrame = geometry.patternTintFrame
        tintLayer.frame = tintFrame
        tintLayer.colors = [
            UniqueGiftBackgroundRenderer.color(content.colors.pattern, alpha: UniqueGiftBackgroundGeometry.patternTintAlpha),
            UniqueGiftBackgroundRenderer.color(content.colors.pattern, alpha: 0.0)
        ]
        let mask = tintLayer.mask ?? CALayer()
        mask.frame = tintLayer.bounds
        let items = geometry.patternItems(transitionFraction: self.patternTransitionFraction)
        while self.patternItemLayers.count < items.count {
            let itemLayer = CALayer()
            itemLayer.contentsGravity = .resize
            mask.addSublayer(itemLayer)
            self.patternItemLayers.append(itemLayer)
        }
        for (index, item) in items.enumerated() {
            let itemLayer = self.patternItemLayers[index]
            itemLayer.contents = glyph.template
            itemLayer.frame = item.frame.offsetBy(dx: -tintFrame.minX, dy: -tintFrame.minY)
            itemLayer.opacity = Float(UniqueGiftBackgroundGeometry.patternGlyphAlpha * item.alpha)
        }
        CATransaction.commit()
    }
}

public final class UniqueGiftBackgroundView: NSView {
    private let backgroundLayer = UniqueGiftBackgroundLayer()

    public var onContentReady: (() -> Void)? {
        get { backgroundLayer.onContentReady }
        set { backgroundLayer.onContentReady = newValue }
    }

    public func animatePatternTransition() {
        backgroundLayer.animatePatternTransition()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func makeBackingLayer() -> CALayer {
        return self.backgroundLayer
    }

    public override var isFlipped: Bool {
        return true
    }

    public override var wantsUpdateLayer: Bool {
        return true
    }

    public override func updateLayer() {
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateBackingProperties()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        self.updateBackingProperties()
    }

    private func updateBackingProperties() {
        guard let window = self.window else {
            return
        }
        self.backgroundLayer.renderScale = window.backingScaleFactor
        self.backgroundLayer.renderColorSpace = window.colorSpace?.cgColorSpace
    }

    public var patternTransitionFraction: CGFloat {
        get {
            return self.backgroundLayer.patternTransitionFraction
        }
        set {
            self.backgroundLayer.patternTransitionFraction = newValue
        }
    }

    public func update(context: any AccountContextProtocol, content: UniqueGiftBackgroundContent?, style: UniqueGiftBackgroundStyle, animated: Bool = false) {
        self.backgroundLayer.update(context: context, content: content, style: style, animated: animated)
    }
}
