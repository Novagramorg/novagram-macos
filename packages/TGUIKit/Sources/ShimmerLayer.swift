import Foundation
import Cocoa
import SwiftSignalKit


private final class ShimmerGradientCache {
    static let shared = ShimmerGradientCache()

    private struct Key: Hashable {
        let background: CGColor
        let foreground: CGColor
        let colorSpace: CGColorSpace
        let width: CGFloat
        let height: CGFloat
        let horizontal: Bool

        static func ==(lhs: Key, rhs: Key) -> Bool {
            lhs.width == rhs.width && lhs.height == rhs.height && lhs.horizontal == rhs.horizontal && CFEqual(lhs.background, rhs.background) && CFEqual(lhs.foreground, rhs.foreground) && CFEqual(lhs.colorSpace, rhs.colorSpace)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(horizontal)
            hasher.combine(CFHash(background))
            hasher.combine(CFHash(foreground))
            hasher.combine(CFHash(colorSpace))
        }
    }

    private struct Entry {
        weak var image: CGImage?
    }

    private struct RecentImage {
        let key: Key
        let image: CGImage
        let cost: Int
    }

    private let lock = NSLock()
    private var recent: [RecentImage] = []
    private var retainedBytes = 0
    private var settings: DeviceGraphicsContextSettings?
    private var entries: [Key: Entry] = [:]
    private var order: [Key?] = Array(repeating: nil, count: 32)
    private var next = 0

    func image(background: CGColor, foreground: CGColor, colorSpace: CGColorSpace, size: CGSize, horizontal: Bool, generate: () -> CGImage?) -> CGImage? {
        let settings = DeviceGraphicsContextSettings.shared
        let key = Key(background: background, foreground: foreground, colorSpace: colorSpace, width: size.width, height: size.height, horizontal: horizontal)
        lock.lock()
        if self.settings != settings {
            self.settings = settings
            entries.removeAll(keepingCapacity: true)
            recent.removeAll(keepingCapacity: true)
            retainedBytes = 0
            order = Array(repeating: nil, count: 32)
            next = 0
        }
        if let image = existingImage(for: key) {
            lock.unlock()
            return image
        }
        lock.unlock()
        guard let image = generate() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard self.settings == settings, DeviceGraphicsContextSettings.shared == settings else { return image }
        if let current = existingImage(for: key) { return current }
        if entries[key] == nil {
            if let previous = order[next] { entries.removeValue(forKey: previous) }
            order[next] = key
            next = (next + 1) % order.count
        }
        entries[key] = Entry(image: image)
        retainRecent(image, for: key)
        return image
    }

    private func existingImage(for key: Key) -> CGImage? {
        if let index = recent.lastIndex(where: { $0.key == key }) {
            let entry = recent[index]
            if index != recent.count - 1 {
                recent.remove(at: index)
                recent.append(entry)
            }
            return entry.image
        }
        if let image = entries[key]?.image {
            retainRecent(image, for: key)
            return image
        }
        return nil
    }

    private func retainRecent(_ image: CGImage, for key: Key) {
        let budget = 64 * 1024
        guard image.bytesPerRow > 0, image.height <= budget / image.bytesPerRow else { return }
        let cost = image.bytesPerRow * image.height
        while !recent.isEmpty && (recent.count >= 3 || retainedBytes + cost > budget) {
            retainedBytes -= recent.removeFirst().cost
        }
        recent.append(RecentImage(key: key, image: image, cost: cost))
        retainedBytes += cost
    }
}

