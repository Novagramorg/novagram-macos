import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import QuartzCore
import AppKit
import TelegramMedia
import ColorPalette
import InlineStickers
import TelegramUtils
import TelegramTheme
import InAppSettings
import InlineStickerLayer


public final class StarsEffectLayer: SimpleLayer {
    private static let particleImage: CGImage? = {
        guard let path = Bundle.main.path(forResource: "particle", ofType: "png") else { return nil }
        return NSImage(contentsOfFile: path)?._cgImage
    }()

    private let emitterLayer = CAEmitterLayer()
    private let emitter = CAEmitterCell()
    private var currentColor: CGColor?
    private var currentSize: CGSize?
    
    public var isPlaying: Bool = true {
        didSet {
            if self.isPlaying != oldValue {
                self.emitterLayer.birthRate = self.isPlaying ? 1.0 : 0.0
            }
        }
    }

    public override init() {
        super.init()
        
        self.addSublayer(self.emitterLayer)
    }
    
    public override init(layer: Any) {
        super.init(layer: layer)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        emitter.name = "emitter"
        emitter.contents = StarsEffectLayer.particleImage
        emitter.birthRate = 6.0
        emitter.lifetime = 1.5
        emitter.velocity = 0.1
        emitter.scaleRange = 0.02
        emitter.alphaRange = 0.1
        emitter.emissionRange = .pi * 2.0
        
        
    }
    
    public func update(color: NSColor, size: CGSize) {
        let resolvedColor = color.cgColor
        let needsSetup = self.emitterLayer.emitterCells == nil
        let colorChanged = self.currentColor != resolvedColor
        let sizeChanged = self.currentSize != size
        guard needsSetup || colorChanged || sizeChanged else {
            return
        }
        if needsSetup {
            self.setup()
            self.emitterLayer.emitterShape = .circle
            self.emitterLayer.emitterMode = .surface
        }
        
        if needsSetup || colorChanged {
            let clearColor = color.withAlphaComponent(0.0).cgColor
            let visibleColor = color.withAlphaComponent(0.58).cgColor
            let staticColorBehavior = createEmitterBehavior(type: "colorOverLife")
            staticColorBehavior.setValue([clearColor, visibleColor, visibleColor, clearColor], forKey: "colors")
            emitter.setValue([staticColorBehavior], forKey: "emitterBehaviors")
        }
        if needsSetup || sizeChanged {
            emitter.scale = (size.width / 32.0) * 0.12
            self.emitterLayer.emitterSize = size
            self.emitterLayer.frame = CGRect(origin: .zero, size: size)
            self.emitterLayer.emitterPosition = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        }
        self.emitterLayer.emitterCells = [emitter]
        self.emitterLayer.seed = UInt32.random(in: .min ..< .max)
        self.currentColor = resolvedColor
        self.currentSize = size
    }
}



protocol PremiumStatusRenderHost: AnyObject {
    var statusHostLayer: CALayer? { get }
    var statusHostSize: NSSize { get }
    func setStatusHostSize(_ size: NSSize)
    var statusHostAlpha: CGFloat { get }
    var statusVisibilityView: NSView? { get }
    var statusVisibleRect: NSRect { get }
    var statusWindow: NSWindow? { get }
    func statusClearTooltip()
    func statusDidUpdate()
}

final class PremiumStatusRenderer {
    private final class StatusConfiguration {
        let account: ObjectIdentifier
        let inlinePacksContext: ObjectIdentifier?
        let size: NSSize
        let loops: Bool
        let isSelected: Bool
        let tint: NSColor
        let hasCustomColor: Bool

        init(account: Account, inlinePacksContext: InlineStickersContext?, size: NSSize, loops: Bool, isSelected: Bool, color: NSColor?) {
            self.account = ObjectIdentifier(account)
            self.inlinePacksContext = inlinePacksContext.map(ObjectIdentifier.init)
            self.size = size
            self.loops = loops
            self.isSelected = isSelected
            self.tint = isSelected ? theme.colors.underSelectedColor : color ?? theme.colors.accent
            self.hasCustomColor = color != nil
        }

        func matchesSource(account: Account, inlinePacksContext: InlineStickersContext?, loops: Bool) -> Bool {
            return self.account == ObjectIdentifier(account) && self.inlinePacksContext == inlinePacksContext.map(ObjectIdentifier.init) && self.loops == loops
        }

