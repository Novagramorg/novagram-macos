import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import ObjcUtils
import TGVideoCameraMovie
import AVFoundation

public class VideoRecorderModalView: View {
    private let captureLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer()
    private let captureContainer: View = View()
    private let placeholderView: ImageView = ImageView()
    private let progressView:  RadialProgressView
    private let previewPlayer: GIFPlayerView = GIFPlayerView()
    private let shadowView: ImageView = ImageView()

    private var pausedPlayer: AVPlayer?
    private var pausedPlayerLayer: AVPlayerLayer?
    private var pausedPath: String?
    private var pausedTrimRange: Range<Double>?
    private var pausedVideoRange: Range<Double>?
    private var pausedEndObserver: Any?
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    public init(frame frameRect: NSRect, thumbnail: CGImage?) {
        progressView = RadialProgressView(theme: RadialProgressTheme(backgroundColor: .clear, foregroundColor: theme.colors.accent, icon: nil, iconInset: NSEdgeInsets(), lineWidth: 4), twist: false)
        super.init(frame: frameRect)
        addSubview(shadowView)
        addSubview(captureContainer)

        
        
        captureContainer.addSubview(previewPlayer)
        
        backgroundColor = .clear
        captureContainer.setFrameSize(frameRect.width - 36, frameRect.height - 36)
        placeholderView.animates = false
        placeholderView.isAccessibilityDecorative = true
        shadowView.isAccessibilityDecorative = true
        placeholderView.image = thumbnail ?? TelegramThemeHooks.shared.image(.videoMessagePlaceholder).precomposed()
        placeholderView.frame = bounds
        captureContainer.addSubview(placeholderView)
        placeholderView.center()
        
        captureContainer.layer?.addSublayer(captureLayer)
        captureLayer.videoGravity = .resizeAspectFill
        captureLayer.frame = captureContainer.bounds
        captureContainer.layer?.cornerRadius = captureContainer.frame.width/2
        captureLayer.actions = ["opacity": NSNull()]
        captureLayer.opacity = 0
        
        progressView.frame = NSMakeRect(0, 0, captureContainer.frame.width + 17, captureContainer.frame.height + 17)
        addSubview(progressView)
        
        previewPlayer.frame = captureContainer.bounds
        
        shadowView.image = TelegramThemeHooks.shared.image(.iconVideoMessageShadow).precomposed()
        shadowView.setFrameSize(NSMakeSize(frameRect.width, frameRect.height))
    }
    
    public var previewView: NSView {
        return captureContainer
    }

    public func updateWithSession(_ session: AVCaptureSession) {
        captureLayer.session = session
        captureLayer.connection?.automaticallyAdjustsVideoMirroring = false
        captureLayer.connection?.isVideoMirrored = true
    }
    
    public func updatePaused(_ path: String) {
        hideGIFPreview()
        setupPausedPlayer(path)
        placeholderView.layer?.opacity = 0
        captureLayer.opacity = 0
    }
    
    public func updateResumed() {
        hideGIFPreview()
        captureLayer.opacity = 1
        if pausedPlayer != nil {
            fadeOutPausedPlayer()
        } else {
            placeholderView.layer?.opacity = 1
        }
    }

    private func fadeOutPausedPlayer() {
        guard let player = pausedPlayer, let layer = pausedPlayerLayer else {
            tearDownPausedPlayer()
            return
        }
        player.pause()
        if let observer = pausedEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pausedEndObserver = nil
        pausedPlayer = nil
        pausedTrimRange = nil
        pausedVideoRange = nil
        pausedPath = nil
        layer.opacity = 0
        layer.animateAlpha(from: 1, to: 0, duration: 0.3, completion: { [weak layer] _ in
            layer?.removeFromSuperlayer()
        })
    }
    
    private func hideGIFPreview() {
        previewPlayer.set(data: nil)
        previewPlayer.isHidden = true
    }
    