func shimmerGradientImage(backgroundColor: NSColor, foregroundColor: NSColor, size: CGSize, horizontal: Bool, gradientColorSpace: CGColorSpace) -> CGImage? {
    let background = backgroundColor.cgColor
    let foreground = foregroundColor.cgColor
    return ShimmerGradientCache.shared.image(background: background, foreground: foreground, colorSpace: gradientColorSpace, size: size, horizontal: horizontal) {
        generateImage(size, opaque: false, scale: 1.0, rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(background)
            context.fill(CGRect(origin: CGPoint(), size: size))
            context.clip(to: CGRect(origin: CGPoint(), size: size))
            let transparentColor = foregroundColor.withAlphaComponent(0.0).cgColor
            var locations: [CGFloat] = [0.0, 0.5, 1.0]
            let colors: [CGColor] = [transparentColor, foreground, transparentColor]
            let gradient = CGGradient(colorsSpace: gradientColorSpace, colors: colors as CFArray, locations: &locations)!
            context.drawLinearGradient(gradient, start: CGPoint(), end: horizontal ? CGPoint(x: size.width, y: 0.0) : CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())
        })
    }
}

private final class ShimmerEffectForegroundLayer: SimpleLayer {
    private var currentBackgroundColor: NSColor?
    private var currentForegroundColor: NSColor?
    private let imageViewContainer: SimpleLayer
    private let imageView: SimpleLayer
    
    private var absoluteLocation: (CGRect, CGSize)?
    private var shouldBeAnimating = false
    
    fileprivate var isStatic: Bool = false
    
    override init() {
        self.imageViewContainer = SimpleLayer()
        self.imageView = SimpleLayer()
        super.init()
        self.imageViewContainer.addSublayer(self.imageView)
        self.addSublayer(self.imageViewContainer)
        
        self.didExitHierarchy = { [weak self] in
            self?.updateAnimation()
        }
        
        self.didEnterHierarchy = { [weak self] in
            self?.updateAnimation()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(backgroundColor: NSColor, foregroundColor: NSColor) {
        let backgroundColor = resolvedShimmerColor(backgroundColor)
        let foregroundColor = resolvedShimmerColor(foregroundColor)
        if let currentBackgroundColor = self.currentBackgroundColor, currentBackgroundColor.isEqual(backgroundColor), let currentForegroundColor = self.currentForegroundColor, currentForegroundColor.isEqual(foregroundColor) {
            return
        }
        self.currentBackgroundColor = backgroundColor
        self.currentForegroundColor = foregroundColor
        let image = shimmerGradientImage(backgroundColor: backgroundColor, foregroundColor: foregroundColor, size: CGSize(width: 320.0, height: 16.0), horizontal: true, gradientColorSpace: DeviceGraphicsContextSettings.shared.colorSpace)

        self.imageView.contents = image
    }
    
    func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        if let absoluteLocation = self.absoluteLocation, absoluteLocation.0 == rect && absoluteLocation.1 == containerSize {
            return
        }
        let sizeUpdated = self.absoluteLocation?.1 != containerSize
        let frameUpdated = self.absoluteLocation?.0 != rect
        self.absoluteLocation = (rect, containerSize)
        
        if sizeUpdated {
            if self.shouldBeAnimating {
                self.imageView.removeAnimation(forKey: "shimmer")
                self.addImageAnimation()
            } else {
                self.updateAnimation()
            }
        }
        
        if frameUpdated {
            self.imageViewContainer.frame = CGRect(origin: CGPoint(x: -rect.minX, y: -rect.minY), size: containerSize)
        }
    }
    
    func reloadAnimation() {
        self.imageView.removeAnimation(forKey: "shimmer")
        self.addImageAnimation()
    }
    
    private func updateAnimation() {
        let shouldBeAnimating = self.absoluteLocation != nil
        if shouldBeAnimating != self.shouldBeAnimating {
            self.shouldBeAnimating = shouldBeAnimating
            if shouldBeAnimating {
                self.addImageAnimation()
            } else {
                self.imageView.removeAnimation(forKey: "shimmer")
            }
        }
    }
    
    private func addImageAnimation() {
        guard let containerSize = self.absoluteLocation?.1 else {
            return
        }
        let duration: Double = isStatic ? 0.7 : 1.5 * 1.0
        
        let gradientHeight: CGFloat = 320.0
        self.imageView.frame = CGRect(origin: CGPoint(x: -gradientHeight, y: 0.0), size: CGSize(width: gradientHeight, height: containerSize.height))
        let animation = self.imageView.makeAnimation(from: 0.0 as NSNumber, to: (containerSize.width + gradientHeight) as NSNumber, keyPath: "position.x", timingFunction: .easeOut, duration: duration, delay: 0.0, mediaTimingFunction: nil, removeOnCompletion: true, additive: true)
        
        if !isStatic {
            animation.repeatCount = Float.infinity
            animation.beginTime = 1.0
        }
        
        if isStatic {
            animation.delegate = CALayerAnimationDelegate(completion: { [weak self] completed in
                if completed {
                    delay(2 - duration, closure: {
                        self?.addImageAnimation()
                    })
                }
            })
        }
        self.imageView.add(animation, forKey: "shimmer")

    }
}


func resolvedShimmerColor(_ color: NSColor) -> NSColor {
    if color.type == .componentBased {
        return color
    }
    return NSColor(cgColor: color.cgColor) ?? color
}

public class ShimmerLayer: SimpleLayer {
    private let backgroundView: SimpleLayer
    private let effectView: ShimmerEffectForegroundLayer
    private let foregroundView: SimpleLayer
    