        func matches(account: Account, inlinePacksContext: InlineStickersContext?, size: NSSize, loops: Bool, isSelected: Bool, color: NSColor?, file: TelegramMediaFile?) -> Bool {
            guard matchesSource(account: account, inlinePacksContext: inlinePacksContext, loops: loops), self.size == size else {
                return false
            }
            let tint = isSelected ? theme.colors.underSelectedColor : color ?? theme.colors.accent
            let sameTint = self.isSelected == isSelected && (self.tint === tint || self.tint.isEqual(tint))
            if sameTint && self.hasCustomColor == (color != nil) {
                return true
            }
            guard let file, !isDefaultStatusesPackId(file.emojiReference) else {
                return false
            }
            return !file.paintToText || sameTint
        }
    }

    private weak var host: PremiumStatusRenderHost?
    private(set) var imageLayer: SimpleLayer?
    private(set) var animateLayer: InlineStickerItemLayer?
    private var statusConfiguration: StatusConfiguration?
    private var statusSelected: Bool? = nil
    private(set) var starsLayer: StarsEffectLayer?
    private let peerObservation = PremiumStatusPeerObservation()
    private(set) var lite: Bool = false

    init(host: PremiumStatusRenderHost) {
        self.host = host
    }

    var hasAnimatedContent: Bool {
        return animateLayer != nil || starsLayer != nil
    }

    private func focus(_ size: NSSize) -> NSRect {
        return NSRect(origin: .zero, size: host?.statusHostSize ?? .zero).focus(size)
    }

    func layout() {
        var offset: CGFloat = 0
        if let imageLayer = imageLayer {
            var rect = focus(imageLayer.frame.size)
            rect.origin.x = 0
            imageLayer.frame = rect
            offset += rect.maxX - 7
        }
        if let animateLayer = self.animateLayer {
            var rect = focus(animateLayer.frame.size)
            rect.origin.x = offset
            animateLayer.frame = rect
        }
    }