    public func updatePreview(trimRange: Range<Double>?, seekTo: Double, play: Bool) {
        guard let player = pausedPlayer else {
            return
        }
        pausedTrimRange = trimRange
        if let trimRange {
            let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
            player.currentItem?.forwardPlaybackEndTime = CMTimeMakeWithSeconds(clampedPreviewTime(trimRange.upperBound, duration: duration), preferredTimescale: 1000)
        } else {
            player.currentItem?.forwardPlaybackEndTime = .invalid
            player.pause()
        }
        seekPreview(to: seekTo, play: play)
    }
    
    private func seekPreview(to seconds: Double, play: Bool) {
        guard let player = pausedPlayer, let item = player.currentItem else {
            return
        }
        let duration = CMTimeGetSeconds(item.duration)
        if item.status != .readyToPlay, !play {
            return
        }
        let clamped = clampedPreviewTime(seconds, duration: duration)
        player.seek(to: CMTimeMakeWithSeconds(max(0, clamped), preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { [weak self] finished in
            if finished, play {
                self?.pausedPlayer?.play()
            }
        })
    }

    private func clampedPreviewTime(_ seconds: Double, duration: Double) -> Double {
        var end = seconds
        if duration.isFinite, duration > 0 {
            end = min(end, duration - 0.05)
        }
        if let video = pausedVideoRange {
            end = min(end, video.upperBound - 0.05)
            return max(video.lowerBound, end)
        }
        return end
    }

    private func videoRange(of path: String) -> Range<Double>? {
        guard let track = AVURLAsset(url: URL(fileURLWithPath: path)).tracks(withMediaType: .video).first else {
            return nil
        }
        let start = CMTimeGetSeconds(track.timeRange.start)
        let end = CMTimeGetSeconds(track.timeRange.end)
        guard start.isFinite, end.isFinite, end > start else {
            return nil
        }
        return start ..< end
    }
    
    private func setupPausedPlayer(_ path: String) {
        if pausedPath == path {
            return
        }
        tearDownPausedPlayer()
        pausedPath = path
        pausedVideoRange = videoRange(of: path)
        
        let player = AVPlayer(url: URL(fileURLWithPath: path))
        player.actionAtItemEnd = .pause
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        layer.frame = captureContainer.bounds
        captureContainer.layer?.addSublayer(layer)
        
        pausedPlayer = player
        pausedPlayerLayer = layer
        pausedEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main, using: { [weak self] _ in
            self?.restartPausedPlayback()
        })
        player.play()
    }
    
    private func restartPausedPlayback() {
        pausedPlayer?.pause()
        seekPreview(to: pausedTrimRange?.lowerBound ?? 0, play: true)
    }
    
    private func tearDownPausedPlayer() {
        if let pausedEndObserver {
            NotificationCenter.default.removeObserver(pausedEndObserver)
        }
        pausedEndObserver = nil
        pausedPlayer?.pause()
        pausedPlayer = nil
        pausedPlayerLayer?.removeFromSuperlayer()
        pausedPlayerLayer = nil
        pausedTrimRange = nil
        pausedVideoRange = nil
        pausedPath = nil
    }
    
    deinit {
        tearDownPausedPlayer()
    }
    
    public func updateForPreview(_ path:String? = nil, preview: CGImage?) -> Void {
        tearDownPausedPlayer()
        previewPlayer.set(data: AVGifData.dataFrom(path))
        placeholderView.image = preview
        
        previewPlayer.isHidden = path == nil
        
        if let _ = path {
            placeholderView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2)
        } else {
            placeholderView.layer?.opacity = 1
        }
        
        progressView.change(opacity: 0, removeOnCompletion: false) { [weak self] completed in
            if completed {
                self?.progressView.removeFromSuperview()
            }
        }
        captureLayer.removeFromSuperlayer()

    }
    
    public func updateProgress(_ progress: Float) {
        progressView.state = .ImpossibleFetching(progress: progress, force: true)
    }
    
    public func didStartedRecording() {
        captureLayer.opacity = 1
        placeholderView.change(opacity: 0.0, duration: 0.3)
       
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        captureContainer.center()
        progressView.center()
        shadowView.center()
        pausedPlayerLayer?.frame = captureContainer.bounds
    }
    
}