    private var maskView: SimpleLayer?
    
    private var currentData: Data?
    private var currentBackgroundColor: NSColor?
    private var currentForegroundColor: NSColor?
    private var currentShimmeringColor: NSColor?
    private var currentSize = CGSize()
    private var currentScale: CGFloat = 0
    private var currentImageSize = CGSize()
    private var currentCornerRadius: CGFloat?
    private var imageDisposable: Disposable?
    
    public var isStatic: Bool = false {
        didSet {
            effectView.isStatic = isStatic
        }
    }
    
    public override init() {
        self.backgroundView = SimpleLayer()
        self.effectView = ShimmerEffectForegroundLayer()
        self.foregroundView = SimpleLayer()
        
        super.init()
        
        self.addSublayer(self.backgroundView)
        self.addSublayer(self.effectView)
        self.addSublayer(self.foregroundView)
        
        
    }
    
    deinit {
        imageDisposable?.dispose()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required override init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        self.effectView.updateAbsoluteRect(rect, within: containerSize)
    }
    
    public func update(backgroundColor: NSColor?, foregroundColor: NSColor = NSColor(rgb: 0x748391, alpha: 0.2), shimmeringColor: NSColor = NSColor(rgb: 0x748391, alpha: 0.35), data: Data?, size: CGSize, imageSize: NSSize, cornerRadius: CGFloat? = nil) {
        let scale = System.backingScale
        let backgroundKey = backgroundColor.map(resolvedShimmerColor)
        let foregroundKey = resolvedShimmerColor(foregroundColor)
        let shimmeringKey = resolvedShimmerColor(shimmeringColor)
        if self.currentData == data, self.currentBackgroundColor == backgroundKey, self.currentForegroundColor == foregroundKey, self.currentShimmeringColor == shimmeringKey, self.currentSize == size, self.currentScale == scale, self.currentImageSize == imageSize, self.currentCornerRadius == cornerRadius {
            return
        }
        
        self.currentBackgroundColor = backgroundKey
        self.currentForegroundColor = foregroundKey
        self.currentShimmeringColor = shimmeringKey
        self.currentData = data
        self.currentSize = size
        self.currentScale = scale
        self.currentImageSize = imageSize
        self.currentCornerRadius = cornerRadius
        self.imageDisposable?.dispose()
        self.imageDisposable = nil
        
        self.backgroundView.backgroundColor = foregroundKey.cgColor
        
        self.effectView.update(backgroundColor: backgroundColor == nil ? .clear : foregroundColor, foregroundColor: shimmeringColor)
        
        
        let signal: Signal<CGImage?, NoError> = Signal { subscriber in
            let cancelled = Atomic(value: false)
            Queue.concurrentDefaultQueue().async {
                guard !cancelled.with({ $0 }) else { return }
            
                let image = generateImage(size, scale: scale, rotatedContext: { size, context in
                    if let backgroundColor = backgroundKey?.cgColor {
                        context.setFillColor(backgroundColor)
                        context.setBlendMode(.copy)
                        context.fill(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(NSColor.clear.cgColor)
                    } else {
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(NSColor.black.cgColor)
                    }

                    if let data = data {
                        var path = decodeStickerThumbnailData(data)
                        if !path.hasPrefix("z") {
                            path = "\(path)z"
                        }
                        let reader = PathDataReader(input: path)
                        let segments = reader.read()

                        let scale = max(size.width, size.height) / max(imageSize.width, imageSize.height)
                        context.scaleBy(x: scale, y: scale)
                        renderPath(segments, context: context)
                    } else {
                        let path = CGMutablePath()
                        if let cornerRadius = cornerRadius {
                            path.addRoundedRect(in: CGRect(origin: CGPoint(), size: size), cornerWidth: cornerRadius, cornerHeight: cornerRadius)
                        } else {
                            path.addRoundedRect(in: CGRect(origin: CGPoint(), size: size), cornerWidth: min(min(4, size.height / 2), size.width / 2), cornerHeight: min(min(size.height / 2, 4), size.height / 2))
                        }
                        context.addPath(path)
                        context.fillPath()
                    }
                })
            
                subscriber.putNext(image)
                subscriber.putCompletion()
            }
            return ActionDisposable { _ = cancelled.swap(true) }
        }
        |> deliverOnMainQueue
        
                
        if backgroundColor == nil {
            self.foregroundView.contents = nil
            
            let maskView: SimpleLayer
            if let current = self.maskView {
                maskView = current
            } else {
                maskView = SimpleLayer()
                maskView.frame = CGRect(origin: CGPoint(), size: size)
                self.maskView = maskView
                self.mask = maskView
            }
        } else {
            if let _ = self.maskView {
                self.mask = nil
                self.maskView = nil
            }
        }
        
        
        self.maskView?.frame = CGRect(origin: CGPoint(), size: size)
        let imageLayer = backgroundColor == nil ? self.maskView : self.foregroundView
        self.imageDisposable = signal.start(next: { [weak imageLayer] image in
            imageLayer?.contents = image
        })

        self.backgroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.foregroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.effectView.frame = CGRect(origin: CGPoint(), size: size)
    }
}


public final class SilhouetteShimmerLayer: SimpleLayer {
    public static let maxWidth: CGFloat = 48

