import Cocoa
import AVFoundation
import SwiftSignalKit
@testable import TGUIKit

private let threadPool = ThreadPool(threadCount: 2, threadPriority: 0.3)

public class LegacyImageRenderProtectedLayer: AVSampleBufferDisplayLayer {
    public override func action(forKey event: String) -> CAAction? {
        return nullAction
    }
}


open class LegacyImageRenderView: NSView {
    public var imageUpdated: ((Any?) -> Void)?
    private let disposable = MetaDisposable()
    private var signalVersion: UInt64 = 0
    public var animatesAlphaOnFirstTransition:Bool = false
    private let argumentsPromise = ValuePromise<TransformImageArguments>(ignoreRepeated: true)
    public private(set) var isFullyLoaded: Bool = false
    public var ignoreFullyLoad:Bool = false
    private var first:Bool = true
    public init() {
        super.init(frame: NSZeroRect)
        self.wantsLayer = true
        self.layer?.disableActions()
        self.background = .clear
        layerContentsRedrawPolicy = .never
    }

    public func clear() {
        let version = invalidateSignal()
        guard version == signalVersion else { return }
        self.isFullyLoaded = false
        self.image = nil
    }

    open override var isFlipped: Bool {
        return true
    }
    private var _image: CGImage? = nil
    public var image: CGImage? {
        set { updateImage(newValue) }
        get { _image }
    }

    private func updateImage(_ image: CGImage?, sampleBuffer: CMSampleBuffer? = nil, trackDisplay: Bool = true) {
        let updated = _image != image
        if let captureProtectedContentLayer {
            if layer?.contents != nil {
                layer?.contents = nil
            }
            if updated {
                enqueueProtected(image, sampleBuffer: sampleBuffer, in: captureProtectedContentLayer)
            }
        } else if image != nil || layer?.contents != nil {
            layer?.contents = image
        }
        if updated {
            _image = image
            imageUpdated?(image)
            if trackDisplay {
                noteImageDisplayed()
            }
        }
    }

    open override var bounds: CGRect {
        didSet {
            if let captureProtectedContentLayer = self.captureProtectedContentLayer {
                captureProtectedContentLayer.frame = super.bounds
            }
        }
    }

    open override var frame: CGRect {
        didSet {
            if let captureProtectedContentLayer = self.captureProtectedContentLayer {
                captureProtectedContentLayer.frame = super.bounds
            }
        }
    }


    private var captureProtectedContentLayer: LegacyImageRenderProtectedLayer?