    func set(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, color: NSColor?, isSelected: Bool, isBig: Bool, animated: Bool, playTwice: Bool = true, isLite: Bool, autoupdate: Bool = true) {
        guard let host = self.host else {
            return
        }

        self.lite = isLite
        
        if let size = PremiumStatusControl.controlSize(peer, isBig, left: left) {
            host.setStatusHostSize(size)
        }
        host.statusHostLayer?.opacity = color != nil && peer.emojiStatus != nil ? 0.4 : 1

        if (peer.isFake || peer.isScam || peer.isPremium || peer.isVerified) && !left, ((peer.isPremium && peer.emojiStatus == nil) || !peer.isPremium || peer.isFake || peer.isScam || peer.isVerified) && !left  {

            let current: SimpleLayer
            if let layer = self.imageLayer {
                current = layer
            } else {
                current = SimpleLayer()
                current.masksToBounds = false
                self.imageLayer = current
                host.statusHostLayer?.addSublayer(current)
            }
            let image: CGImage?
            
            if peer.isVerified {
                image = isSelected ? (left ? theme.icons.verify_dialog_active_left : theme.icons.verifyDialogActive) : (left ? theme.icons.verify_dialog_left : theme.icons.verifyDialog)
            } else if peer.isScam {
                image = isSelected ? theme.icons.scamActive : theme.icons.scam
            } else if peer.isFake {
                image = isSelected ? theme.icons.fakeActive : theme.icons.fake
            } else if peer.isPremium {
                if isBig {
                    let color = color ?? theme.colors.accent
                    if isSelected {
                        let under = theme.colors.underSelectedColor
                        image = theme.resourceCache.image(Int32(color.rgb + 1000), {
                            generatePremium(false, color: under)
                        })
                    } else {
                        image = theme.resourceCache.image(Int32(color.rgb + 1001), {
                            generatePremium(false, color: color)
                        })
                    }
                } else {
                    if isSelected {
                        let under = theme.colors.underSelectedColor
                        image = theme.resourceCache.image(Int32(under.rgb + 1003), {
                            return generatePremium(false, color: under, small: true)
                        })
                    } else if let color = color {
                        image = theme.resourceCache.image(Int32(color.rgb + 1002), {
                            return generatePremium(false, color: color, small: true)
                        })
                    } else {
                        let under = theme.colors.accent
                        image = theme.resourceCache.image(Int32(under.rgb + 1004), {
                            return generatePremium(false, color: under, small: true)
                        })
                    }
                }
            } else {
                image = nil
            }
            if let image = image {
                current.contents = image
                current.contentsScale = System.backingScale
                current.contentsGravity = .resizeAspectFill
                var rect = focus(image.backingSize)
                rect.origin.x = 0
                current.frame = rect
            } else {
                current.contents = nil
            }
        } else if let imageLayer = imageLayer {
            performSublayerRemoval(imageLayer, animated: animated, scale: true)
            self.imageLayer = nil
        }
        
        let makeStatus:(Int64)->Void = { [weak self] fileId in
            guard let self, let host = self.host else {
                return
            }
            let current: InlineStickerItemLayer
            
            let getColors:(TelegramMediaFile?)->[LottieColor] = { file in
                var colors: [LottieColor] = []
                if let file = file {
                    if isDefaultStatusesPackId(file.emojiReference) || file.paintToText {
                        if isSelected {
                            colors.append(.init(keyPath: "", color: theme.colors.underSelectedColor))
                        } else {
                            colors.append(.init(keyPath: "", color: color ?? theme.colors.accent))
                        }
                    }
                }
                return colors
            }
            
            let loops = isBig && !playTwice
            
            if let layer = self.animateLayer, layer.fileId == fileId,
               layer.file != nil || !layer.hasFileResolutionResult,
               self.statusConfiguration?.matches(account: account, inlinePacksContext: inlinePacksContext, size: host.statusHostSize, loops: loops, isSelected: isSelected, color: color, file: layer.file) == true {
                current = layer
                if isDefaultStatusesPackId(layer.file?.emojiReference), color != nil {
                    host.statusHostLayer?.opacity = 0.4
                } else {
                    host.statusHostLayer?.opacity = Float(host.statusHostAlpha)
                }
                
            } else {
                let animated = animated && statusSelected == isSelected
                var previousStopped: Bool = false
                if self.animateLayer?.fileId == fileId, self.statusConfiguration?.matchesSource(account: account, inlinePacksContext: inlinePacksContext, loops: loops) == true {
                    previousStopped = self.animateLayer?.stopped ?? false
                }
                if let animateLayer = animateLayer {
                    animateLayer.fileDidUpdate = nil
                    let contents = animateLayer.contents
                    animateLayer.isPlayable = false
                    animateLayer.contents = contents
                    performSublayerRemoval(animateLayer, animated: animated, scale: true)
                    self.animateLayer = nil
                }
                current = InlineStickerItemLayer(account: account, inlinePacksContext: inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: host.statusHostSize, playPolicy: loops ? .loop : .playCount(2), checkStatus: true, getColors: getColors)
                
                current.fileDidUpdate = { [weak host] file in
                    guard let host else {
                        return
                    }
                    if isDefaultStatusesPackId(file?.emojiReference), color != nil {
                        host.statusHostLayer?.opacity = 0.4
                    } else {
                        host.statusHostLayer?.opacity = Float(host.statusHostAlpha)
                    }
                }
                current.fileDidUpdate?(current.file)
                
                current.stopped = previousStopped
                current.superview = host.statusVisibilityView
                self.animateLayer = current
                self.statusConfiguration = StatusConfiguration(account: account, inlinePacksContext: inlinePacksContext, size: host.statusHostSize, loops: loops, isSelected: isSelected, color: color)
                host.statusHostLayer?.addSublayer(current)
                
                if animated {
                    current.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.animateScale(from: 0.1, to: 1, duration: 0.2)
                }
            }
        }
        
        if let status = peer.emojiStatus, !peer.isFake && !peer.isScam, !left {
            let fileId: Int64 = status.fileId
            makeStatus(fileId)
        } else if let status = peer.verificationIconFileId, left {
            let fileId: Int64 = status
            makeStatus(fileId)
        } else if let animateLayer = animateLayer {
            animateLayer.fileDidUpdate = nil
            let contents = animateLayer.contents
            animateLayer.isPlayable = false
            animateLayer.contents = contents
            performSublayerRemoval(animateLayer, animated: animated)
            self.animateLayer = nil
            self.statusConfiguration = nil
        }
        
        if let status = peer.emojiStatus, case let .starGift(_, _, _, _, _, innerColor, _, _, _) = status.content, !left {
            let starsLayer: StarsEffectLayer
            if let current = self.starsLayer {
                starsLayer = current
            } else {
                starsLayer = StarsEffectLayer()
                host.statusHostLayer?.insertSublayer(starsLayer, at: 0)
                self.starsLayer = starsLayer
            }
            let availableSize = NSMakeSize(20, 20)
            let side = floor(availableSize.width * 1.25)
            let starsFrame = CGRect(origin: NSMakePoint(0, 0), size: availableSize).focus(CGSize(width: side, height: side))
            starsLayer.frame = starsFrame.offsetBy(dx: imageLayer != nil ? imageLayer!.frame.width : 0, dy: 0)
            starsLayer.update(color: isSelected ? theme.colors.underSelectedColor : NSColor(UInt32(innerColor)), size: starsFrame.size)
            
        } else {
            if let starsLayer = self.starsLayer {
                starsLayer.isPlaying = false
                self.starsLayer = nil
                starsLayer.removeFromSuperlayer()
            }
            host.statusClearTooltip()
        }
        
        self.statusSelected = isSelected
        
        host.statusDidUpdate()
        
        self.peerObservation.update(peer: peer, account: account, enabled: autoupdate) { [weak self] updated in
            self?.set(updated, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: isLite, autoupdate: autoupdate)
        }
    }

