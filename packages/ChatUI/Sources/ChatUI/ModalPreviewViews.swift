import Cocoa
import TGUIKit
import TelegramCore
import TelegramMedia
import Postbox
import SwiftSignalKit
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

public class StickerPreviewModalView : View, ModalPreviewControllerView {
    fileprivate let imageView:TransformImageView = TransformImageView()
    fileprivate let textView:TextView = TextView()
    private let fetchDisposable = MetaDisposable()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        textView.backgroundColor = .clear
        imageView.setFrameSize(100,100)
        self.background = .clear
    }
    
    deinit {
        fetchDisposable.dispose()
    }
    
    public override func layout() {
        super.layout()
        imageView.center()
    }
    
    public func update(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) -> Void {
        if let reference = reference.fileReference {
            
            let size = reference.media.dimensions?.size.aspectFitted(NSMakeSize(min(300, frame.size.width), min(300, frame.size.height))) ?? frame.size
            imageView.set(arguments: TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets()))
            imageView.frame = NSMakeRect(0, frame.height - size.height, size.width, size.height)
            if animated {
                imageView.layer?.animateScaleSpring(from: 0.5, to: 1.0, duration: 0.2)
            }
            
            imageView.setSignal(chatMessageSticker(postbox: context.account.postbox, file: reference, small: false, scale: backingScaleFactor, fetched: true), clearInstantly: true, animate:true)
            
            let layout = TextViewLayout(.initialize(string: reference.media.stickerText?.fixed, color: nil, font: .normal(30.0)))
            layout.measure(width: .greatestFiniteMagnitude)
            textView.update(layout)
            textView.centerX(y: 0)
            if animated {
                textView.layer?.animateScaleSpring(from: 0.5, to: 1.0, duration: 0.2)
            }
            
            needsLayout = true
        }
    }
    
    public func getContentView() -> NSView {
        return imageView
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



public class GifPreviewModalView : View, ModalPreviewControllerView {
    fileprivate var player:GIFContainerView = GIFContainerView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(player)
        player.setFrameSize(100,100)
        self.background = .clear
    }
    
    public override func layout() {
        super.layout()
        player.center()
        
    }
    
    public func getContentView() -> NSView {
        return player
    }
    
    public func update(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) -> Void {
        if let reference = reference.fileReference {
            if animated {
                let current = self.player
                current.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak current] completed in
                    if completed {
                        current?.removeFromSuperview()
                    }
                })
            } else {
                self.player.removeFromSuperview()
            }
           
            self.player = GIFContainerView()
            self.player.layer?.borderWidth = 0
            self.player.layer?.cornerRadius = .cornerRadius
            addSubview(self.player)
            let size = reference.media.dimensions?.size.aspectFitted(NSMakeSize(frame.size.width, frame.size.height - 40)) ?? frame.size
            

            player.update(with: reference, size: size, viewSize: size, context: context, table: nil, isPreview: true)
            player.frame = NSMakeRect(0, frame.height - size.height, size.width, size.height)
            if animated {
                player.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            needsLayout = true
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class ImagePreviewModalView : View, ModalPreviewControllerView {
    fileprivate var imageView:TransformImageView = TransformImageView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        self.background = .clear
    }
    
    public override func layout() {
        super.layout()
        imageView.center()
    }
    
    public func getContentView() -> NSView {
        return imageView
    }
    
    public func update(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) -> Void {
        if let reference = reference.imageReference {
            let current = self.imageView
            if animated {
                current.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak current] completed in
                    if completed {
                        current?.removeFromSuperview()
                    }
                })
            } else {
                current.removeFromSuperview()
            }
            
            self.imageView = TransformImageView()
            self.imageView.layer?.borderWidth = 0
            addSubview(self.imageView)
            
            let size = frame.size
            
            let dimensions = largestImageRepresentation(reference.media.representations)?.dimensions.size ?? size

            let arguments = TransformImageArguments(corners: ImageCorners(radius: .cornerRadius), imageSize: dimensions.fitted(size), boundingSize: dimensions.fitted(size), intrinsicInsets: NSEdgeInsets(), resizeMode: .none)
            
            self.imageView.setSignal(signal: cachedMedia(media: reference.media, arguments: arguments, scale: backingScaleFactor, positionFlags: nil), clearInstantly: false)
            
            let updateImageSignal = chatMessagePhoto(account: context.account, imageReference: reference, scale: backingScaleFactor, synchronousLoad: true)
            self.imageView.setSignal(updateImageSignal, animate: false)
            self.imageView.set(arguments: arguments)
            
            imageView.setFrameSize(arguments.imageSize)
            if animated {
                imageView.layer?.animateScaleSpring(from: 0.5, to: 1.0, duration: 0.2)
            }
            needsLayout = true
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