    private let contentLayer = SimpleLayer()
    private let imageDisposable = MetaDisposable()

    private var currentData: Data?
    private var currentForegroundColor: NSColor?
    private var currentShimmeringColor: NSColor?
    private var currentSize = CGSize()
    private var currentScale: CGFloat = 0
    private var currentImageSize = CGSize()

    public override init() {
        super.init()
        self.addSublayer(self.contentLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required override init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    deinit {
        self.imageDisposable.dispose()
    }

    public func update(foregroundColor: NSColor, shimmeringColor: NSColor, data: Data?, size: CGSize, imageSize: NSSize) {
        let scale = System.backingScale
        let foregroundKey = resolvedShimmerColor(foregroundColor)
        let shimmeringKey = resolvedShimmerColor(shimmeringColor)
        if self.currentData == data, self.currentForegroundColor == foregroundKey, self.currentShimmeringColor == shimmeringKey, self.currentSize == size, self.currentScale == scale, self.currentImageSize == imageSize {
            return
        }
        let sizeUpdated = self.currentSize != size
        let alphaUpdated = self.currentForegroundColor?.alphaComponent != foregroundKey.alphaComponent || self.currentShimmeringColor?.alphaComponent != shimmeringKey.alphaComponent
        self.currentData = data
        self.currentForegroundColor = foregroundKey
        self.currentShimmeringColor = shimmeringKey
        self.currentSize = size
        self.currentScale = scale
        self.currentImageSize = imageSize

        self.contentLayer.frame = CGRect(origin: CGPoint(), size: size)

        let baseAlpha = foregroundKey.alphaComponent
        let peakAlpha = baseAlpha + shimmeringKey.alphaComponent * (1.0 - baseAlpha)
        self.contentLayer.opacity = Float(baseAlpha)
        if sizeUpdated || alphaUpdated || self.contentLayer.animation(forKey: "shimmer") == nil {
            self.contentLayer.removeAnimation(forKey: "shimmer")
            self.contentLayer.add(SilhouetteShimmerLayer.makeAnimation(width: size.width, baseAlpha: baseAlpha, peakAlpha: peakAlpha), forKey: "shimmer")
        }

        let color = foregroundKey.withAlphaComponent(1.0)
        let signal: Signal<CGImage?, NoError> = Signal { subscriber in
            let cancelled = Atomic(value: false)
            Queue.concurrentDefaultQueue().async {
                guard !cancelled.with({ $0 }) else { return }
                let image: CGImage?
                if let data = data {
                    image = generateStickerPlaceholderImage(data: data, size: size, scale: scale, imageSize: imageSize, backgroundColor: nil, foregroundColor: color)
                } else {
                    image = generateImage(size, scale: scale, rotatedContext: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(color.cgColor)
                        let path = CGMutablePath()
                        path.addRoundedRect(in: CGRect(origin: CGPoint(), size: size), cornerWidth: min(min(4, size.height / 2), size.width / 2), cornerHeight: min(min(size.height / 2, 4), size.height / 2))
                        context.addPath(path)
                        context.fillPath()
                    })
                }
                subscriber.putNext(image)
                subscriber.putCompletion()
            }
            return ActionDisposable { _ = cancelled.swap(true) }
        }
        |> deliverOnMainQueue

        self.imageDisposable.set(signal.start(next: { [weak self] image in
            self?.contentLayer.contents = image
        }))
    }

    private static func makeAnimation(width: CGFloat, baseAlpha: CGFloat, peakAlpha: CGFloat) -> CAAnimation {
        let gradientWidth: CGFloat = 320.0
        let travel = width + gradientWidth
        let center = width / 2.0
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [baseAlpha, baseAlpha, peakAlpha, baseAlpha, baseAlpha].map { NSNumber(value: Float($0)) }
        animation.keyTimes = [0.0, center / travel, (center + gradientWidth / 2.0) / travel, (center + gradientWidth) / travel, 1.0].map { NSNumber(value: Float($0)) }
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.duration = 1.5
        animation.repeatCount = Float.infinity
        animation.beginTime = 1.0
        let k = Float(NSView.animationDurationFactor())
        if k != 0 && k != 1 {
            animation.speed = 1.0 / k
        }
        return animation
    }
}


public class ShimmerView: View {
    private let backgroundView: SimpleLayer
    private let effectView: ShimmerEffectForegroundLayer
    private let foregroundView: SimpleLayer
    