    func updatePlayback() {
        guard let host else {
            return
        }
        var isKeyWindow: Bool = false
        if let window = host.statusWindow {
            if !window.canBecomeKey {
                isKeyWindow = true
            } else {
                isKeyWindow = window.isKeyWindow
            }
        }
        let visibleRect = host.statusVisibleRect
        if let layer = self.animateLayer, layer.superview != nil {
            layer.isPlayable = NSIntersectsRect(layer.frame, visibleRect) && isKeyWindow && !lite
        }
        if let starsLayer = self.starsLayer {
            starsLayer.isPlaying = NSIntersectsRect(starsLayer.frame, visibleRect) && isKeyWindow && !lite
        }
    }
}

public final class PremiumStatusControl : Control, PremiumStatusRenderHost {
    private lazy var renderer = PremiumStatusRenderer(host: self)

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        userInteractionEnabled = false
        layer?.masksToBounds = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var statusHostLayer: CALayer? { layer }
    var statusHostSize: NSSize { frame.size }
    func setStatusHostSize(_ size: NSSize) { setFrameSize(size) }
    var statusHostAlpha: CGFloat { alphaValue }
    var statusVisibilityView: NSView? { self }
    var statusVisibleRect: NSRect { visibleRect }
    var statusWindow: NSWindow? { window }
    func statusClearTooltip() { appTooltip = nil }
    func statusDidUpdate() {
        updateAnimatableContent()
        updateListeners()
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        renderer.layout()
    }
    
    public func set(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, color: NSColor?, isSelected: Bool, isBig: Bool, animated: Bool, playTwice: Bool = true, isLite: Bool, autoupdate: Bool = true) {
        renderer.set(peer, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: isLite, autoupdate: autoupdate)
    }
    
    @objc public func updateAnimatableContent() -> Void {
        renderer.updatePlayback()
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
        NotificationCenter.default.removeObserver(self)
    }
    
    private var animatableContentObserver: AnimatableContentObserver?

