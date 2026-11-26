import Cocoa
import AVFoundation
import SwiftSignalKit

private let threadPool = ThreadPool(threadCount: 2, threadPriority: 0.3)

private final class ImageRenderState {
    private var lock = os_unfair_lock()
    private var cancelled = false
    private var alreadyRendered: TransformImageArguments?

    init(alreadyRendered: TransformImageArguments?) {
        self.alreadyRendered = alreadyRendered
    }

    func takeRendered() -> (cancelled: Bool, alreadyRendered: TransformImageArguments?) {
        os_unfair_lock_lock(&lock)
        let result = (cancelled, alreadyRendered)
        alreadyRendered = nil
        os_unfair_lock_unlock(&lock)
        return result
    }

    func restoreRendered(_ value: TransformImageArguments) {
        os_unfair_lock_lock(&lock)
        let previous = alreadyRendered
        if !cancelled {
            alreadyRendered = value
        }
        os_unfair_lock_unlock(&lock)
        withExtendedLifetime(previous) {}
    }

    func cancel() {
        os_unfair_lock_lock(&lock)
        cancelled = true
        os_unfair_lock_unlock(&lock)
    }

    var isCancelled: Bool {
        os_unfair_lock_lock(&lock)
        let result = cancelled
        os_unfair_lock_unlock(&lock)
        return result
    }
}

public class CaptureProtectedContentLayer: AVSampleBufferDisplayLayer {
    public override func action(forKey event: String) -> CAAction? {
        return nullAction
    }
}


protocol TransformImageRenderHost: AnyObject {
    var transformImageHostLayer: CALayer? { get }
    var transformImageDisplayView: NSView? { get }
    func transformImageApplyContents(_ image: CGImage?, sampleBuffer: CMSampleBuffer?, updated: Bool)
    func transformImageDidUpdate(_ image: CGImage?)
}

final class TransformImageRenderer {
    weak var host: TransformImageRenderHost?
    private let disposable = MetaDisposable()
    private var signalVersion: UInt64 = 0
    private var renderState: ImageRenderState?
    var animatesAlphaOnFirstTransition: Bool = false
    private let argumentsPromise = ValuePromise<TransformImageArguments>(ignoreRepeated: true)
    private(set) var isFullyLoaded: Bool = false
    var ignoreFullyLoad: Bool = false
    private var first: Bool = true
    private(set) var image: CGImage? = nil

    init() {
    }

    init(host: TransformImageRenderHost) {
        self.host = host
    }

    deinit {
        cancel()
    }

    func cancel() {
        renderState?.cancel()
        disposable.dispose()
    }

    func clear() {
        let version = invalidateSignal()
        guard version == signalVersion else { return }
        self.isFullyLoaded = false
        self.updateImage(nil)
    }

    func updateImage(_ image: CGImage?, sampleBuffer: CMSampleBuffer? = nil, trackDisplay: Bool = true) {
        let updated = self.image != image
        host?.transformImageApplyContents(image, sampleBuffer: sampleBuffer, updated: updated)
        if updated {
            self.image = image
            host?.transformImageDidUpdate(image)
            if trackDisplay {
                noteImageDisplayed()
            }
        }
    }

    func noteImageDisplayed() {
        if let image = self.image, let view = host?.transformImageDisplayView, view.window != nil {
            ScopedImageCache.noteDisplayed(image, in: view)
        }
    }

    private func invalidateSignal() -> UInt64 {
        signalVersion &+= 1
        let version = signalVersion
        let previousRenderState = renderState
        renderState = nil
        previousRenderState?.cancel()
        withExtendedLifetime(previousRenderState) {
            disposable.set(nil)
        }
        return version
    }

    private func installSignal(_ value: Disposable, version: UInt64) {
        if version == signalVersion {
            disposable.set(value)
        } else {
            value.dispose()
        }
    }

    func dispose() {
        _ = invalidateSignal()
    }