public class VideoPreviewModalView : View, ModalPreviewControllerView {
    fileprivate var playerView:ChatVideoAutoplayView?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.background = .clear
    }
    
    public override func layout() {
        super.layout()
        playerView?.view.center()
    }
    
    public func getContentView() -> NSView {
        return playerView?.view ?? self
    }
    
    public func update(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) -> Void {
        if let reference = reference.fileReference {
            let currentView = self.playerView?.view
            if animated {
                currentView?.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak currentView] completed in
                    if completed {
                        currentView?.removeFromSuperview()
                    }
                })
            } else {
                currentView?.removeFromSuperview()
            }
                        
            self.playerView = ChatVideoAutoplayView(mediaPlayer: MediaPlayer(postbox: context.account.postbox, userLocation: reference.userLocation, userContentType: reference.userContentType, reference: reference.resourceReference(reference.media.resource), streamable: reference.media.isStreamable, video: true, preferSoftwareDecoding: false, enableSound: true, volume: 1.0, fetchAutomatically: true), view: MediaPlayerView(backgroundThread: true))

            guard let playerView = self.playerView else {
                return
            }
            
            addSubview(playerView.view)
            
            let size = frame.size
            
            let dimensions = reference.media.dimensions?.size ?? size
            
            playerView.view.setFrameSize(dimensions.fitted(size))
            playerView.mediaPlayer.attachPlayerView(playerView.view)

            playerView.mediaPlayer.play()
            
            needsLayout = true
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



public class AnimatedStickerPreviewModalView : View, ModalPreviewControllerView {
    private let loadResourceDisposable = MetaDisposable()
    fileprivate let textView:TextView = TextView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.background = .clear
        