    private func updateListeners() {
        guard window != nil, renderer.hasAnimatedContent else {
            animatableContentObserver = nil
            return
        }
        if animatableContentObserver == nil {
            animatableContentObserver = AnimatableContentObserver()
        }
        animatableContentObserver?.update(for: self, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }
    
    public static func control(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, isSelected: Bool, isBig: Bool = false, playTwice: Bool = false, color: NSColor? = nil, cached: PremiumStatusControl?, animated: Bool, autoupdate: Bool = true) -> PremiumStatusControl? {
        var current: PremiumStatusControl? = nil
        if (peer.isVerified || peer.isScam || peer.isFake || peer.isPremium || peer.emojiStatus != nil) && !left || (left && peer.verificationIconFileId != nil) {
            current = cached ?? PremiumStatusControl(frame: .zero)
        }
                
        current?.set(peer, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: TelegramUtilsHooks.shared.isLite(.emoji), autoupdate: autoupdate)
        return current
    }
    
    public static func hasControl(_ peer: Peer, left: Bool) -> Bool {
        return (peer.isVerified || peer.isScam || peer.isFake || peer.isPremium || peer.emojiStatus != nil) && !left || (left && peer.verificationIconFileId != nil)
    }
    public static func controlSize(_ peer: Peer, _ isBig: Bool, left: Bool) -> NSSize? {
        if hasControl(peer, left: left) {
            var addition: NSSize = .zero
            if peer.isScam || peer.isFake {
                addition.width += 20
            }
            if peer.isVerified && peer.emojiStatus != nil, !left {
                addition.width += 18
            }
            return isBig ? NSMakeSize(20 + addition.width, 20 + addition.height) : NSMakeSize(16 + addition.width, 16 + addition.height)
        } else {
            return nil
        }
    }
}

public final class PremiumStatusLayer: SimpleLayer, PremiumStatusRenderHost {
    private lazy var renderer = PremiumStatusRenderer(host: self)
    public weak var visibilityView: NSView? {
        didSet {
            if visibilityView !== oldValue {
                renderer.animateLayer?.superview = visibilityView
                updateListeners()
                updatePlayback()
            }
        }
    }

    public override init() {
        super.init()
        anchorPoint = .zero
        masksToBounds = false
        isOpaque = true
        edgeAntialiasingMask = []
        if #available(macOS 10.15, *) {
            cornerCurve = .continuous
        }
    }

    public override init(layer: Any) {
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var statusHostLayer: CALayer? { self }
    var statusHostSize: NSSize { bounds.size }
    func setStatusHostSize(_ size: NSSize) {
        if bounds.size != size {
            bounds = CGRect(origin: .zero, size: size)
        }
    }
    var statusHostAlpha: CGFloat { 1 }
    var statusVisibilityView: NSView? { visibilityView }
    var statusVisibleRect: NSRect {
        guard let view = visibilityView else { return .zero }
        var origin = NSPoint(x: frame.minX, y: frame.minY)
        var parent = superlayer
        let root = view.layer
        while let current = parent, current !== root {
            origin.x += current.frame.minX - current.bounds.minX
            origin.y += current.frame.minY - current.bounds.minY
            parent = current.superlayer
        }
        guard parent === root else { return .zero }
        return view.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
    }
    var statusWindow: NSWindow? { visibilityView?.window }
    func statusClearTooltip() {}
    func statusDidUpdate() {
        renderer.layout()
        updateListeners()
        updatePlayback()
    }

    public var hasAnimatedContent: Bool { renderer.hasAnimatedContent }

    public func hostDidMoveToWindow() {
        updateListeners()
        updatePlayback()
    }

    public func set(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, color: NSColor?, isSelected: Bool, isBig: Bool, animated: Bool, playTwice: Bool = true, isLite: Bool, autoupdate: Bool = true) {
        renderer.set(peer, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: isLite, autoupdate: autoupdate)
    }

    @objc public func updatePlayback() {
        renderer.updatePlayback()
    }

    private var animatableContentObserver: AnimatableContentObserver?

    private func updateListeners() {
        guard let view = visibilityView, view.window != nil, renderer.hasAnimatedContent else {
            animatableContentObserver = nil
            return
        }
        if animatableContentObserver == nil {
            animatableContentObserver = AnimatableContentObserver()
        }
        animatableContentObserver?.update(for: view, target: self, selector: #selector(updatePlayback), options: [.contentBounds, .documentFrame, .ownFrame])
    }

    public static func layer(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, isSelected: Bool, isBig: Bool = false, playTwice: Bool = false, color: NSColor? = nil, cached: PremiumStatusLayer?, animated: Bool, autoupdate: Bool = true) -> PremiumStatusLayer? {
        guard PremiumStatusControl.hasControl(peer, left: left) else {
            return nil
        }
        let current = cached ?? PremiumStatusLayer()
        current.set(peer, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: TelegramUtilsHooks.shared.isLite(.emoji), autoupdate: autoupdate)
        return current
    }
}
