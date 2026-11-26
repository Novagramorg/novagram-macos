import Foundation
import AppKit
import Metal
import TGUIKit
import SwiftSignalKit
import TelegramVoip

#if arch(arm64)
public let isNativeCallVideoRenderingAvailable: Bool = false
#else
public let isNativeCallVideoRenderingAvailable: Bool = MTLCreateSystemDefaultDevice() != nil
#endif

func callVideoMetrics(displayAspect aspect: CGFloat) -> CallVideoView.VideoMetrics? {
    guard aspect.isFinite, aspect > 0 else {
        return nil
    }
    return CallVideoView.VideoMetrics(resolution: CGSize(width: aspect * 1000.0, height: 1000.0), rotationAngle: 0, followsDeviceOrientation: false, sourceId: 0)
}

func callVideoMirrorTransform(width: CGFloat) -> CATransform3D {
    var transform = CATransform3DIdentity
    transform = CATransform3DTranslate(transform, width / 2, 0, 0)
    transform = CATransform3DScale(transform, -1, 1, 1)
    transform = CATransform3DTranslate(transform, -(width / 2), 0, 0)
    return transform
}

func nativeCallVideoDisplayAspect(reported: CGFloat, fallback: CGFloat) -> CGFloat {
    if reported.isFinite, reported > 0 {
        return reported
    }
    return fallback
}

public final class NativeCallVideoView : CallVideoView {
    private let video: OngoingCallContextPresentationCallVideoView
    private var hasFirstFrame = false
    private var aspectTimer: SwiftSignalKit.Timer?

    public init(video: OngoingCallContextPresentationCallVideoView) {
        self.video = video
        super.init(frame: NSMakeRect(0, 0, 300, 300))
        self.userInteractionEnabled = false
        self.layer?.masksToBounds = true
        if #available(macOS 10.15, *) {
            self.layer?.cornerCurve = .continuous
        }
        video.view.frame = self.bounds
        self.addSubview(video.view)
        video.setVideoContentMode(.resizeAspect)

        video.setOnFirstFrameReceived({ [weak self] aspect in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.hasFirstFrame = true
                self.refreshMetrics(fallbackAspect: CGFloat(aspect))
                if let firstFrameRendered = self.firstFrameRendered {
                    self.firstFrameRendered = nil
                    firstFrameRendered()
                }
                self.updateAspectPolling()
            }
        })
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.aspectTimer?.invalidate()
        self.video.setOnFirstFrameReceived(nil)
    }

    private func refreshMetrics(fallbackAspect: CGFloat) {
        let aspect = nativeCallVideoDisplayAspect(reported: self.video.getAspect(), fallback: fallbackAspect)
        if let metrics = callVideoMetrics(displayAspect: aspect) {
            self.videoMetrics = metrics
        }
    }

    private func updateAspectPolling() {
        if self.hasFirstFrame, self.window != nil, !self.isPaused {
            if self.aspectTimer == nil {
                let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
                    guard let self, let metrics = self.videoMetrics else {
                        return
                    }
                    self.refreshMetrics(fallbackAspect: metrics.resolution.width / max(1.0, metrics.resolution.height))
                }, queue: Queue.mainQueue())
                self.aspectTimer = timer
                timer.start()
            }
        } else {
            self.aspectTimer?.invalidate()
            self.aspectTimer = nil
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateAspectPolling()
    }

    public var isMirrored: Bool = false {
        didSet {
            if oldValue != self.isMirrored {
                self.updateMirroring()
            }
        }
    }
    
    private func updateMirroring() {
        self.layer?.sublayerTransform = self.isMirrored ? callVideoMirrorTransform(width: self.bounds.width) : CATransform3DIdentity
    }
    
    public override var isPaused: Bool {
        didSet {
            if oldValue != self.isPaused {
                self.video.setIsPaused(self.isPaused)
                self.updateAspectPolling()
            }
        }
    }

    public override func setGravity(_ gravity: CALayerContentsGravity) {
        self.video.setVideoContentMode(gravity)
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self.video.view, frame: size.bounds)
        if self.isMirrored {
            self.layer?.sublayerTransform = callVideoMirrorTransform(width: size.width)
        }
    }
}
