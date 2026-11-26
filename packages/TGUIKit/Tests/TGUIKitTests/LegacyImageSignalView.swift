import Cocoa
import AVFoundation
import SwiftSignalKit
@testable import TGUIKit

private let threadPool = ThreadPool(threadCount: 2, threadPriority: 0.3)

public class LegacySignalProtectedLayer: AVSampleBufferDisplayLayer {
    public override func action(forKey event: String) -> CAAction? {
        return nullAction
    }
}


open class LegacyImageSignalView: NSView {
    public var imageUpdated: ((Any?) -> Void)?
    private let disposable = MetaDisposable()
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
        self.isFullyLoaded = false
        self.image = nil
        self.disposable.set(nil)
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


    private var captureProtectedContentLayer: LegacySignalProtectedLayer?


    public var preventsCapture: Bool = false {
        didSet {
            guard preventsCapture != oldValue else {
                return
            }
            if self.preventsCapture {
                let captureProtectedContentLayer = LegacySignalProtectedLayer()
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

    private func enqueueProtected(_ image: CGImage?, sampleBuffer: CMSampleBuffer?, in layer: LegacySignalProtectedLayer) {
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


    public func dispose() {
        disposable.set(nil)
    }

    public func setSignal(signal: Signal<TransformImageResult?, NoError>, clearInstantly: Bool = true, animate: Bool = false) {
        self.disposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] result in

            let hasImage = self?.image != nil
            if clearInstantly {
                self?.updateImage(result?.image, sampleBuffer: result?.sampleBuffer)
            } else if let image = result?.image {
                self?.updateImage(image, sampleBuffer: result?.sampleBuffer)
            }
            if !hasImage && animate {
                self?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            } else if animate {
                self?.layer?.animateContents()
            }
            self?.isFullyLoaded = result?.highQuality ?? false
            if result?.image != nil {
                self?.first = false
            }
        }))
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
        if clearInstantly {
            self.image = nil
        }

        if !isProtected {
            var bp = 0
            bp += 1
        }

        if isFullyLoaded && !ignoreFullyLoad {
            disposable.set(nil)
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

        self.disposable.set(result.start(next: { [weak self] result in
            guard let result else {
                return
            }
            if let strongSelf = self  {
                if strongSelf.image == nil && strongSelf.animatesAlphaOnFirstTransition {
                    strongSelf.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                strongSelf.updateImage(result.image, sampleBuffer: result.sampleBuffer, trackDisplay: false)
                if !strongSelf.first && animate {
                    self?.layer?.animateContents()
                }
                strongSelf.first = false
                cacheImage(result)
                strongSelf.noteImageDisplayed()
            }
        }))

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
