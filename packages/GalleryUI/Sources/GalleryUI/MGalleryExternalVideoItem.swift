import Cocoa
import ExternalVideoUtils
import TelegramCore
import ObjcUtils
import Postbox
import SwiftSignalKit
import TGUIKit
import AVFoundation
import AVKit
import InAppVideoServices
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import ChatModeTypes
import ChatHistoryModel
import GeneralRows
import LocalAnimations
import TelegramMediaUtils
import TelegramMedia
import AvatarUI
import MessageUtils
import InstantPageUI
import SecureIdUtils
import ColorPalette
import InAppSettings
import FoundationUtils

public enum AVPlayerState : Equatable {
    case playing(duration: Float64)
    case paused(duration: Float64)
    case waiting
    
    @available(OSX 10.12, *)
    public init(_ player: AVPlayer) {
        let duration: Float64
        if let item = player.currentItem {
            duration = CMTimeGetSeconds(item.duration)
        } else {
            duration = 0
        }
        switch player.timeControlStatus {
        case .playing:
            self = .playing(duration: duration)
        case .paused:
            self = .paused(duration: duration)
        case .waitingToPlayAtSpecifiedRate:
            self = .waiting
        @unknown default:
            self = .waiting
        }
    }
}

private final class GAVPlayer : AVPlayer {
    private var playerStatusContext = 0
    private let _playerState: ValuePromise<AVPlayerState> = ValuePromise(.waiting, ignoreRepeated: true)
    public var playerState: Signal<AVPlayerState, NoError> {
        return _playerState.get() |> deliverOnMainQueue
    }
    
    public var bufferingValue: ValuePromise<Bool> = ValuePromise(true, ignoreRepeated: true)
    
    public override func pause() {
        super.pause()
    }
    public override init(url: URL) {
        super.init(url: url)
    }
    public override init(playerItem item: AVPlayerItem?) {
        super.init(playerItem: item)
        if #available(OSX 10.12, *) {
            addObserver(self, forKeyPath: "timeControlStatus", options: [.new, .initial], context: &playerStatusContext)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidEnd(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: item)
        
        item?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)
        item?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: [.new], context: nil)
        item?.addObserver(self, forKeyPath: "playbackBufferFull", options: [.new], context: nil)
    }
    
    public override init() {
        super.init()
    }
    
    @objc private func playerDidEnd(_ notification: Notification) {
        seek(to: CMTime(seconds: 0, preferredTimescale: 1000000000));
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?)
    {
        //  Check status
        if keyPath == "timeControlStatus" && context == &playerStatusContext && change != nil
        {
            if #available(OSX 10.12, *) {
                _playerState.set(AVPlayerState(self))
            }
        }
        
        if let item = object as? AVPlayerItem {
            bufferingValue.set(!item.isPlaybackLikelyToKeepUp)
        }
    }
    
    deinit {
        if #available(OSX 10.12, *) {
            removeObserver(self, forKeyPath: "timeControlStatus")
        }
        self.currentItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        self.currentItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        self.currentItem?.removeObserver(self, forKeyPath: "playbackBufferFull")

        
        NotificationCenter.default.removeObserver(self)
    }
}

public class VideoPlayerView : AVPlayerView {
    
    public override func enterFullScreenMode(_ screen: NSScreen, withOptions options: [NSView.FullScreenModeOptionKey : Any]? = nil) -> Bool {
        return super.enterFullScreenMode(screen, withOptions: options)
    }
    
