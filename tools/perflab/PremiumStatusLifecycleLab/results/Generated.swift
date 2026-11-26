import Cocoa
import TGUIKit
public final class ReferencePremiumStatusControl : Control {
    private var imageLayer: SimpleLayer?
    private var animateLayer: InlineStickerItemLayer?
    private var statusSelected: Bool? = nil
    private var starsLayer: StarsEffectLayer?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        userInteractionEnabled = false
        layer?.masksToBounds = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let peerObservation = PremiumStatusPeerObservation()
    
    private var lite: Bool = false
    
    public override func layout() {
        super.layout()
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
    
    public func set(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, color: NSColor?, isSelected: Bool, isBig: Bool, animated: Bool, playTwice: Bool = true, isLite: Bool, autoupdate: Bool = true) {
        
        
        self.lite = isLite
        
        if let size = ReferencePremiumStatusControl.controlSize(peer, isBig, left: left) {
            setFrameSize(size)
        }
        self.layer?.opacity = color != nil && peer.emojiStatus != nil ? 0.4 : 1

        if (peer.isFake || peer.isScam || peer.isPremium || peer.isVerified) && !left, ((peer.isPremium && peer.emojiStatus == nil) || !peer.isPremium || peer.isFake || peer.isScam || peer.isVerified) && !left  {

            let current: SimpleLayer
            if let layer = self.imageLayer {
                current = layer
            } else {
                current = SimpleLayer()
                current.masksToBounds = false
                self.imageLayer = current
                self.layer?.addSublayer(current)
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
            guard let self else {
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
            
            var updated: Bool = false
            
            if statusSelected != isSelected, let layer = self.animateLayer {
                if layer.file?.fileId.id == fileId {
                    if !getColors(layer.file).isEmpty {
                        updated = true
                    }
                }
            }
            
            if let layer = self.animateLayer, layer.file?.fileId.id == fileId && !updated {
                current = layer
                if isDefaultStatusesPackId(layer.file?.emojiReference), color != nil {
                    self.layer?.opacity = Float(alphaValue)
                } else {
                    self.layer?.opacity = Float(alphaValue)
                }
                
            } else {
                let animated = animated && statusSelected == isSelected
                var previousStopped: Bool = false
                if self.animateLayer?.file?.fileId.id == fileId {
                    previousStopped = self.animateLayer?.stopped ?? false
                }
                if let animateLayer = animateLayer {
                    performSublayerRemoval(animateLayer, animated: animated, scale: true)
                    self.animateLayer = nil
                }
                current = InlineStickerItemLayer(account: account, inlinePacksContext: inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: frame.size, playPolicy: isBig && !playTwice ? .loop : .playCount(2), checkStatus: true, getColors: getColors)
                
                current.fileDidUpdate = { [weak self] file in
                    guard let `self` = self else {
                        return
                    }
                    if isDefaultStatusesPackId(file?.emojiReference), color != nil {
                        self.layer?.opacity = 0.4
                    } else {
                        self.layer?.opacity = Float(self.alphaValue)
                    }
                }
                current.fileDidUpdate?(current.file)
                
                current.stopped = previousStopped
                current.superview = self
                self.animateLayer = current
                self.layer?.addSublayer(current)
                
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
            performSublayerRemoval(animateLayer, animated: animated)
            self.animateLayer = nil
        }
        
        if let status = peer.emojiStatus, case let .starGift(_, _, _, _, _, innerColor, _, _, _) = status.content, !left {
            let starsLayer: StarsEffectLayer
            if let current = self.starsLayer {
                starsLayer = current
            } else {
                starsLayer = StarsEffectLayer()
                self.layer?.insertSublayer(starsLayer, at: 0)
                self.starsLayer = starsLayer
            }
            let availableSize = NSMakeSize(20, 20)
            let side = floor(availableSize.width * 1.25)
            let starsFrame = CGRect(origin: NSMakePoint(0, 0), size: availableSize).focus(CGSize(width: side, height: side))
            starsLayer.frame = starsFrame.offsetBy(dx: imageLayer != nil ? imageLayer!.frame.width : 0, dy: 0)
            starsLayer.update(color: isSelected ? theme.colors.underSelectedColor : NSColor(UInt32(innerColor)), size: starsFrame.size)
            
           // self.appTooltip = title
            
        } else {
            if let starsLayer = self.starsLayer {
                self.starsLayer = nil
                starsLayer.removeFromSuperlayer()
            }
            self.appTooltip = nil
        }
        

        
        self.statusSelected = isSelected
        
        self.updateAnimatableContent()
        self.updateListeners()
        
        needsLayout = true
        
        self.peerObservation.update(peer: peer, account: account, enabled: autoupdate) { [weak self] updated in
            self?.set(updated, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: isLite, autoupdate: autoupdate)
        }
        
    }
    

    
    @objc public func updateAnimatableContent() -> Void {
        var isKeyWindow: Bool = false
        if let window = window {
            if !window.canBecomeKey {
                isKeyWindow = true
            } else {
                isKeyWindow = window.isKeyWindow
            }
        }
        if let layer = self.animateLayer, let superview = layer.superview {
            layer.isPlayable = NSIntersectsRect(layer.frame, superview.visibleRect) && isKeyWindow && !lite
        }
        if let starsLayer = self.starsLayer {
            starsLayer.isPlaying = !self.visibleRect.isEmpty && isKeyWindow && !lite
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
        NotificationCenter.default.removeObserver(self)
    }
    
    private let animatableContentObserver = AnimatableContentObserver()

    private func updateListeners() {
        animatableContentObserver.update(for: self, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }
    
    public static func control(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, isSelected: Bool, isBig: Bool = false, playTwice: Bool = false, color: NSColor? = nil, cached: ReferencePremiumStatusControl?, animated: Bool, autoupdate: Bool = true) -> ReferencePremiumStatusControl? {
        var current: ReferencePremiumStatusControl? = nil
        if (peer.isVerified || peer.isScam || peer.isFake || peer.isPremium || peer.emojiStatus != nil) && !left || (left && peer.verificationIconFileId != nil) {
            current = cached ?? ReferencePremiumStatusControl(frame: .zero)
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

public final class CandidatePremiumStatusControl : Control {
    private var imageLayer: SimpleLayer?
    private var animateLayer: InlineStickerItemLayer?
    private var statusSelected: Bool? = nil
    private var starsLayer: StarsEffectLayer?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        userInteractionEnabled = false
        layer?.masksToBounds = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let peerObservation = PremiumStatusPeerObservation()
    
    private var lite: Bool = false
    
    public override func layout() {
        super.layout()
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
    
    public func set(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, color: NSColor?, isSelected: Bool, isBig: Bool, animated: Bool, playTwice: Bool = true, isLite: Bool, autoupdate: Bool = true) {
        
        
        self.lite = isLite
        
        if let size = CandidatePremiumStatusControl.controlSize(peer, isBig, left: left) {
            setFrameSize(size)
        }
        self.layer?.opacity = color != nil && peer.emojiStatus != nil ? 0.4 : 1

        if (peer.isFake || peer.isScam || peer.isPremium || peer.isVerified) && !left, ((peer.isPremium && peer.emojiStatus == nil) || !peer.isPremium || peer.isFake || peer.isScam || peer.isVerified) && !left  {

            let current: SimpleLayer
            if let layer = self.imageLayer {
                current = layer
            } else {
                current = SimpleLayer()
                current.masksToBounds = false
                self.imageLayer = current
                self.layer?.addSublayer(current)
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
            guard let self else {
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
            
            var updated: Bool = false
            
            if statusSelected != isSelected, let layer = self.animateLayer {
                if layer.file?.fileId.id == fileId {
                    if !getColors(layer.file).isEmpty {
                        updated = true
                    }
                }
            }
            
            if let layer = self.animateLayer, layer.file?.fileId.id == fileId && !updated {
                current = layer
                if isDefaultStatusesPackId(layer.file?.emojiReference), color != nil {
                    self.layer?.opacity = Float(alphaValue)
                } else {
                    self.layer?.opacity = Float(alphaValue)
                }
                
            } else {
                let animated = animated && statusSelected == isSelected
                var previousStopped: Bool = false
                if self.animateLayer?.file?.fileId.id == fileId {
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
                current = InlineStickerItemLayer(account: account, inlinePacksContext: inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: frame.size, playPolicy: isBig && !playTwice ? .loop : .playCount(2), checkStatus: true, getColors: getColors)
                
                current.fileDidUpdate = { [weak self] file in
                    guard let `self` = self else {
                        return
                    }
                    if isDefaultStatusesPackId(file?.emojiReference), color != nil {
                        self.layer?.opacity = 0.4
                    } else {
                        self.layer?.opacity = Float(self.alphaValue)
                    }
                }
                current.fileDidUpdate?(current.file)
                
                current.stopped = previousStopped
                current.superview = self
                self.animateLayer = current
                self.layer?.addSublayer(current)
                
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
        }
        
        if let status = peer.emojiStatus, case let .starGift(_, _, _, _, _, innerColor, _, _, _) = status.content, !left {
            let starsLayer: StarsEffectLayer
            if let current = self.starsLayer {
                starsLayer = current
            } else {
                starsLayer = StarsEffectLayer()
                self.layer?.insertSublayer(starsLayer, at: 0)
                self.starsLayer = starsLayer
            }
            let availableSize = NSMakeSize(20, 20)
            let side = floor(availableSize.width * 1.25)
            let starsFrame = CGRect(origin: NSMakePoint(0, 0), size: availableSize).focus(CGSize(width: side, height: side))
            starsLayer.frame = starsFrame.offsetBy(dx: imageLayer != nil ? imageLayer!.frame.width : 0, dy: 0)
            starsLayer.update(color: isSelected ? theme.colors.underSelectedColor : NSColor(UInt32(innerColor)), size: starsFrame.size)
            
           // self.appTooltip = title
            
        } else {
            if let starsLayer = self.starsLayer {
                starsLayer.isPlaying = false
                self.starsLayer = nil
                starsLayer.removeFromSuperlayer()
            }
            self.appTooltip = nil
        }
        

        
        self.statusSelected = isSelected
        
        self.updateAnimatableContent()
        self.updateListeners()
        
        needsLayout = true
        
        self.peerObservation.update(peer: peer, account: account, enabled: autoupdate) { [weak self] updated in
            self?.set(updated, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: isLite, autoupdate: autoupdate)
        }
        
    }
    

    
    @objc public func updateAnimatableContent() -> Void {
        var isKeyWindow: Bool = false
        if let window = window {
            if !window.canBecomeKey {
                isKeyWindow = true
            } else {
                isKeyWindow = window.isKeyWindow
            }
        }
        if let layer = self.animateLayer, let superview = layer.superview {
            layer.isPlayable = NSIntersectsRect(layer.frame, superview.visibleRect) && isKeyWindow && !lite
        }
        if let starsLayer = self.starsLayer {
            starsLayer.isPlaying = NSIntersectsRect(starsLayer.frame, self.visibleRect) && isKeyWindow && !lite
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
        NotificationCenter.default.removeObserver(self)
    }
    
    private var animatableContentObserver: AnimatableContentObserver?

    private func updateListeners() {
        guard window != nil, animateLayer != nil || starsLayer != nil else {
            animatableContentObserver = nil
            return
        }
        if animatableContentObserver == nil {
            animatableContentObserver = AnimatableContentObserver()
        }
        animatableContentObserver?.update(for: self, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }
    
    public static func control(_ peer: Peer, account: Account, inlinePacksContext: InlineStickersContext?, left: Bool, isSelected: Bool, isBig: Bool = false, playTwice: Bool = false, color: NSColor? = nil, cached: CandidatePremiumStatusControl?, animated: Bool, autoupdate: Bool = true) -> CandidatePremiumStatusControl? {
        var current: CandidatePremiumStatusControl? = nil
        if (peer.isVerified || peer.isScam || peer.isFake || peer.isPremium || peer.emojiStatus != nil) && !left || (left && peer.verificationIconFileId != nil) {
            current = cached ?? CandidatePremiumStatusControl(frame: .zero)
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