    private var maskView: SimpleLayer?
    
    private var currentData: Data?
    private var currentBackgroundColor: NSColor?
    private var currentForegroundColor: NSColor?
    private var currentShimmeringColor: NSColor?
    private var currentSize = CGSize()
    private var currentScale: CGFloat = 0
    private var currentImageSize = CGSize()
    private var currentCornerRadius: CGFloat?
    private var imageDisposable: Disposable?
    
    public override init() {
        self.backgroundView = SimpleLayer()
        self.effectView = ShimmerEffectForegroundLayer()
        self.foregroundView = SimpleLayer()
        
        super.init()
        
        self.layer?.addSublayer(self.backgroundView)
        self.layer?.addSublayer(self.effectView)
        self.layer?.addSublayer(self.foregroundView)
        
        
    }
    
    deinit {
        imageDisposable?.dispose()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        self.effectView.updateAbsoluteRect(rect, within: containerSize)
    }
    
    public func reloadAnimation() {
        self.effectView.reloadAnimation()
    }
    
    public func update(backgroundColor: NSColor?, foregroundColor: NSColor = NSColor(rgb: 0x748391, alpha: 0.2), shimmeringColor: NSColor = NSColor(rgb: 0x748391, alpha: 0.35), data: Data?, size: CGSize, imageSize: NSSize, cornerRadius: CGFloat? = nil) {
        let scale = System.backingScale
        let backgroundKey = backgroundColor.map(resolvedShimmerColor)
        let foregroundKey = resolvedShimmerColor(foregroundColor)
        let shimmeringKey = resolvedShimmerColor(shimmeringColor)
        if self.currentData == data, self.currentBackgroundColor == backgroundKey, self.currentForegroundColor == foregroundKey, self.currentShimmeringColor == shimmeringKey, self.currentSize == size, self.currentScale == scale, self.currentImageSize == imageSize, self.currentCornerRadius == cornerRadius {
            return
        }
        
        self.currentBackgroundColor = backgroundKey
        self.currentForegroundColor = foregroundKey
        self.currentShimmeringColor = shimmeringKey
        self.currentData = data
        self.currentSize = size
        self.currentScale = scale
        self.currentImageSize = imageSize
        self.currentCornerRadius = cornerRadius
        self.imageDisposable?.dispose()
        self.imageDisposable = nil
        
        self.backgroundView.backgroundColor = foregroundKey.cgColor
        
        self.effectView.update(backgroundColor: backgroundColor == nil ? .clear : foregroundColor, foregroundColor: shimmeringColor)
        
        
        let signal: Signal<CGImage?, NoError> = Signal { subscriber in
            let cancelled = Atomic(value: false)
            Queue.concurrentDefaultQueue().async {
                guard !cancelled.with({ $0 }) else { return }
            
                let image = generateImage(size, scale: scale, rotatedContext: { size, context in
                    if let backgroundColor = backgroundKey?.cgColor {
                        context.setFillColor(backgroundColor)
                        context.setBlendMode(.copy)
                        context.fill(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(NSColor.clear.cgColor)
                    } else {
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(NSColor.black.cgColor)
                    }

                    if let data = data {
                        var path = decodeStickerThumbnailData(data)
                        if !path.hasPrefix("z") {
                            path = "\(path)z"
                        }
                        let reader = PathDataReader(input: path)
                        let segments = reader.read()

                        let scale = max(size.width, size.height) / max(imageSize.width, imageSize.height)
                        context.scaleBy(x: scale, y: scale)
                        renderPath(segments, context: context)
                    } else {
                        let path = CGMutablePath()
                        if let cornerRadius = cornerRadius {
                            path.addRoundedRect(in: CGRect(origin: CGPoint(), size: size), cornerWidth: cornerRadius, cornerHeight: cornerRadius)
                        } else {
                            path.addRoundedRect(in: CGRect(origin: CGPoint(), size: size), cornerWidth: min(min(4, size.height / 2), size.width / 2), cornerHeight: min(min(size.height / 2, 4), size.height / 2))
                        }
                        context.addPath(path)
                        context.fillPath()
                    }
                })
            
                subscriber.putNext(image)
                subscriber.putCompletion()
            }
            return ActionDisposable { _ = cancelled.swap(true) }
        }
        |> deliverOnMainQueue
        
                
        if backgroundColor == nil {
            self.foregroundView.contents = nil
            
            let maskView: SimpleLayer
            if let current = self.maskView {
                maskView = current
            } else {
                maskView = SimpleLayer()
                maskView.frame = CGRect(origin: CGPoint(), size: size)
                self.maskView = maskView
                self.layer?.mask = maskView
            }
        } else {
            if let _ = self.maskView {
                self.layer?.mask = nil
                self.maskView = nil
            }
        }
        
        
        self.maskView?.frame = CGRect(origin: CGPoint(), size: size)
        let imageLayer = backgroundColor == nil ? self.maskView : self.foregroundView
        self.imageDisposable = signal.start(next: { [weak imageLayer] image in
            imageLayer?.contents = image
        })

        self.backgroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.foregroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.effectView.frame = CGRect(origin: CGPoint(), size: size)
    }
}

open class PathSegment: Equatable {
    public enum SegmentType {
        case M
        case L
        case C
        case Q
        case A
        case z
        case H
        case V
        case S
        case T
        case m
        case l
        case c
        case q
        case a
        case h
        case v
        case s
        case t
        case E
        case e
    }
    
