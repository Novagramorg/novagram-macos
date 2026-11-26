import Foundation
import TGUIKit
import SwiftSignalKit
import MetalEngine
import AppKit


open class CallVideoView : Control {
    
    public struct VideoMetrics: Equatable {
        public var resolution: CGSize
        public var rotationAngle: Float
        public var followsDeviceOrientation: Bool
        public var sourceId: Int
        
        public init(resolution: CGSize, rotationAngle: Float, followsDeviceOrientation: Bool, sourceId: Int) {
            self.resolution = resolution
            self.rotationAngle = rotationAngle
            self.followsDeviceOrientation = followsDeviceOrientation
            self.sourceId = sourceId
        }
        
        public var displayResolution: CGSize {
            if self.rotationAngle == Float.pi * 0.5 || self.rotationAngle == Float.pi * 3.0 / 2.0 {
                return CGSize(width: self.resolution.height, height: self.resolution.width)
            }
            return self.resolution
        }
    }
    
    public var videoMetricsDidUpdate:((VideoMetrics?)->Void)?
    
    public internal(set) var videoMetrics: VideoMetrics? {
        didSet {
            if oldValue != videoMetrics {
                updateLayout(size: self.frame.size, transition: .immediate)
                videoMetricsDidUpdate?(videoMetrics)
            }
        }
    }
    
    public var firstFrameRendered: (()->Void)?
    
    open var isPaused: Bool = false
    
    open func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
    }
    
    open func setGravity(_ gravity: CALayerContentsGravity) {
    }
}

public class MetalCallVideoView : CallVideoView {
    
    private let videoLayer: PrivateCallVideoLayer = .init()
    //private let visual = VisualEffect
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.addSublayer(videoLayer.blurredLayer)
        videoLayer.blurredLayer.opacity = 0.2
        self.layer?.addSublayer(videoLayer)
        videoLayer.frame = frameRect
        videoLayer.isDoubleSided = false
        videoLayer.contentsGravity = .resizeAspect
        videoLayer.blurredLayer.contentsGravity = .resizeAspectFill
        self.userInteractionEnabled = false
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        } 
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private var videoOnUpdatedListener: Disposable?

    public var video: VideoSource? {
        didSet {
            if let video = video {
                self.videoOnUpdatedListener?.dispose()
                
                
                self.videoOnUpdatedListener = video.addOnUpdated { [weak self] in
                    guard let self else {
                        return
                    }
                    if let currentOutput = self.video?.currentOutput {
                        self.updateRenderSpecs(output: currentOutput)
                        self.videoLayer.video = currentOutput
                        
                        self.videoMetrics = VideoMetrics(resolution: currentOutput.resolution, rotationAngle: currentOutput.rotationAngle, followsDeviceOrientation: currentOutput.followsDeviceOrientation, sourceId: currentOutput.sourceId)

                    } else {
                        self.videoLayer.renderSpec = nil
                        self.videoLayer.blurredRenderSpec = nil
                        self.videoLayer.video = nil
                        self.videoMetrics = nil
                    }
                    self.updateBlurVisibility()
                    
                    if self.firstFrameRendered != nil {
                        self.firstFrameRendered?()
                        self.firstFrameRendered = nil
                    }

                    self.setNeedsRenderIfVisible()
                }
            } else {
                videoOnUpdatedListener?.dispose()
                self.videoLayer.renderSpec = nil
                self.videoLayer.blurredRenderSpec = nil
                self.videoLayer.video = nil

            }
            
        }
    }
    
    deinit {
        videoOnUpdatedListener?.dispose()
    }
    
    public override var isPaused: Bool {
        didSet {
            if oldValue != self.isPaused {
                self.setNeedsRenderIfVisible()
            }
        }
    }
    
    private func updateRenderSpecs(output: VideoSource.Output) {
        var resolution = output.resolution
        if output.rotationAngle == Float.pi * 0.5 || output.rotationAngle == Float.pi * 3.0 / 2.0 {
            resolution = NSMakeSize(resolution.height, resolution.width)
        }
        var size = resolution.aspectFitted(self.frame.size) * System.backingScale
        if size.width > resolution.width {
            size = resolution
        }
        let renderSize = RenderSize(width: max(1, Int(size.width)), height: max(1, Int(size.height)))
        self.videoLayer.renderSpec = RenderLayerSpec(size: renderSize, edgeInset: 1)
        
        var blurredSize = size
        let blurredMaxSide = max(blurredSize.width, blurredSize.height)
        if blurredMaxSide > 256.0 {
            blurredSize = NSMakeSize(blurredSize.width * 256.0 / blurredMaxSide, blurredSize.height * 256.0 / blurredMaxSide)
        }
        self.videoLayer.blurredRenderSpec = RenderLayerSpec(size: RenderSize(width: max(1, Int(blurredSize.width)), height: max(1, Int(blurredSize.height))), edgeInset: 1)
    }
    
    private func setNeedsRenderIfVisible() {
        if !CallVideoTuning.isOptimized || (!self.isPaused && self.window != nil) {
            self.videoLayer.setNeedsUpdate()
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.setNeedsRenderIfVisible()
    }
    
    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
                
        let frame = NSMakeRect(size.width * 0.5, size.height * 0.5, size.width, size.height)
        
        transition.updateFrame(layer: self.videoLayer, frame: frame, updatePosition: true)
        transition.updateFrame(layer: self.videoLayer.blurredLayer, frame: frame, updatePosition: true)
     
        self.videoLayer.blurredLayer.frame = size.bounds
        self.videoLayer.frame = size.bounds
        self.updateBlurVisibility()
    }
    
    public override func setGravity(_ gravity: CALayerContentsGravity) {
        self.videoLayer.contentsGravity = gravity
        self.updateBlurVisibility()
    }
    
    private func updateBlurVisibility() {
        var isCovered = CallVideoTuning.isOptimized && self.videoLayer.contentsGravity == .resizeAspectFill
        if CallVideoTuning.isOptimized, !isCovered, let output = self.video?.currentOutput, self.frame.width > 0, self.frame.height > 0 {
            var resolution = output.resolution
            if output.rotationAngle == Float.pi * 0.5 || output.rotationAngle == Float.pi * 3.0 / 2.0 {
                resolution = NSMakeSize(resolution.height, resolution.width)
            }
            let fitted = resolution.aspectFitted(self.frame.size)
            isCovered = self.frame.width - fitted.width < 1.0 && self.frame.height - fitted.height < 1.0
        }
        if self.videoLayer.blurredLayer.isHidden != isCovered {
            self.videoLayer.blurredLayer.isHidden = isCovered
        }
    }
}

