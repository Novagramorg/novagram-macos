import Cocoa
import Postbox
import TelegramCore
import TelegramMedia
import TGUIKit
import SwiftSignalKit
import TelegramMedia
import TelegramMediaResources
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import DiceCache


public class MediaAnimatedStickerView: ChatMediaContentView {

    private let loadResourceDisposable = MetaDisposable()
    private let fetchPremiumDisposable = MetaDisposable()
    private let stateDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private let playThrottleDisposable = MetaDisposable()
    private let playerView: LottiePlayerView = LottiePlayerView(frame: NSMakeRect(0, 0, 240, 240))
    private var placeholderView: StickerShimmerEffectView?
    private let firstFrameReadyValue = ValuePromise(false, ignoreRepeated: true)

    public var firstFrameReady: Signal<Bool, NoError> {
        return firstFrameReadyValue.get()
    }

    public var playOnHover: Bool? = nil
    
    private let thumbView = TransformImageView()
    private var sticker:LottieAnimation? = nil {
        didSet {
            if oldValue != sticker {
                self.previousAccept = false
                if sticker == nil {
                    self.playerView.set(nil)
                }
            }
            updatePlayerIfNeeded()
        }
    }
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(self.playerView)
        addSubview(self.thumbView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func play() {
        if self.playerView.animation?.playPolicy == .framesCount(0) {
            playerView.set(self.playerView.animation?.withUpdatedPolicy(.onceEnd), reset: false)
        } else {
            playerView.playAgain()
        }
    }
    
    public override func clean() {
        stateDisposable.set(nil)
        loadResourceDisposable.set(nil)
        playThrottleDisposable.set(nil)
        fetchDisposable.set(nil)
        fetchPremiumDisposable.set(nil)
    }
    
    deinit {
        loadResourceDisposable.dispose()
        stateDisposable.dispose()
        playThrottleDisposable.dispose()
        fetchDisposable.dispose()
        fetchPremiumDisposable.dispose()
    }
    
    public func removeNotificationListeners() {
        NotificationCenter.default.removeObserver(self)
    }
    
    public override func viewDidUpdatedDynamicContent() {
        super.viewDidUpdatedDynamicContent()
        updatePlayerIfNeeded()
    }
    
    private var previousAccept: Bool = false
    
    public var overridePlayValue: Bool? = nil {
        didSet {
            updatePlayerIfNeeded()
        }
    }
    
    @objc public func updatePlayerIfNeeded() {
        
        var accept = ((self.window != nil && self.window!.isKeyWindow) || (self.window != nil && !(self.window is Window))) && !NSIsEmptyRect(self.visibleRect) && !self.isDynamicContentLocked && self.sticker != nil
                
        let parameters = self.parameters as? ChatAnimatedStickerMediaLayoutParameters
        
        
        accept = parameters?.alwaysAccept ?? accept

        if playOnHover == true {
            accept = true
        }
        if TelegramUtilsHooks.shared.isLite(.stickers) == true, parent != nil {
            if !mouseInside(), self.playerView.currentState == .playing {
                accept = true
            } else {
                accept = accept && mouseInside()
            }
            
        }
        
        if NSIsEmptyRect(self.visibleRect) || self.window == nil {
            accept = false
        }
        
        
        if let value = overridePlayValue {
            accept = value
        }
       
        let delayPlay = accept && !nextForceAccept && self.sticker != nil
        if accept && self.sticker != nil {
            nextForceAccept = false
        }
        
        if let sticker = self.sticker, previousAccept {
            switch sticker.playPolicy {
            case .once, .onceEnd:
                return
            default:
                break
            }
        }
        if previousAccept != accept {
            var signal = Signal<Void, NoError>.single(Void())
            if delayPlay {
                signal = signal |> delay(0.01, queue: .mainQueue())
            }
            self.playThrottleDisposable.set(signal.start(next: { [weak self] in
                guard let `self` = self else {
                    return
                }
                self.playerView.set(accept ? self.sticker : nil, reset: true)
                self.previousAccept = accept
            }))
        }
        previousAccept = accept
        self.playerView.updateVisible()
        
    }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        self.updatePlayerIfNeeded()
    }
    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        self.updatePlayerIfNeeded()
    }
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        self.updatePlayerIfNeeded()
    }
    
    
    public func setColors(_ colors: [LottieColor]) {
        self.playerView.setColors(colors)
    }
    
    private var nextForceAccept: Bool = false

    
    public override var canSpamClicks: Bool {
        return true
    }
    
    public override func previewMediaIfPossible() -> Bool {
        if let table = table, let context = context, let window = window as? Window {
            startModalPreviewHandle(table, window: window, context: context)
        }
        return true
    }
    