        addSubview(textView)
        textView.backgroundColor = .clear
    }
    private var player: LottiePlayerView?
    private var effectView: LottiePlayerView?
    
    private let dataDisposable = MetaDisposable()
    
    public override func layout() {
        super.layout()
        //player.center()
    }
    
    public func getContentView() -> NSView {
        return player ?? self
    }
    
    public override func viewDidMoveToWindow() {
        
    }
    
    deinit {
        self.loadResourceDisposable.dispose()
        self.dataDisposable.dispose()
    }
    
    public func update(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) -> Void {
        
        if let reference = reference.fileReference {
            self.player?.removeFromSuperview()
            self.player = nil
            
            let dimensions = reference.media.dimensions?.size
            
            var size = NSMakeSize(frame.width - 80, frame.height - 80)
            if reference.media.premiumEffect != nil {
                size = NSMakeSize(200, 200)
            } else if reference.media.isCustomEmoji {
                size = NSMakeSize(200, 200)
            }
            if let dimensions = dimensions {
                size = dimensions.aspectFitted(size)
            }

            self.player = LottiePlayerView(frame: NSMakeRect(0, 0, size.width, size.height))
            addSubview(self.player!)
            
            guard let player = self.player else {
                return
            }

            
            player.center()
            
            let mediaId = reference.media.id
            
            let data: Signal<MediaResourceData, NoError>
            if let resource = reference.media.resource as? LocalBundleResource {
                data = Signal { subscriber in
                    if let path = Bundle.main.path(forResource: resource.name, ofType: resource.ext), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedRead]) {
                        subscriber.putNext(MediaResourceData(path: path, offset: 0, size: Int64(data.count), complete: true))
                        subscriber.putCompletion()
                    }
                    return EmptyDisposable
                }
            } else {
                data = context.account.postbox.mediaBox.resourceData(reference.media.resource, attemptSynchronously: true)
            }
            
            self.loadResourceDisposable.set((data |> map { resourceData -> Data? in
                
                if resourceData.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: [.mappedIfSafe]) {
                    if reference.media.isWebm {
                        return resourceData.path.data(using: .utf8)!
                    }
                    return data
                }
                return nil
            } |> deliverOnMainQueue).start(next: { [weak player] data in
                if let data = data {
                    
                    let type: LottieAnimationType
                    if reference.media.isWebm {
                        type = .webm
                    } else if reference.media.mimeType == "image/webp" {
                        type = .webp
                    } else {
                        type = .lottie
                    }
                    
                    var colors:[LottieColor] = []
                    if reference.media.isCustomTemplateEmoji {
                        colors.append(.init(keyPath: "", color: theme.colors.text))
                    }
                    
                    player?.set(LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .media(mediaId), size: size), type: type, cachePurpose: .none, colors: colors))
                } else {
                    player?.set(nil)
                }
            }))

            if animated {
                player.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            
            let layout = TextViewLayout(.initialize(string: reference.media.stickerText?.fixed ?? reference.media.customEmojiText?.fixed, color: nil, font: .normal(30.0)))
            layout.measure(width: .greatestFiniteMagnitude)
            textView.update(layout)
            textView.centerX(y: max(0, player.frame.minY - textView.frame.height - 20))
            if animated {
                textView.layer?.animateScaleSpring(from: 0.5, to: 1.0, duration: 0.2)
            }
            
            if let effect = reference.media.premiumEffect {
                var animationSize = NSMakeSize(size.width * 1.5, size.height * 1.5)
                if let dimensions = reference.media.dimensions?.size {
                    animationSize = dimensions.aspectFitted(animationSize)
                }
                let signal: Signal<LottieAnimation?, NoError> = context.account.postbox.mediaBox.resourceData(effect.resource) |> filter { $0.complete } |> take(1) |> map { data in
                    if data.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                        return LottieAnimation(compressed: data, key: .init(key: .bundle("_premium_\(reference.media.fileId)"), size: animationSize, backingScale: Int(System.backingScale)), cachePurpose: .none, playPolicy: .loop)
                    } else {
                        return nil
                    }
                } |> deliverOnMainQueue
                
                let current: LottiePlayerView
                if let view = effectView {
                    current = view
                } else {
                    current = LottiePlayerView(frame: animationSize.bounds)
                    self.effectView = current
                }
                
                addSubview(current, positioned: .above, relativeTo: self.player)
                current.centerY(x: player.frame.maxX - current.frame.width + 19, addition: -1.5)
                
                dataDisposable.set(signal.start(next: { [weak current] animation in
                    current?.set(animation)
                }))
            } else if let view = effectView {
                performSubviewRemoval(view, animated: true)
                self.effectView = nil
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension StickerPreviewModalView {
    public func updateModalPreview(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) {
        self.update(with: reference, context: context, animated: animated)
    }
}

extension GifPreviewModalView {
    public func updateModalPreview(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) {
        self.update(with: reference, context: context, animated: animated)
    }
}

extension ImagePreviewModalView {
    public func updateModalPreview(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) {
        self.update(with: reference, context: context, animated: animated)
    }
}

extension VideoPreviewModalView {
    public func updateModalPreview(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) {
        self.update(with: reference, context: context, animated: animated)
    }
}

extension AnimatedStickerPreviewModalView {
    public func updateModalPreview(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) {
        self.update(with: reference, context: context, animated: animated)
    }
}