    public var isPip: Bool = false
    
    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateLayout()
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateLayout()
    }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateLayout()
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayout()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayout()
    }
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateLayout()
    }
    
    
    public func rewindForward(_ seekDuration: Float64 = 15) {
        guard let player = player, let duration = player.currentItem?.duration else { return }
        let playerCurrentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = min(playerCurrentTime + seekDuration, CMTimeGetSeconds(duration))
        
        let time2: CMTime = CMTimeMake(value: Int64(newTime * 1000 as Float64), timescale: 1000)
        player.seek(to: time2, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
    }
    public func rewindBack(_ seekDuration: Float64 = 15) {
        guard let player = player else { return }
        
        let playerCurrentTime = CMTimeGetSeconds(player.currentTime())
        var newTime = playerCurrentTime - seekDuration
        
        if newTime < 0 {
            newTime = 0
        }
        let time2: CMTime = CMTimeMake(value: Int64(newTime * 1000 as Float64), timescale: 1000)
        player.seek(to: time2, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        
    }
    
    private func updateLayout() {
        let controls = ObjcUtils.findElements(byClass: "AVMovableView", in: self).first
        if let controls = controls {
            if let pip = controls.subviews.last as? ImageButton {
                pip.setFrameOrigin(controls.frame.width - pip.frame.width - 80, controls.frame.height - pip.frame.height - 16)
            }
            controls._change(opacity: _mouseInside() ? 1 : 0, animated: true)
            
        }
        
    }
    
    public override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        updateLayout()
    }
    
    public override func layout() {
        super.layout()
        updateLayout()
    }
}


public class MGalleryExternalVideoItem: MGalleryItem {
    public let content:TelegramMediaWebpageLoadedContent
    private let _media:TelegramMediaImage
    
    public var mediaImage: TelegramMediaImage {
        return _media
    }
    
    public private(set) var startTime: TimeInterval = 0
    private var playAfter:Bool = true
    private let _playerItem: Promise<GAVPlayer> = Promise()
    
    public var playerState: Signal<AVPlayerState, NoError> {
        return _playerItem.get() |> mapToSignal { $0.playerState }
    }
    public override init(_ context: any AccountContextProtocol, _ entry: GalleryEntry, _ pagerSize: NSSize) {
        
        
        
        let webpage = entry.webpage!
        
        var startTime:TimeInterval = 0
        if case let .Loaded(content) = webpage.content {
            self.content = content
            
            
            _ = ObjcUtils._youtubeVideoId(fromText: content.embedUrl, originalUrl: content.url, startTime: &startTime)
            
            self._media = content.image!
        } else {
            fatalError("content for external video not found")
        }
        super.init(context, entry, pagerSize)
        self.startTime = startTime
        
        _playerItem.set((path.get() |> distinctUntilChanged |> deliverOnMainQueue) |> map { path -> GAVPlayer in
            let url = URL(string: path) ?? URL(fileURLWithPath: path)
            return GAVPlayer(url: url)
            })
        
        disposable.set(combineLatest(_playerItem.get() |> deliverOnMainQueue, view.get() |> distinctUntilChanged |> deliverOnMainQueue |> map { $0 as! AVPlayerView }).start(next: { [weak self] player, view in
            if let strongSelf = self {
                view.player = player
                if strongSelf.playAfter {
                    strongSelf.playAfter = false
                    
                    player.play()
                    if strongSelf.startTime > 0 {
                        player.seek(to: CMTimeMake(value: Int64(strongSelf.startTime * 1000.0), timescale: 1000))
                    }
                }
                let controls = ObjcUtils.findElements(byClass: "AVMovableView", in: view).first
                if let controls = controls, let pip = strongSelf.pipButton {
                    controls.addSubview(pip)
                    view.needsLayout = true
                }
            }
        }))
    
    }
    
    private var _cachedView: VideoPlayerView?
    private var pipButton: ImageButton?
    
    public override func toggleFullScreen() {
        if let view = _cachedView {
            let controls = ObjcUtils.findElements(byClass: "AVMovableView", in: view).first
            if let controls = controls {
                if let view = controls.subviews.first?.subviews.first?.subviews.first?.subviews.last?.subviews.first?.subviews.last {
                    if let view = view as? NSButton {
                        view.performClick(self)
                    }
                }
            }
        }
    }
    
