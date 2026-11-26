import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import AVKit
import SwiftSignalKit
import Localization
import TelegramContext
import TelegramTheme
import TelegramIconsTheme
import TelegramMediaUtils
import ColorPalette


private final class VideoAvatarKeyFramePreviewView: Control {
    private let imageView: ImageView = ImageView()
    private let flash: View = View()
    fileprivate var keyFrame: CGFloat?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(flash)
        imageView.isAccessibilityDecorative = true
        flash.backgroundColor = .white
        flash.frame = bounds
        imageView.frame = bounds
        imageView.animates = true
        layout()
    }
    
    func update(with image: CGImage?, value: CGFloat?, animated: Bool, completion: @escaping(Bool)->Void) {
        imageView.image = image
        self.keyFrame = value
        if animated {
            flash.layer?.animateAlpha(from: 1, to: 0, duration: 0.8, timingFunction: .easeIn, removeOnCompletion: false, completion: { [weak self] completed in
                self?.flash.removeFromSuperview()
                completion(completed)
            })
        } else {
            flash.removeFromSuperview()
            completion(true)
        }
    }
    
    
    
    override func layout() {
        super.layout()
        imageView.frame = bounds
        layer?.cornerRadius = frame.width / 2
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class VideoAvatarModalView : View {
    private let avPlayer: AVPlayerLayer
    private var videoSize: NSSize = .zero
    private let playerContainer: View = View()
    private var keyFramePreview: VideoAvatarKeyFramePreviewView?
    private var keyFrameDotView: View?
    private var keyFrameGeneration = UUID()
    private var keyFrameAnimating = false
    private let controls: View = View()
    
    fileprivate let ok: TextButton = TextButton()
    fileprivate let cancel: TextButton = TextButton()

    fileprivate let scrubberView: VideoEditorScrubblerControl = VideoEditorScrubblerControl(frame: .zero)
    fileprivate let selectionRectView: SelectionRectView
    

    private let descView: TextView = TextView()
    
    required init(frame frameRect: NSRect) {
        
        
        selectionRectView = SelectionRectView(frame: frameRect.size.bounds)
        avPlayer = AVPlayerLayer()
        avPlayer.frame = frameRect.size.bounds
        super.init(frame: frameRect)
        playerContainer.layer?.addSublayer(avPlayer)
        
        avPlayer.videoGravity = .resizeAspectFill
        playerContainer.addSubview(selectionRectView)
        controls.addSubview(scrubberView)
        selectionRectView.isCircleCap = true
        selectionRectView.dimensions = .square
        
        self.videoSize = frameRect.size
        

        addSubview(playerContainer)
        addSubview(controls)
        
        self.addSubview(ok)
        self.addSubview(cancel)
        
        addSubview(descView)
        
        descView.userInteractionEnabled = false
        descView.isSelectable = false
        descView.disableBackgroundDrawing = true
        
        
        cancel.set(background: .grayText, for: .Normal)
        ok.set(background: .accent, for: .Normal)
        
        cancel.set(background: NSColor.grayText.withAlphaComponent(0.8), for: .Highlight)
        ok.set(background: NSColor.accent.highlighted, for: .Highlight)

        
        cancel.set(color: .white, for: .Normal)
        cancel.set(text: strings().videoAvatarButtonCancel, for: .Normal)

        
        ok.set(color: .white, for: .Normal)
        ok.set(text: strings().videoAvatarButtonSet, for: .Normal)

        _ = cancel.sizeToFit(.zero, NSMakeSize(80, 20), thatFit: true)
        _ = ok.sizeToFit(.zero, NSMakeSize(80, 20), thatFit: true)

        cancel.layer?.cornerRadius = .cornerRadius
        ok.layer?.cornerRadius = .cornerRadius

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 5
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSMakeSize(0, 2)
        self.cancel.shadow = shadow
        self.ok.shadow = shadow

        setFrameSize(frame.size)
        layout()
        
        
    }
    
    func updateKeyFrameImage(_ image: CGImage?) {
        keyFramePreview?.update(with: image, value: keyFramePreview?.keyFrame, animated: false, completion: { _ in })
    }
    
    func setKeyFrame(value: CGFloat?, highRes: CGImage? = nil, lowRes: CGImage? = nil, animated: Bool, completion: @escaping(Bool)->Void = { _ in}, moveToCurrentKeyFrame: @escaping(CGFloat)->Void = { _ in }) -> Void {
        self.keyFrameGeneration = UUID()
        let generation = self.keyFrameGeneration
        self.keyFrameAnimating = false
        self.keyFramePreview?.removeFromSuperview()
        self.keyFrameDotView?.removeFromSuperview()
        self.keyFramePreview = nil
        self.keyFrameDotView = nil
        guard let value else { return }

        let origin = self.convert(selectionRectView.selectedRect.origin, from: selectionRectView)
        let size = selectionRectView.selectedRect.size
        let keyFramePreview = VideoAvatarKeyFramePreviewView(frame: CGRect(origin: origin, size: size))
        self.keyFramePreview = keyFramePreview
        self.keyFrameAnimating = true
        self.addSubview(keyFramePreview)
        keyFramePreview.set(handler: { [weak self] _ in
            guard let self, self.keyFrameGeneration == generation else { return }
            moveToCurrentKeyFrame(value)
        }, for: .Click)
        keyFramePreview.update(with: highRes, value: value, animated: animated, completion: { [weak self, weak keyFramePreview] completed in
            guard let self, self.keyFrameGeneration == generation, let keyFramePreview, self.keyFramePreview === keyFramePreview else { return }
            guard completed else {
                self.keyFrameAnimating = false
                self.keyFramePreview = nil
                keyFramePreview.removeFromSuperview()
                completion(false)
                return
            }
            let keyFrameDotView = View()
            self.keyFrameDotView = keyFrameDotView
            self.addSubview(keyFrameDotView)
            keyFrameDotView.backgroundColor = .white
            keyFrameDotView.layer?.cornerRadius = 3

            let point = NSMakePoint(self.controls.frame.minX + self.scrubberView.frame.minX + self.scrubberView.timelinePosition(for: value) - 15, self.controls.frame.maxY - self.scrubberView.frame.height - 30 - 14)
            keyFrameDotView.frame = NSMakeRect(self.controls.frame.minX + self.scrubberView.frame.minX + self.scrubberView.timelinePosition(for: value) - 3, self.controls.frame.maxY - self.scrubberView.frame.height - 10, 6, 6)
            let finish: (Bool) -> Void = { [weak self, weak keyFramePreview, weak keyFrameDotView] complete in
                guard let self, self.keyFrameGeneration == generation, self.keyFrameAnimating, let keyFramePreview, self.keyFramePreview === keyFramePreview else { return }
                self.keyFrameAnimating = false
                keyFramePreview.update(with: lowRes, value: value, animated: false, completion: { _ in })
                keyFramePreview.frame = CGRect(origin: point, size: NSMakeSize(30, 30))
                keyFramePreview.layer?.removeAllAnimations()
                if !complete {
                    self.keyFramePreview = nil
                    self.keyFrameDotView = nil
                    keyFrameDotView?.removeFromSuperview()
                    keyFramePreview.removeFromSuperview()
                }
                self.needsLayout = true
                completion(complete)
            }
            if animated {
                keyFramePreview.layer?.animateScale(from: 1, to: 30 / keyFramePreview.frame.width, duration: 0.23, removeOnCompletion: false)
                keyFramePreview.layer?.animatePosition(from: keyFramePreview.frame.origin, to: point, duration: 0.3, removeOnCompletion: false, completion: finish)
                keyFrameDotView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            } else {
                finish(true)
            }
        })
    }

    var playerSize: NSSize {
        return playerContainer.frame.size
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
    }
    
    private var localize: String?
    
    func update(_ player: AVPlayer, localize: String, size: NSSize) {
        self.avPlayer.player = player
        self.videoSize = size
        self.localize = localize
        setFrameSize(frame.size)
        layout()
        
        let size = NSMakeSize(200, 200).aspectFitted(playerContainer.frame.size)
        let rect = playerContainer.focus(size)
        selectionRectView.minimumSize = size.aspectFitted(NSMakeSize(150, 150))
        selectionRectView.applyRect(rect, force: true, dimensions: .square)
    }

    func play() {
        self.avPlayer.player?.play()

    }
    func stop() {
        self.avPlayer.player?.pause()
        self.avPlayer.player = nil
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = self.frame.size
        super.setFrameSize(newSize)
        
        let videoContainerSize = videoSize.aspectFitted(NSMakeSize(newSize.width, newSize.height - 200))
        let oldVideoContainerSize = playerContainer.frame.size
        playerContainer.setFrameSize(videoContainerSize)

        
        if oldSize != newSize, oldSize != NSZeroSize, inLiveResize {
            let multiplier = NSMakeSize(videoContainerSize.width / oldVideoContainerSize.width, videoContainerSize.height / oldVideoContainerSize.height)
            selectionRectView.applyRect(selectionRectView.selectedRect.apply(multiplier: multiplier))
        }
        
        avPlayer.frame = videoContainerSize.bounds
        
        
        selectionRectView.frame = playerContainer.bounds
        controls.setFrameSize(NSMakeSize(370, 44))
        scrubberView.setFrameSize(controls.frame.size)

        
        
        if let localize = localize {
            let descLayout = TextViewLayout.init(.initialize(string: localize, color: .white, font: .normal(.text)), maximumNumberOfLines: 1)
            descLayout.measure(width: frame.width)
            descView.update(descLayout)
        }
    }
    
    override func layout() {
        super.layout()
        
        playerContainer.centerX(y: floorToScreenPixels(backingScaleFactor, (frame.height - 184) - playerContainer.frame.height) / 2)
        controls.centerX(y: frame.height - controls.frame.height - 100)
        scrubberView.centerX(y: controls.frame.height - scrubberView.frame.height)
        
        ok.centerX(y: frame.height - ok.frame.height - 30, addition: 7 + ok.frame.width / 2)
        cancel.centerX(y: frame.height - cancel.frame.height - 30, addition: -(7 + cancel.frame.width / 2))

        descView.centerX(y: controls.frame.maxY + 15)
        
        
        if !self.keyFrameAnimating, let keyFramePreview = keyFramePreview, let keyFrameDotView = keyFrameDotView, let value = keyFramePreview.keyFrame {
            let point = NSMakePoint(self.controls.frame.minX + self.scrubberView.frame.minX + self.scrubberView.timelinePosition(for: value) - 15, self.controls.frame.maxY - self.scrubberView.frame.height - 30 - 14)
            
            keyFrameDotView.frame = NSMakeRect(self.controls.frame.minX + self.scrubberView.frame.minX + self.scrubberView.timelinePosition(for: value) - 3, self.controls.frame.maxY - self.scrubberView.frame.height - 10, 6, 6)
            keyFramePreview.frame = CGRect(origin: point, size: NSMakeSize(30, 30))

        }
        
    }
}


public enum VideoAvatarGeneratorState : Equatable {
    case start(thumb: String)
    case progress(Float)
    case complete(thumb: String, video: String, keyFrame: Double?)
    case error
}


public class VideoAvatarModalController: ModalViewController {
    private let context: any AccountContextProtocol
    fileprivate let videoSize: NSSize
    fileprivate let player: AVPlayer
    fileprivate let item: AVPlayerItem
    fileprivate let asset: AVComposition
    fileprivate let track: AVAssetTrack
    fileprivate var appliedKeyFrame: CGFloat? = nil
    
    private let updateThumbsDisposable = MetaDisposable()
    private let rectDisposable = MetaDisposable()
    private let valuesDisposable = MetaDisposable()
    private let keyFrameGeneratorDisposable = MetaDisposable()
    private var keyFrameGeneration = UUID()
    private var keyFrameInteractionGeneration = UUID()
    private var keyFramePreviewResumePending = false
    private var thumbnailGeneration = UUID()
    private var playToEndObserver: NSObjectProtocol?
    
    fileprivate let scrubberValues:Atomic<VideoScrubberValues> = Atomic(value: VideoScrubberValues(movePos: 0, keyFrame: nil, leftTrim: 0, rightTrim: 1.0, minDist: 0, maxDist: 1, paused: true, suspended: false))
    fileprivate let _scrubberValuesSignal: ValuePromise<VideoScrubberValues> = ValuePromise(ignoreRepeated: true)
    var scrubberValuesSignal: Signal<VideoScrubberValues, NoError> {
        return _scrubberValuesSignal.get() |> deliverOnMainQueue
    }
    
    fileprivate func updateValues(_ f: (VideoScrubberValues)->VideoScrubberValues) {
        _scrubberValuesSignal.set(scrubberValues.modify(f))
    }
    private var firstTime: Bool = true
    private var timeObserverToken: Any?
    private var playbackGeneration = UUID()
    private var playbackActive = true
    
    public var completeState: Signal<VideoAvatarGeneratorState, NoError> {
        return state.get()
    }
    
    private var state: Promise<VideoAvatarGeneratorState> = Promise()
    private let localize: String
    private let quality: String
    private let holder: AVAsset
    private let confirm: ((Signal<URL, NoError>, @escaping()->Void)->Void)?
    public init(context: any AccountContextProtocol, asset: AVComposition, track: AVAssetTrack, localize: String, quality: String, holder: AVAsset, confirm: ((Signal<URL, NoError>, @escaping()->Void)->Void)? = nil) {
        self.context = context
        self.asset = asset
        self.confirm = confirm
        self.track = track
        self.holder = holder
        self.quality = quality
        self.videoSize = EditedAvatarVideoGeometry(naturalSize: track.naturalSize, transform: track.preferredTransform)?.size ?? .zero
        
        self.item = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: item)
        
        self.item.videoComposition = editedAvatarVideoComposition(track: track, duration: asset.duration)

        self.localize = localize
        super.init(frame: CGRect(origin: .zero, size: context.window.contentView!.frame.size - NSMakeSize(20, 20)))
        self.bar = .init(height: 0)
    }
    
    public override func measure(size: NSSize) {
        if let contentSize = self.modal?.window.contentView?.frame.size {
            self.modal?.resize(with: contentSize - NSMakeSize(20, 20), animated: false)
        }
    }
    
    public func updateSize(_ animated: Bool) {
        if let contentSize = self.modal?.window.contentView?.frame.size {
            self.modal?.resize(with: contentSize - NSMakeSize(20, 20), animated: animated)
        }
    }
    
    
    public override var dynamicSize: Bool {
        return true
    }
    
    public override var background: NSColor {
        return .clear
    }
    
    public override var containerBackground: NSColor {
        return .clear
    }
    public override var isVisualEffectBackground: Bool {
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return VideoAvatarModalView.self
    }
    
    private var genericView: VideoAvatarModalView {
        return self.view as! VideoAvatarModalView
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !self.playbackActive {
            self.playbackActive = true
            self.updateUserInterface(self.firstTime)
            let values = self.scrubberValues.with { $0 }
            if values.paused {
                self.applyValuesToPlayer(values)
            } else {
                self.play()
            }
        }
    }
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.playbackActive = false
        self.invalidateKeyFramePreview()
        self.thumbnailGeneration = UUID()
        self.updateThumbsDisposable.set(nil)
        self.generatedRect = nil
        self.playbackGeneration = UUID()
        player.pause()
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
            self.playToEndObserver = nil
        }
        
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }
    
    public override func returnKeyAction() -> KeyHandlerResult {
        
        guard let composition = self.currentVideoComposition() else { return .invoked }
        let dataSignal = generateVideo(self.asset, composition: composition, quality: self.quality, values: self.scrubberValues.with { $0 })
        
        let promise: Promise<VideoAvatarGeneratorState> = Promise()
        promise.set(dataSignal)
        
        let invoke = { [weak self] in
            guard let `self` = self else {
                return
            }
            self.state.set(promise.get())
            self.close()
        }
        
        if let confirm = confirm {
            confirm(promise.get() |> mapToSignal { value in
                switch value {
                case let .start(thumb):
                    return .single(URL(fileURLWithPath: thumb))
                case let .complete(thumb, _, _):
                    return .single(URL(fileURLWithPath: thumb))
                default:
                    return .never()
                }
            }, invoke)
        } else {
            invoke()
        }
        
        return .invoked
    }
    
    
    private func currentVideoComposition() -> AVVideoComposition? {
        editedAvatarVideoComposition(track: self.track, duration: self.asset.duration, selection: self.genericView.selectionRectView.selectedRect, viewSize: self.genericView.playerSize)
    }

    deinit {
        rectDisposable.dispose()
        updateThumbsDisposable.dispose()
        valuesDisposable.dispose()
        keyFrameGeneratorDisposable.dispose()
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
        }
        
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }
    
    private var generatedRect: NSRect? = nil
    
    private func updateUserInterface(_ firstTime: Bool) {
        guard self.playbackActive else { return }
        let size = NSMakeSize(genericView.scrubberView.frame.height, genericView.scrubberView.frame.height)
        guard let composition = self.currentVideoComposition(), size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, let count = Int(exactly: ceil(genericView.scrubberView.frame.width / size.width)), count > 0 else { return }
        let selectedRect = self.genericView.selectionRectView.selectedRect
        guard self.generatedRect != selectedRect else { return }
        self.generatedRect = selectedRect
        self.thumbnailGeneration = UUID()
        let generation = self.thumbnailGeneration
        let request = MetaDisposable()
        self.updateThumbsDisposable.set(request)
        let signal = generateVideoScrubberThumbs(for: asset, composition: composition, size: size, count: count, gradually: true, blur: true)
            |> delay(0.2, queue: .concurrentDefaultQueue())
            |> deliverOnMainQueue
        request.set(signal.start(next: { [weak self] images in
            guard let self, self.playbackActive, self.thumbnailGeneration == generation else { return }
            self.genericView.scrubberView.render(images.0, size: size)
            if self.firstTime {
                self.firstTime = !images.1
            }
        }))
        if let keyFrame = self.scrubberValues.with({ $0.keyFrame }) {
            self.runKeyFrameUpdater(keyFrame, animated: false)
        }
    }
    private func applyValuesToPlayer(_ values: VideoScrubberValues) {
        guard self.playbackActive, self.scrubberValues.with({ $0 }) == values, let range = EditedAvatarVideoRange(duration: self.asset.duration.seconds, leftTrim: Double(values.leftTrim), rightTrim: Double(values.rightTrim), keyFrame: nil) else { return }
        self.item.forwardPlaybackEndTime = CMTimeRangeGetEnd(range.timeRange)
        if values.movePos >= values.rightTrim, !values.paused {
            play()
        }
        if values.paused {
            player.rate = 0
            seekToNormal(values)
            player.pause()
        } else if player.rate == 0, !values.paused {
            player.rate = 1
            play()
        }
        if let keyFrame = values.keyFrame, appliedKeyFrame != keyFrame {
            self.runKeyFrameUpdater(keyFrame)
            seekToNormal(values)
        } else if appliedKeyFrame != nil && values.keyFrame == nil {
            self.invalidateKeyFramePreview()
        }
    }
    @discardableResult private func seekToNormal(_ values: VideoScrubberValues) -> CGFloat? {
        let duration = self.asset.duration.seconds
        guard let range = EditedAvatarVideoRange(duration: duration, leftTrim: Double(values.leftTrim), rightTrim: Double(values.rightTrim), keyFrame: values.suspended ? Double(values.movePos) : nil) else { return nil }
        self.player.seek(to: range.thumbnailTime, toleranceBefore: .zero, toleranceAfter: .zero)
        return values.suspended ? CGFloat(range.thumbnailTime.seconds / duration) : nil
    }

    private func play() {
        guard self.playbackActive else { return }
        player.pause()
        self.playbackGeneration = UUID()
        let generation = self.playbackGeneration
        let duration = CMTimeGetSeconds(asset.duration)
        
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        
        let values = self.scrubberValues.with { $0 }
        guard let range = EditedAvatarVideoRange(duration: duration, leftTrim: Double(values.leftTrim), rightTrim: Double(values.rightTrim), keyFrame: values.suspended ? Double(values.movePos) : nil) else { return }
        self.item.forwardPlaybackEndTime = CMTimeRangeGetEnd(range.timeRange)

        _ = self.scrubberValues.modify { values in
            let values = values.withUpdatedPaused(false)
            if let result = self.seekToNormal(values) {
                return values.withUpdatedMove(result)
            } else {
                return values.withUpdatedMove(values.leftTrim)
            }
        }
        
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.016 * 2, preferredTimescale: timeScale)

        
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self]  time in
            guard let self, self.playbackActive, self.playbackGeneration == generation, time.isNumeric, time.seconds.isFinite else { return }
            self.updateValues { current in
                if !current.suspended {
                    return current.withUpdatedMove(CGFloat(CMTimeGetSeconds(time) / duration))
                } else {
                    return current
                }
            }
        }
        
        
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
        }
        self.playToEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: self.item, queue: .main) { [weak self] _ in
            guard let self, self.playbackActive, self.playbackGeneration == generation else { return }
            self.play()
        }

        self.player.play()
    }
    
    private func invalidateKeyFramePreview() {
        self.keyFrameGeneration = UUID()
        self.keyFramePreviewResumePending = false
        self.keyFrameGeneratorDisposable.set(nil)
        self.appliedKeyFrame = nil
        self.genericView.setKeyFrame(value: nil, animated: false)
    }

    private func runKeyFrameUpdater(_ keyFrame: CGFloat, animated: Bool = true) {
        guard self.playbackActive, self.scrubberValues.with({ $0.keyFrame }) == keyFrame else { return }
        let resumePlayback = animated ? self.scrubberValues.with({ $0.paused && $0.suspended }) : self.keyFramePreviewResumePending
        self.invalidateKeyFramePreview()
        self.keyFramePreviewResumePending = resumePlayback
        self.appliedKeyFrame = keyFrame
        let generation = self.keyFrameGeneration
        let interaction = self.keyFrameInteractionGeneration
        var finished = false
        let finish: (Bool) -> Void = { [weak self] completed in
            guard let self, !finished, self.playbackActive, self.keyFrameGeneration == generation, self.keyFrameInteractionGeneration == interaction, self.scrubberValues.with({ $0.keyFrame }) == keyFrame, resumePlayback else { return }
            finished = true
            self.keyFramePreviewResumePending = false
            _ = self.scrubberValues.modify { values in
                let updated = values.withUpdatedPaused(false).withUpdatedSuspended(true)
                return completed ? updated.withUpdatedMove(keyFrame) : updated
            }
            self.play()
            self.updateValues { $0.withUpdatedSuspended(false) }
        }
        guard let composition = self.currentVideoComposition(), let range = EditedAvatarVideoRange(duration: self.asset.duration.seconds, leftTrim: Double(self.scrubberValues.with { $0.leftTrim }), rightTrim: Double(self.scrubberValues.with { $0.rightTrim }), keyFrame: Double(keyFrame)) else {
            finish(false)
            return
        }
        let size = self.genericView.selectionRectView.selectedRect.size
        let signal = generateVideoAvatarPreview(for: self.asset, composition: composition, highSize: size, lowSize: NSMakeSize(30, 30), at: range.thumbnailTime.seconds)
            |> take(1)
            |> deliverOnMainQueue
        let request = MetaDisposable()
        self.keyFrameGeneratorDisposable.set(request)
        var received = false
        request.set(signal.start(next: { [weak self] highRes, lowRes in
            received = true
            guard let self, self.playbackActive, self.keyFrameGeneration == generation, self.scrubberValues.with({ $0.keyFrame }) == keyFrame else { return }
            guard let highRes, let lowRes else {
                finish(false)
                return
            }
            self.genericView.setKeyFrame(value: keyFrame, highRes: highRes, lowRes: lowRes, animated: animated, completion: finish, moveToCurrentKeyFrame: { [weak self] value in
                guard let self, self.playbackActive, self.keyFrameGeneration == generation, self.scrubberValues.with({ $0.keyFrame }) == value else { return }
                self.keyFrameInteractionGeneration = UUID()
                self.keyFramePreviewResumePending = false
                let values = self.scrubberValues.with { $0 }.withUpdatedMove(value).withUpdatedSuspended(true)
                let position = self.seekToNormal(values) ?? value
                self.updateValues { $0.withUpdatedMove(position).withUpdatedSuspended(values.paused) }
            })
        }, completed: {
            if !received {
                finish(false)
            }
        }))
    }

    public override var closable: Bool {
        return false
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        
        genericView.update(self.player, localize: self.localize, size: self.videoSize)
        
        genericView.cancel.set(handler: { [weak self] _ in
            self?.close()
        }, for: .Click)
        
        genericView.ok.set(handler: { [weak self] _ in
            _ = self?.returnKeyAction()
        }, for: .Click)
        
        guard let initialValues = initialAvatarVideoScrubberValues(duration: self.asset.duration.seconds) else {
            self.state.set(.single(.error))
            self.close()
            return
        }
        self.updateValues { _ in initialValues }

        genericView.scrubberView.updateValues = { [weak self] values in
            self?.keyFrameInteractionGeneration = UUID()
            self?.keyFramePreviewResumePending = false
            self?.updateValues { _ in
                return values
            }
        }
        
        rectDisposable.set(genericView.selectionRectView.updatedRect.start(next: { [weak self] rect in
            self?.genericView.selectionRectView.applyRect(rect, force: true, dimensions: .square)
            self?.updateUserInterface(self?.firstTime ?? false)
        }))
        
        valuesDisposable.set(self.scrubberValuesSignal.start(next: { [weak self] values in
            guard let self, self.scrubberValues.with({ $0 }) == values else { return }
            self.genericView.scrubberView.apply(values: values)
            self.applyValuesToPlayer(values)
        }))
        
        
        play()
        readyOnce()
    }
    
}



public func selectVideoAvatar(context: any AccountContextProtocol, path: String, localize: String, quality: String = AVAssetExportPresetMediumQuality, signal:@escaping(Signal<VideoAvatarGeneratorState, NoError>)->Void, confirm: ((Signal<URL, NoError>, @escaping()->Void)->Void)? = nil) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let prepared = prepareEditedAvatarVideo(asset) else {
        signal(.single(.error))
        return
    }
    let controller = VideoAvatarModalController(context: context, asset: prepared.composition, track: prepared.track, localize: localize, quality: quality, holder: asset, confirm: confirm)
    showModal(with: controller, for: context.window)
    signal(controller.completeState)
}


private func generateVideo(_ asset: AVComposition, composition: AVVideoComposition, quality: String, values: VideoScrubberValues) -> Signal<VideoAvatarGeneratorState, NoError> {
    generateEditedAvatarVideo(asset, composition: composition, quality: quality, leftTrim: Double(values.leftTrim), rightTrim: Double(values.rightTrim), keyFrame: values.keyFrame.map(Double.init))
}