    func setSignal(signal: Signal<TransformImageResult?, NoError>, clearInstantly: Bool, animate: Bool) {
        let version = invalidateSignal()
        guard version == signalVersion else { return }
        let subscription = (signal |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, version == self.signalVersion, let host = self.host else { return }
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
                host.transformImageHostLayer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            } else if animate {
                host.transformImageHostLayer?.animateContents()
            }
        })
        installSignal(subscription, version: version)
    }

    func setSignal(_ signal: Signal<ImageDataTransformation, NoError>, clearInstantly: Bool, animate: Bool, synchronousLoad: Bool, cacheImage: @escaping (TransformImageResult) -> Void, isProtected: Bool, alreadyRendered: TransformImageArguments?) {
        let version = invalidateSignal()
        guard version == signalVersion else { return }
        if clearInstantly {
            self.updateImage(nil)
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

        let renderState = ImageRenderState(alreadyRendered: alreadyRendered)
        self.renderState = renderState
        let result = combine |> map { data, arguments -> TransformImageResult? in
            let state = renderState.takeRendered()
            guard !state.cancelled else { return nil }
            if let rendered = state.alreadyRendered, rendered == arguments, data.data.fullSizeComplete {
                renderState.restoreRendered(rendered)
                return nil
            }
            let context = data.execute(arguments, data.data)
            guard context == nil || !renderState.isCancelled else { return nil }
            let image = context?.generateDisplayImage()
            if isProtected, image != nil, renderState.isCancelled {
                return nil
            }
            return TransformImageResult(image, context?.isHighQuality ?? false, isProtected ? image?.cmSampleBuffer : nil)
        } |> deliverOnMainQueue

        let subscription = result.start(next: { [weak self] result in
            guard let self, version == self.signalVersion, let result, let host = self.host else { return }
            let animateFirst = self.image == nil && self.animatesAlphaOnFirstTransition
            let animateContents = !self.first && animate
            self.first = false
            self.updateImage(result.image, sampleBuffer: result.sampleBuffer, trackDisplay: false)
            guard version == self.signalVersion else { return }
            if animateFirst {
                host.transformImageHostLayer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            if animateContents {
                host.transformImageHostLayer?.animateContents()
            }
            cacheImage(result)
            if version == self.signalVersion {
                self.noteImageDisplayed()
            }
        })
        installSignal(subscription, version: version)
    }

    func set(arguments: TransformImageArguments) {
        argumentsPromise.set(arguments)
    }
}

open class TransformImageView: NSView, TransformImageRenderHost {
    public var imageUpdated: ((Any?) -> Void)?
    private let renderer = TransformImageRenderer()
    public var animatesAlphaOnFirstTransition: Bool {
        get { renderer.animatesAlphaOnFirstTransition }
        set { renderer.animatesAlphaOnFirstTransition = newValue }
    }
    public var isFullyLoaded: Bool {
        return renderer.isFullyLoaded
    }
    public var ignoreFullyLoad: Bool {
        get { renderer.ignoreFullyLoad }
        set { renderer.ignoreFullyLoad = newValue }
    }
    public init() {
        super.init(frame: NSZeroRect)
        renderer.host = self
        self.wantsLayer = true
        self.layer?.disableActions()
        self.background = .clear
        layerContentsRedrawPolicy = .never
    }
    
    public func clear() {
        renderer.clear()
    }
    
    open override var isFlipped: Bool {
        return true
    }
    public var image: CGImage? {
        set { renderer.updateImage(newValue) }
        get { renderer.image }
    }

    var transformImageHostLayer: CALayer? { layer }
    var transformImageDisplayView: NSView? { self }

    func transformImageApplyContents(_ image: CGImage?, sampleBuffer: CMSampleBuffer?, updated: Bool) {
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
    }

    func transformImageDidUpdate(_ image: CGImage?) {
        imageUpdated?(image)
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

    
    private var captureProtectedContentLayer: CaptureProtectedContentLayer?

    
    public var preventsCapture: Bool = false {
        didSet {
            guard preventsCapture != oldValue else {
                return
            }
            if self.preventsCapture {
                let captureProtectedContentLayer = CaptureProtectedContentLayer()
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

    private func enqueueProtected(_ image: CGImage?, sampleBuffer: CMSampleBuffer?, in layer: CaptureProtectedContentLayer) {
        if let sampleBuffer = sampleBuffer ?? image?.cmSampleBuffer {
            layer.flush()
            layer.enqueue(sampleBuffer)
        } else {
            layer.flushAndRemoveImage()
        }
    }

    
    required public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        renderer.host = self
        self.wantsLayer = true
        self.layer?.disableActions()
        self.background = .clear
        layerContentsRedrawPolicy = .never
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        renderer.cancel()
    }

    public func dispose() {
        renderer.dispose()
    }

    public func setSignal(signal: Signal<TransformImageResult?, NoError>, clearInstantly: Bool = true, animate: Bool = false) {
        renderer.setSignal(signal: signal, clearInstantly: clearInstantly, animate: animate)
    }

    open override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderer.noteImageDisplayed()
    }

    public func setSignal(_ signal: Signal<ImageDataTransformation, NoError>, clearInstantly: Bool = false, animate:Bool = false, synchronousLoad: Bool = false, cacheImage:@escaping(TransformImageResult) -> Void = { _ in }, isProtected: Bool = false, alreadyRendered: TransformImageArguments? = nil) {
        renderer.setSignal(signal, clearInstantly: clearInstantly, animate: animate, synchronousLoad: synchronousLoad, cacheImage: cacheImage, isProtected: isProtected, alreadyRendered: alreadyRendered)
    }
    
    
    open override var isHidden: Bool {
        didSet {
           
        }
    }
    
    public var hasImage: Bool {
        return image != nil
    }
    
    public func set(arguments:TransformImageArguments) ->Void {
        renderer.set(arguments: arguments)
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

public final class TransformImageLayer: SimpleLayer, TransformImageRenderHost {
    private lazy var renderer = TransformImageRenderer(host: self)

    public var imageUpdated: ((Any?) -> Void)?
    public weak var visibilityView: NSView? {
        didSet {
            if visibilityView !== oldValue {
                renderer.noteImageDisplayed()
            }
        }
    }

    public var animatesAlphaOnFirstTransition: Bool {
        get { renderer.animatesAlphaOnFirstTransition }
        set { renderer.animatesAlphaOnFirstTransition = newValue }
    }
    public var isFullyLoaded: Bool {
        return renderer.isFullyLoaded
    }
    public var ignoreFullyLoad: Bool {
        get { renderer.ignoreFullyLoad }
        set { renderer.ignoreFullyLoad = newValue }
    }

    public override init() {
        super.init()
        anchorPoint = .zero
    }

    public override init(frame frameRect: NSRect) {
        super.init()
        anchorPoint = .zero
        self.frame = frameRect
    }

    public override init(layer: Any) {
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var transformImageHostLayer: CALayer? { self }
    var transformImageDisplayView: NSView? { visibilityView }

    func transformImageApplyContents(_ image: CGImage?, sampleBuffer: CMSampleBuffer?, updated: Bool) {
        if image != nil || contents != nil {
            contents = image
        }
    }

    func transformImageDidUpdate(_ image: CGImage?) {
        imageUpdated?(image)
    }

    public var image: CGImage? {
        set { renderer.updateImage(newValue) }
        get { renderer.image }
    }

    public var hasImage: Bool {
        return image != nil
    }

    public func hostDidMoveToWindow() {
        renderer.noteImageDisplayed()
    }

    public func clear() {
        renderer.clear()
    }

    public func dispose() {
        renderer.dispose()
    }

    public func setSignal(signal: Signal<TransformImageResult?, NoError>, clearInstantly: Bool = true, animate: Bool = false) {
        let unprotected = signal |> map { result -> TransformImageResult? in
            return result?.sampleBuffer == nil ? result : nil
        }
        renderer.setSignal(signal: unprotected, clearInstantly: clearInstantly, animate: animate)
    }

    public func setSignal(_ signal: Signal<ImageDataTransformation, NoError>, clearInstantly: Bool = false, animate: Bool = false, synchronousLoad: Bool = false, cacheImage: @escaping (TransformImageResult) -> Void = { _ in }, alreadyRendered: TransformImageArguments? = nil) {
        renderer.setSignal(signal, clearInstantly: clearInstantly, animate: animate, synchronousLoad: synchronousLoad, cacheImage: cacheImage, isProtected: false, alreadyRendered: alreadyRendered)
    }

    public func set(arguments: TransformImageArguments) {
        renderer.set(arguments: arguments)
    }
}