    public let type: SegmentType
    public let data: [Double]

    public init(type: PathSegment.SegmentType = .M, data: [Double] = []) {
        self.type = type
        self.data = data
    }

    open func isAbsolute() -> Bool {
        switch type {
        case .M, .L, .H, .V, .C, .S, .Q, .T, .A, .E:
            return true
        default:
            return false
        }
    }

    public static func == (lhs: PathSegment, rhs: PathSegment) -> Bool {
        return lhs.type == rhs.type && lhs.data == rhs.data
    }
}

func renderPath(_ segments: [PathSegment], context: CGContext) {
    var currentPoint: CGPoint?
    var cubicPoint: CGPoint?
    
    func M(_ x: Double, y: Double) {
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        context.move(to: point)
        setInitPoint(point)
    }
    
    func m(_ x: Double, y: Double) {
        if let cur = currentPoint {
            let next = CGPoint(x: CGFloat(x) + cur.x, y: CGFloat(y) + cur.y)
            context.move(to: next)
            setInitPoint(next)
        } else {
            M(x, y: y)
        }
    }
    
    func L(_ x: Double, y: Double) {
        lineTo(CGPoint(x: CGFloat(x), y: CGFloat(y)))
    }
    
    func l(_ x: Double, y: Double) {
        if let cur = currentPoint {
            lineTo(CGPoint(x: CGFloat(x) + cur.x, y: CGFloat(y) + cur.y))
        } else {
            L(x, y: y)
        }
    }
    
    func H(_ x: Double) {
        if let cur = currentPoint {
            lineTo(CGPoint(x: CGFloat(x), y: CGFloat(cur.y)))
        }
    }
    
    func h(_ x: Double) {
        if let cur = currentPoint {
            lineTo(CGPoint(x: CGFloat(x) + cur.x, y: CGFloat(cur.y)))
        }
    }
    
    func V(_ y: Double) {
        if let cur = currentPoint {
            lineTo(CGPoint(x: CGFloat(cur.x), y: CGFloat(y)))
        }
    }
    
    func v(_ y: Double) {
        if let cur = currentPoint {
            lineTo(CGPoint(x: CGFloat(cur.x), y: CGFloat(y) + cur.y))
        }
    }

    func lineTo(_ p: CGPoint) {
        context.addLine(to: p)
        setPoint(p)
    }
    
    func c(_ x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double) {
        if let cur = currentPoint {
            let endPoint = CGPoint(x: CGFloat(x) + cur.x, y: CGFloat(y) + cur.y)
            let controlPoint1 = CGPoint(x: CGFloat(x1) + cur.x, y: CGFloat(y1) + cur.y)
            let controlPoint2 = CGPoint(x: CGFloat(x2) + cur.x, y: CGFloat(y2) + cur.y)
            context.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
            setCubicPoint(endPoint, cubic: controlPoint2)
        }
    }
    
    func C(_ x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double) {
        let endPoint = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let controlPoint1 = CGPoint(x: CGFloat(x1), y: CGFloat(y1))
        let controlPoint2 = CGPoint(x: CGFloat(x2), y: CGFloat(y2))
        context.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
        setCubicPoint(endPoint, cubic: controlPoint2)
    }
    
    func s(_ x2: Double, y2: Double, x: Double, y: Double) {
        if let cur = currentPoint {
            let nextCubic = CGPoint(x: CGFloat(x2) + cur.x, y: CGFloat(y2) + cur.y)
            let next = CGPoint(x: CGFloat(x) + cur.x, y: CGFloat(y) + cur.y)
            
            let xy1: CGPoint
            if let curCubicVal = cubicPoint {
                xy1 = CGPoint(x: CGFloat(2 * cur.x) - curCubicVal.x, y: CGFloat(2 * cur.y) - curCubicVal.y)
            } else {
                xy1 = cur
            }
            context.addCurve(to: next, control1: xy1, control2: nextCubic)
            setCubicPoint(next, cubic: nextCubic)
        }
    }
    
    func S(_ x2: Double, y2: Double, x: Double, y: Double) {
        if let cur = currentPoint {
            let nextCubic = CGPoint(x: CGFloat(x2), y: CGFloat(y2))
            let next = CGPoint(x: CGFloat(x), y: CGFloat(y))
            let xy1: CGPoint
            if let curCubicVal = cubicPoint {
                xy1 = CGPoint(x: CGFloat(2 * cur.x) - curCubicVal.x, y: CGFloat(2 * cur.y) - curCubicVal.y)
            } else {
                xy1 = cur
            }
            context.addCurve(to: next, control1: xy1, control2: nextCubic)
            setCubicPoint(next, cubic: nextCubic)
        }
    }
    
    func z() {
        context.fillPath()
    }
    
    func setQuadrPoint(_ p: CGPoint, quadr: CGPoint) {
        currentPoint = p
        cubicPoint = nil
    }

    func setCubicPoint(_ p: CGPoint, cubic: CGPoint) {
        currentPoint = p
        cubicPoint = cubic
    }

    func setInitPoint(_ p: CGPoint) {
        setPoint(p)
    }

    func setPoint(_ p: CGPoint) {
        currentPoint = p
        cubicPoint = nil
    }
    
    for segment in segments {
        let data = segment.data
        switch segment.type {
            case .M:
                M(data[0], y: data[1])
                var index = 2
                while index + 1 < data.count {
                    L(data[index], y: data[index + 1])
                    index += 2
                }
            case .m:
                m(data[0], y: data[1])
                var index = 2
                while index + 1 < data.count {
                    l(data[index], y: data[index + 1])
                    index += 2
                }
            case .L:
                var index = 0
                while index + 1 < data.count {
                    L(data[index], y: data[index + 1])
                    index += 2
                }
            case .l:
                var index = 0
                while index + 1 < data.count {
                    l(data[index], y: data[index + 1])
                    index += 2
                }
            case .H:
                H(data[0])
            case .h:
                h(data[0])
            case .V:
                V(data[0])
            case .v:
                v(data[0])
            case .C:
                var index = 0
                while index + 5 < data.count {
                    C(data[index], y1: data[index + 1], x2: data[index + 2], y2: data[index + 3], x: data[index + 4], y: data[index + 5])
                    index += 6
                }
            case .c:
                var index = 0
                while index + 5 < data.count {
                    c(data[index], y1: data[index + 1], x2: data[index + 2], y2: data[index + 3], x: data[index + 4], y: data[index + 5])
                    index += 6
                }
            case .S:
                var index = 0
                while index + 3 < data.count {
                    S(data[index], y2: data[index + 1], x: data[index + 2], y: data[index + 3])
                    index += 4
                }
            case .s:
                var index = 0
                while index + 3 < data.count {
                    s(data[index], y2: data[index + 1], x: data[index + 2], y: data[index + 3])
                    index += 4
                }
            case .z:
                z()
            default:
                print("unknown")
                break
        }
    }
}