//    private var test: MediaObjectToAvatar? = nil
    
    public override func executeInteraction(_ isControl: Bool) {
        if let window = window as? Window {
            if let context = context, let peerId = parent?.id.peerId, let media = media as? TelegramMediaFile, !media.isEmojiAnimatedSticker, let reference = media.stickerReference {
                showModal(with:ChatMediaUIHooks.shared.makeStickerPackPreview(context, peerId, [.stickers(reference)]), for:window)
            } else if let media = media as? TelegramMediaFile, let sticker = media.stickerText, !sticker.isEmpty {
                self.playerView.playIfNeeded(true)
                parameters?.runEmojiScreenEffect(sticker)
                
            }
        }
    }
    
    public override func playIfNeeded(_ playSound: Bool = false) {
        playerView.playIfNeeded(playSound)
    }
    
    public func playAgain() {
        self.playerView.playIfNeeded(true)
    }
    
    public var chatLoopAnimated: Bool {
        if let context = self.context {
            return context.autoplayMedia.loopAnimatedStickers
        }
        return true
    }
    
    private let animatableContentObserver = AnimatableContentObserver()

    public func updateListeners() {
        animatableContentObserver.update(for: self, target: self, selector: #selector(updatePlayerIfNeeded), options: [.contentBounds, .documentFrame])
    }
    
    
    public override func willRemove() {
        super.willRemove()
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    public override func viewDidMoveToSuperview() {
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    public override func viewDidMoveToWindow() {
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    public override func update(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message? = nil, table: TableView?, parameters: ChatMediaLayoutParameters? = nil, animated: Bool, positionFlags: LayoutPositionFlags? = nil, approximateSynchronousValue: Bool = false) {
        
        
        let prev = self.media as? TelegramMediaFile
        
        guard let file = media as? TelegramMediaFile else { return }

        var updated = self.media != nil ? !file.isSemanticallyEqual(to: self.media!) : true
                
        
        if parent?.stableId != self.parent?.stableId {
            self.sticker = nil
            updated = true
        } else if parent == nil && file.fileId != prev?.fileId {
            self.sticker = nil
            updated = true
        }
               

        self.nextForceAccept = approximateSynchronousValue || parent?.id.namespace == Namespaces.Message.Local

        super.update(with: media, size: size, context: context, parent: parent, table: table, parameters: parameters, animated: animated, positionFlags: positionFlags, approximateSynchronousValue: approximateSynchronousValue)
        
        
        let mirror = parameters?.mirror ?? false

        let params = parameters as? ChatAnimatedStickerMediaLayoutParameters
                
        let reference: FileMediaReference
        let mediaResource: MediaResourceReference
        var premiumResource: MediaResourceReference? = nil
        if let message = parent {
            reference = FileMediaReference.message(message: MessageReference(message), media: file)
            mediaResource = reference.resourceReference(file.resource)
            if let effect = file.premiumEffect {
                premiumResource = reference.resourceReference(effect.resource)
            }
        } else if let stickerReference = file.stickerReference {
            if file.resource is CloudStickerPackThumbnailMediaResource {
                reference = FileMediaReference.stickerPack(stickerPack: stickerReference, media: file)
                mediaResource = MediaResourceReference.stickerPackThumbnail(stickerPack: stickerReference, resource: file.resource)
                if let effect = file.premiumEffect {
                    premiumResource = MediaResourceReference.stickerPackThumbnail(stickerPack: stickerReference, resource: effect.resource)
                }
            } else {
                reference = FileMediaReference.stickerPack(stickerPack: stickerReference, media: file)
                mediaResource = reference.resourceReference(file.resource)
                if let effect = file.premiumEffect {
                    premiumResource = reference.resourceReference(effect.resource)
                }
            }
        } else {
            reference = FileMediaReference.standalone(media: file)
            mediaResource = reference.resourceReference(file.resource)
            if let effect = file.premiumEffect {
                premiumResource = reference.resourceReference(effect.resource)
            }
        }
        
        let data: Signal<MediaResourceData, NoError>
        if let resource = file.resource as? LocalBundleResource {
            data = Signal { subscriber in
                if let path = Bundle.main.path(forResource: resource.name, ofType: resource.ext), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedRead]) {
                    subscriber.putNext(MediaResourceData(path: path, offset: 0, size: Int64(data.count), complete: true))
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            } |> runOn(resourcesQueue)
        } else {
            data = context.account.postbox.mediaBox.resourceData(file.resource, attemptSynchronously: approximateSynchronousValue)
        }
        
        if updated {
            firstFrameReadyValue.set(false)
            self.loadResourceDisposable.set((data |> map { resourceData -> Data? in
                if resourceData.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: [.mappedIfSafe]) {
                    if file.isWebm {
                        return resourceData.path.data(using: .utf8)!
                    } else {
                        return data
                    }
                }
                return nil
            } |> deliverOnMainQueue).start(next: { [weak self] data in
                if let data = data, let `self` = self {
                    
                    var playPolicy: LottiePlayPolicy = params?.playPolicy ?? (file.isEmojiAnimatedSticker || !self.chatLoopAnimated ? .loop : .loop)
                    
                    if TelegramUtilsHooks.shared.isLite(.stickers), parent != nil {
                        playPolicy = .toStart(from: 0)
                    }
                    if self.playOnHover == true {
                        playPolicy = .framesCount(0)
                    }
                    var soundEffect: LottieSoundEffect? = nil
                    if file.isEmojiAnimatedSticker, let emoji = file.stickerText {
                        if let file = EmojiesSoundConfiguration.sound(for: emoji, appConfiguration: context.appConfiguration) {
                            soundEffect = LottieSoundEffect(file: file, postbox: context.account.postbox, triggerOn: 1)
                        }
                    }
                    let maximumFps: Int = size.width < 200 && !file.isEmojiAnimatedSticker ? size.width <= 30 ? 30 : 30 : 60
                    let cache: ASCachePurpose = params?.cache ?? (size.width < 200 ? .temporaryLZ4(.effect) : self.parent != nil ? .temporaryLZ4(.chat) : .none)
                    let fitzModifier = file.animatedEmojiFitzModifier
                    
                    
                    let type: LottieAnimationType
                    if file.isWebm {
                        type = .webm
                    } else if file.mimeType == "image/webp" {
                        type = .webp
                    } else {
                        type = .lottie
                    }
                    let effective = size
                    
                    self.sticker = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .media(file.id), size: effective, fitzModifier: fitzModifier, colors: parameters?.colors ?? [], mirror: mirror), type: type, cachePurpose: cache, playPolicy: playPolicy, maximumFps: maximumFps, colors: parameters?.colors ?? [], soundEffect: soundEffect, postbox: self.context?.account.postbox, metalSupport: false)
                    
                    self.fetchStatus = .Local
                } else {
                    self?.sticker = nil
                    self?.fetchStatus = .Remote(progress: 0)
                }
            }))
            
            let aspectSize = file.dimensions?.size.aspectFitted(size) ?? size
            let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: aspectSize, boundingSize: size, intrinsicInsets: NSEdgeInsets(), mirror: mirror)
                               
            if params?.noThumb == false || params == nil {
                self.thumbView.setSignal(signal: cachedMedia(media: file, arguments: arguments, scale: backingScaleFactor), clearInstantly: updated)
                if self.thumbView.image != nil {
                    self.firstFrameReadyValue.set(true)
                }
                
                let hasPlaceholder = (parent == nil || file.immediateThumbnailData != nil) && self.thumbView.image == nil && (params == nil || params!.shimmer)
                if updated {
                    if hasPlaceholder {
                        let current: StickerShimmerEffectView
                        if let local = self.placeholderView {
                            current = local
                        } else {
                            current = StickerShimmerEffectView()
                            current.frame = bounds
                            self.placeholderView = current
                            addSubview(current, positioned: .below, relativeTo: playerView)
                            if animated {
                                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                            }
                        }
                        current.update(backgroundColor: nil, foregroundColor: NSColor(rgb: 0x748391, alpha: 0.2), shimmeringColor: NSColor(rgb: 0x748391, alpha: 0.35), data: file.immediateThumbnailData, size: size)
                        current.updateAbsoluteRect(bounds, within: size)
                    } else {
                        self.removePlaceholder(animated: animated)
                    }
                }
                
                self.thumbView.imageUpdated = { [weak self] value in
                    if value != nil {
                        self?.removePlaceholder(animated: animated)
                        self?.firstFrameReadyValue.set(true)
                    }
                }
                
                if !self.thumbView.isFullyLoaded {

                    let signal: Signal<ImageDataTransformation, NoError>
                        
                    switch file.mimeType {
                    case "image/webp":
                        signal = chatMessageSticker(postbox: context.account.postbox, file: reference, small: size.width <= 5, scale: backingScaleFactor, fetched: true)
                    default:
                        signal = chatMessageAnimatedSticker(postbox: context.account.postbox, file: reference, small: size.width <= 5, scale: backingScaleFactor, size: size, fetched: true, thumbAtFrame: params?.thumbAtFrame ?? 0, isVideo: file.fileName == "webm-preview" || file.isVideoSticker)
                    }
                    self.thumbView.setSignal(signal, cacheImage: { [weak self] result in
                        cacheMedia(result, media: file, arguments: arguments, scale: System.backingScale)
                        self?.removePlaceholder(animated: false)
                    })
                }
                self.thumbView.set(arguments: arguments)
                if updated {
                    self.playerView.removeFromSuperview()
                    addSubview(self.thumbView)
                }
            }

        }
        
        
       
        
        fetchDisposable.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: reference.userLocation, userContentType: reference.userContentType, reference: mediaResource).start())
        
        if let premiumResource = premiumResource {
            fetchPremiumDisposable.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: reference.userLocation, userContentType: reference.userContentType, reference: premiumResource).start())
        }
        
        if updated {
            stateDisposable.set((self.playerView.state |> deliverOnMainQueue).start(next: { [weak self] state in
                guard let `self` = self else { return }
                switch state {
                case .playing:
                    self.addSubview(self.playerView)
                    self.thumbView.removeFromSuperview()
                    self.removePlaceholder(animated: false)
                    self.firstFrameReadyValue.set(true)
                case .stoped:
                    if let parameters = params, parameters.hidePlayer == false {
                        break
                    } else {
                        self.playerView.removeFromSuperview()
                        self.addSubview(self.thumbView)
                    }
                case .finished:
                    if TelegramUtilsHooks.shared.isLite(.stickers), parent != nil {
                        DispatchQueue.main.async { [weak self] in
                            self?.previousAccept = false
                            self?.updatePlayerIfNeeded()
                        }
                    } else if let sticker = self.sticker, sticker.playPolicy == .once || sticker.playPolicy == .onceEnd {
                        self.playerView.releaseFinishedContext()
                    }
                    
                default:
                    break
                }
                
            }))
        }
        
    }
    
    private func removePlaceholder(animated: Bool) {
        if let placeholderView = self.placeholderView {
            if animated {
                placeholderView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak placeholderView] _ in
                    placeholderView?.removeFromSuperview()
                })
            } else {
                placeholderView.removeFromSuperview()
            }
            self.placeholderView = nil
        }
    }
    
    public override var contents: Any? {
        return self.thumbView.image
    }
    
    
    public override func layout() {
        super.layout()
        self.playerView.frame = bounds
        self.thumbView.frame = bounds
        self.placeholderView?.frame = bounds
    }
    
}
