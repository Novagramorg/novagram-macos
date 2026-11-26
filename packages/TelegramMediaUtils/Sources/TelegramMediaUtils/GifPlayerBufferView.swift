import Cocoa
import TelegramCore
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramMedia
import ObjcUtils
import TelegramTheme
import TelegramContext
import TelegramUtils
import CoreMedia

public final class GifPlayerBufferView : TransformImageView {
    public var timebase: CMTimebase!

    private var videoLayer: (SoftwareVideoLayerFrameManager, SampleBufferLayer)?
    public private(set) var imageHolder: CGImage?
    public override init() {
        super.init()
        initialize()
    }

    private func initialize() {
        let timebase = createTimebase()!.takeRetainedValue()
        CMTimebaseSetRate(timebase, rate: 0.0)
        self.timebase = timebase
    }
    
    private var fileReference: FileMediaReference?
    private var account: Account?
    private var resizeInChat: Bool = false
    
    public private(set) var isRendering: Bool = false
    
    public func update(_ fileReference: FileMediaReference, context: any AccountContextProtocol, resizeInChat: Bool = false) -> Void {
        
        let updated = self.fileReference == nil || fileReference.media.fileId != self.fileReference!.media.fileId
        self.fileReference = fileReference
        self.account = context.account
        self.resizeInChat = resizeInChat
        if updated {
            self.isRendering = false
            self.videoLayer?.1.layer.removeFromSuperlayer()
            self.videoLayer = nil
            if self.window != nil {
                self.setupVideoLayer()
            }
        }
        
        
        needsLayout = true
    }
    
    private func setupVideoLayer() {
        guard let fileReference = self.fileReference, let account = self.account else {
            return
        }
        let layerHolder = takeSampleBufferLayer()
        if let gravity = gravity {
            layerHolder.layer.videoGravity = gravity
        } else {
            layerHolder.layer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        }
        layerHolder.layer.backgroundColor = NSColor.clear.cgColor
        self.layer?.addSublayer(layerHolder.layer)
        let manager = SoftwareVideoLayerFrameManager(account: account, fileReference: fileReference, layerHolder: layerHolder)
        self.videoLayer = (manager, layerHolder)
        
        manager.onRender = { [weak self] in
            if self?.image != nil {
                self?.imageHolder = self?.image
                self?.clear()
                self?.image = nil
                self?.isRendering = true
            }
        }
        manager.start()
        needsLayout = true
    }
    
    private func releaseVideoLayer() {
        guard let videoLayer = self.videoLayer else {
            return
        }
        videoLayer.1.layer.removeFromSuperlayer()
        self.videoLayer = nil
        if self.isRendering, self.image == nil, let imageHolder = self.imageHolder {
            self.image = imageHolder
        }
        self.isRendering = false
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window == nil {
            self.releaseVideoLayer()
        } else if self.videoLayer == nil {
            self.setupVideoLayer()
        }
    }
    
    public override func layout() {
        super.layout()
        
        if let file = fileReference?.media, resizeInChat {
            let dimensions = file.dimensions?.size ?? frame.size
            let size = dimensions.aspectFitted(frame.size)
            let rect = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - size.width) / 2), floorToScreenPixels(backingScaleFactor, (frame.height - size.height) / 2), size.width, size.height)
            videoLayer?.1.layer.frame = rect
        } else {
            videoLayer?.1.layer.frame = bounds
        }
        
    }
    
    private var gravity: AVLayerVideoGravity?
    
    public func setVideoLayerGravity(_ gravity: AVLayerVideoGravity) {
        self.gravity = gravity
        videoLayer?.1.layer.videoGravity = gravity
    }
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initialize()
    }
    
    private var displayLink: ConstantDisplayLinkAnimator?
    public var ticking: Bool = false {
        didSet {
            if self.ticking != oldValue {
                if self.ticking {
                    let displayLink = ConstantDisplayLinkAnimator(update: { [weak self] in
                        self?.displayLinkEvent()
                    }, fps: 25)
                    self.displayLink = displayLink
                    displayLink.isPaused = false
                    CMTimebaseSetRate(self.timebase, rate: 1.0)
                } else if let displayLink = self.displayLink {
                    self.displayLink = nil
                    displayLink.isPaused = true
                    displayLink.invalidate()
                    CMTimebaseSetRate(self.timebase, rate: 0.0)
                }
            }
        }
    }
    
    
    private func displayLinkEvent() {
        let timestamp = CMTimebaseGetTime(self.timebase).seconds
        self.videoLayer?.0.tick(timestamp: timestamp)
    }
    

    private let maskLayer = CAShapeLayer()
    
    public var positionFlags: LayoutPositionFlags? {
        didSet {
            if let positionFlags = positionFlags {
                maskLayer.path = CGPath.bubbleCorners(size: frame.size, flags: positionFlags)
                layer?.mask = maskLayer
            } else {
                layer?.mask = nil
            }
        }
    }
    
}
