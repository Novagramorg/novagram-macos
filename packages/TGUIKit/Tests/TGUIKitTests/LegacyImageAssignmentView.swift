import Cocoa
import AVFoundation
import SwiftSignalKit
@testable import TGUIKit

private let threadPool = ThreadPool(threadCount: 2, threadPriority: 0.3)

public class LegacyAssignmentProtectedLayer: AVSampleBufferDisplayLayer {
    public override func action(forKey event: String) -> CAAction? {
        return nullAction
    }
}


open class LegacyImageAssignmentView: NSView {
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
    private var sampleBuffer: CMSampleBuffer?

    public var image: CGImage? {
        set {
            let updated = _image != newValue
            if let captureProtectedContentLayer {
                layer?.contents = nil
                if updated {
                    enqueueProtected(newValue, sampleBuffer: sampleBuffer, in: captureProtectedContentLayer)
                }
            } else {
                layer?.contents = newValue
            }
            sampleBuffer = nil
            if updated {
                imageUpdated?(newValue)
                _image = newValue
                noteImageDisplayed()
            }
        }
        get {
            return _image
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


    private var captureProtectedContentLayer: LegacyAssignmentProtectedLayer?


    public var preventsCapture: Bool = false {
        didSet {
            guard preventsCapture != oldValue else {
                return
            }
            if self.preventsCapture {
                let captureProtectedContentLayer = LegacyAssignmentProtectedLayer()
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

    private func enqueueProtected(_ image: CGImage?, sampleBuffer: CMSampleBuffer?, in layer: LegacyAssignmentProtectedLayer) {
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
            self?.sampleBuffer = result?.sampleBuffer
            if clearInstantly {
                self?.image = result?.image
            } else if let image = result?.image {
                self?.image = image
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
                self?.sampleBuffer = result.sampleBuffer
                self?.image = result.image
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