    public override func togglePlayerOrPause() {
        if let view = _cachedView, let player = view.player {
            switch player.rate {
            case 0:
                player.play()
            default:
                player.pause()
            }
        }
    }
    
    public override func rewindBack() {
        _cachedView?.rewindBack()
    }
    public override func rewindForward() {
        _cachedView?.rewindForward()
    }
    
    public override func singleView() -> NSView {
        let view: VideoPlayerView
        if let _cachedView = _cachedView {
            view = _cachedView
        } else {
            view = VideoPlayerView()
        }
        view.showsFullScreenToggleButton = true
        view.showsFrameSteppingButtons = true
        view.controlsStyle = .floating
        view.autoresizingMask = []
        view.autoresizesSubviews = false
        
        _cachedView = view
        return view
        
    }
    private var isPausedGlobalPlayer: Bool = false
    
    public override func appear(for view: NSView?) {
        super.appear(for: view)
        
        pausepip()
        
        isPausedGlobalPlayer = GalleryHooks.shared.pauseGlobalAudio(context)
        
        if let view = view as? AVPlayerView {
            if let player = view.player {
                player.play()
                playAfter = false
            } else {
                playAfter = true
            }
        } else {
            playAfter = true
        }
    }
    
    public override var maxMagnify: CGFloat {
        return min(pagerSize.width / sizeValue.width, pagerSize.height / sizeValue.height)
    }
    
    public override func disappear(for view: NSView?) {
        super.disappear(for: view)
        if isPausedGlobalPlayer {
            GalleryHooks.shared.resumeGlobalAudio(context)
        }
        if let view = view as? VideoPlayerView, !view.isPip {
            view.player?.pause()
        }
        playAfter = false
    }
    
    public override var status: Signal<MediaResourceStatus, NoError> {
        return _playerItem.get() |> mapToSignal { value in
            return value.bufferingValue.get() |> map { buffering in
                return buffering ? .Fetching(isActive: true, progress: 0.8) : .Local
            }
        }
    }
 
    public override var sizeValue: NSSize {
        return NSMakeSize(1280, 720).fitted(pagerSize)
    }
    
    private var hasRequested: Bool = false
    
    public override func releaseResources() {
        guard hasRequested else {
            return
        }
        hasRequested = false
        releaseDisplayedImage()
    }
    
    public override func request(immediately: Bool) {
        super.request(immediately: immediately)
        guard !hasRequested else {
            return
        }
        hasRequested = true
        let webpage = entry.webpage!

        
        let signal:Signal<ImageDataTransformation,NoError> = chatMessagePhoto(account: context.account, imageReference: ImageMediaReference.webPage(webPage: WebpageReference(webpage), media: _media), scale: System.backingScale)
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: sizeValue, boundingSize: sizeValue, intrinsicInsets: NSEdgeInsets())
        let result = signal |> deliverOn(graphicsThreadPool) |> mapToThrottled { data -> Signal<CGImage?, NoError> in
            return .single(data.execute(arguments, data.data)?.generateImage())
        }
        
        switch webpage.content {
        case let .Loaded(content):
            _ = sharedVideoLoader.fetch(for: content).start()
        default:
            break
        }
        
        self.path.set(sharedVideoLoader.status(for: content) |> `catch` {_ in return .complete()} |> mapToSignal { (status) -> Signal<String, NoError> in
            if let status = status, case let .loaded(video) = status {
                return .single(video.stream)
            }
            return .complete()
        } |> deliverOnMainQueue)
        
        self.image.set(result |> map { GPreviewValueClass(.image($0 != nil ? NSImage(cgImage: $0!, size: $0!.backingSize) : nil, nil)) } |> deliverOnMainQueue)
        
        fetch()
    }
    
    
    
    
    public override func fetch() -> Void {
        fetching.set(sharedVideoLoader.fetch(for: content).start())
    }
    
}