    public var preventsCapture: Bool = false {
        didSet {
            guard preventsCapture != oldValue else {
                return
            }
            if self.preventsCapture {
                let captureProtectedContentLayer = LegacyImageRenderProtectedLayer()
                captureProtectedContentLayer.frame = self.bounds
                captureProtectedContentLayer.videoGravity = .resize
                if #available(macOS 10.15, *) {
                    captureProtectedContentLayer.preventsCapture = true
                }
                self.layer?.addSublayer(captureProtectedContentLayer)
                self.captureProtectedContentLayer = captureProtectedContentLayer
                self.layer?.contents = nil
                enqueueProtected(self.image, sampleBuffer: nil, in: captureProtectedContentLayer)
            } else {
                if let captureProtectedContentLayer = self.captureProtectedContentLayer {
                    self.captureProtectedContentLayer = nil
                    captureProtectedContentLayer.removeFromSuperlayer()
                }
                self.layer?.contents = self.image
            }
        }
    }

    private func enqueueProtected(_ image: CGImage?, sampleBuffer: CMSampleBuffer?, in layer: LegacyImageRenderProtectedLayer) {
        if let sampleBuffer = sampleBuffer ?? image?.cmSampleBuffer {
            layer.flush()
            layer.enqueue(sampleBuffer)
        } else {
            layer.flushAndRemoveImage()
        }
    }


    required public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.disableActions()
        self.background = .clear
        layerContentsRedrawPolicy = .never
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable.dispose()
    }


    private func invalidateSignal() -> UInt64 {
        signalVersion &+= 1
        let version = signalVersion
        disposable.set(nil)
        return version
    }

    private func installSignal(_ value: Disposable, version: UInt64) {
        if version == signalVersion {
            disposable.set(value)
        } else {
            value.dispose()
        }
    }

    public func dispose() {
        _ = invalidateSignal()
    }

    public func setSignal(signal: Signal<TransformImageResult?, NoError>, clearInstantly: Bool = true, animate: Bool = false) {
        let version = invalidateSignal()
        guard version == signalVersion else { return }
        let subscription = (signal |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, version == self.signalVersion else { return }
            let hasImage = self.image != nil
            self.isFullyLoaded = result?.highQuality ?? false
            if result?.image != nil {
                self.first = false
            }
            if clearInstantly {
                self.updateImage(result?.image, sampleBuffer: result?.sampleBuffer)
            } else if let image = result?.image {
                self.updateImage(image, sampleBuffer: result?.sampleBuffer)
            }
            guard version == self.signalVersion else { return }
            if !hasImage && animate {
                self.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            } else if animate {
                self.layer?.animateContents()
            }
        })
        installSignal(subscription, version: version)
    }

    open override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        noteImageDisplayed()
    }

    private func noteImageDisplayed() {
        if let image = _image, window != nil {
            ScopedImageCache.noteDisplayed(image, in: self)
        }
    }


    public func setSignal(_ signal: Signal<ImageDataTransformation, NoError>, clearInstantly: Bool = false, animate:Bool = false, synchronousLoad: Bool = false, cacheImage:@escaping(TransformImageResult) -> Void = { _ in }, isProtected: Bool = false, alreadyRendered: TransformImageArguments? = nil) {
        let version = invalidateSignal()
        guard version == signalVersion else { return }
        if clearInstantly {
            self.image = nil
        }
        guard version == signalVersion else { return }

        if isFullyLoaded && !ignoreFullyLoad {
            isFullyLoaded = false
            return
        }

        var combine = combineLatest(signal, argumentsPromise.get())

        if !synchronousLoad {
            combine = combine |> deliverOn(threadPool)
        }

        let skipsRendered = Atomic<TransformImageArguments?>(value: alreadyRendered)
        let result = combine |> map { data, arguments -> TransformImageResult? in
            let rendered = skipsRendered.swap(nil)
            if let rendered, rendered == arguments, data.data.fullSizeComplete {
                _ = skipsRendered.swap(rendered)
                return nil
            }
            let context = data.execute(arguments, data.data)
            let image = context?.generateDisplayImage()
            return TransformImageResult(image, context?.isHighQuality ?? false, isProtected ? image?.cmSampleBuffer : nil)
        } |> deliverOnMainQueue

        let subscription = result.start(next: { [weak self] result in
            guard let self, version == self.signalVersion, let result else { return }
            let animateFirst = self.image == nil && self.animatesAlphaOnFirstTransition
            let animateContents = !self.first && animate
            self.first = false
            self.updateImage(result.image, sampleBuffer: result.sampleBuffer, trackDisplay: false)
            guard version == self.signalVersion else { return }
            if animateFirst {
                self.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            if animateContents {
                self.layer?.animateContents()
            }
            cacheImage(result)
            if version == self.signalVersion {
                self.noteImageDisplayed()
            }
        })
        installSignal(subscription, version: version)

    }


    open override var isHidden: Bool {
        didSet {

        }
    }

    public var hasImage: Bool {
        return image != nil
    }

    public func set(arguments:TransformImageArguments) ->Void {
        argumentsPromise.set(arguments)
    }


    override open func copy() -> Any {

        let visibleRect = self.effectiveVisibleRect

        let view = NSView()
        view.wantsLayer = true
        view.background = .clear
        view.layer?.contents = self.image
        view.frame = visibleRect
        view.layer?.masksToBounds = true


        if bounds != visibleRect {
            if let image = self.layer?.contents {
                view.layer?.contents = generateImage(bounds.size, contextGenerator: { size, ctx in
                    ctx.clear(bounds)
                    ctx.setFillColor(.clear)
                    ctx.fill(bounds)
                    if visibleRect.minY != 0  {
                        ctx.clip(to: NSMakeRect(0, 0, bounds.width, bounds.height - ( bounds.height - visibleRect.height)))
                    } else {
                        ctx.clip(to: NSMakeRect(0, (bounds.height - visibleRect.height), bounds.width, bounds.height - ( bounds.height - visibleRect.height)))
                    }
                    ctx.draw(image as! CGImage, in: bounds)
                }, opaque: false)
            }
        }

        view.layer?.shouldRasterize = true
        view.layer?.rasterizationScale = backingScaleFactor

        return view
    }


}
