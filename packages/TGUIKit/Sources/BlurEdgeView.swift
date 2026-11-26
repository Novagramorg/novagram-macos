import Cocoa

private final class BlurEdgeMaskCache {
    static let shared = BlurEdgeMaskCache()

    private struct Entry {
        let size: CGSize
        let padding: CGFloat
        let bottom: Bool
        weak var image: CIImage?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var replacementIndex = 0

    func image(size: CGSize, padding: CGFloat, bottom: Bool, generate: () -> CIImage?) -> CIImage? {
        lock.lock()
        if let image = entries.first(where: { $0.size == size && $0.padding == padding && $0.bottom == bottom })?.image {
            lock.unlock()
            return image
        }
        lock.unlock()
        guard let generated = generate() else { return nil }
        lock.lock()
        if let image = entries.first(where: { $0.size == size && $0.padding == padding && $0.bottom == bottom })?.image {
            lock.unlock()
            return image
        }
        let entry = Entry(size: size, padding: padding, bottom: bottom, image: generated)
        if let vacant = entries.firstIndex(where: { $0.image == nil }) {
            entries[vacant] = entry
        } else if entries.count < 16 {
            entries.append(entry)
        } else {
            entries[replacementIndex] = entry
            replacementIndex = (replacementIndex + 1) % 16
        }
        lock.unlock()
        return generated
    }
}

public final class BlurEdgeView: NSView {

    public enum Edge {
        case top
        case bottom
    }

    public var blurRadius: CGFloat = 8
    public var padding: CGFloat = 0

    public var bgColor: NSColor = .clear {
        didSet {
            applyTintGradient()
        }
    }


    public override var isFlipped: Bool {
        return true
    }
    public var isEventLess: Bool = false

    private let tintLayer = CAGradientLayer()
    private var currentEdge: Edge = .bottom

    public init() {
        super.init(frame: .zero)
        prepare()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        prepare()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func prepare() {
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        tintLayer.type = .axial
        tintLayer.actions = ["colors": NSNull(), "locations": NSNull(), "startPoint": NSNull(), "endPoint": NSNull(), "frame": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.addSublayer(tintLayer)

        applyTintGradient()
        applyVariableBlur()
    }

    private func applyTintGradient() {
        let solid = bgColor.cgColor
        let clear = bgColor.withAlphaComponent(0).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch currentEdge {
        case .bottom:
            // Max blur at top → solid tint at top, fading to clear at bottom.
            tintLayer.colors = [solid, clear]
        case .top:
            // Max blur at bottom → solid tint at bottom, fading to clear at top.
            tintLayer.colors = [clear, solid]
        }
        tintLayer.locations = [0.0, 1.0]
        tintLayer.startPoint = CGPoint(x: 0.5, y: 0)
        tintLayer.endPoint = CGPoint(x: 0.5, y: 1)
        CATransaction.commit()
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        if isEventLess { return nil }
        return super.hitTest(point)
    }

    public func change(opacity to: CGFloat, animated: Bool = true, _ save: Bool = true, removeOnCompletion: Bool = true, duration: Double = 0.2, timingFunction: CAMediaTimingFunctionName = .easeOut, completion: ((Bool) -> Void)? = nil) {
        self._change(opacity: to, animated: animated, save, removeOnCompletion: removeOnCompletion, duration: duration, timingFunction: timingFunction, completion: completion)
    }

    public func update(edge: Edge, edgeSize: CGFloat, rect: NSRect, transition: ContainedViewLayoutTransition, horizontalFade: CGFloat = 0, intensity: CGFloat = 1.0) {
        currentEdge = edge
        let bounds = NSRect(origin: .zero, size: rect.size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        CATransaction.commit()

        let _ = edgeSize
        let _ = horizontalFade
        let _ = intensity

        applyTintGradient()
        applyVariableBlur()
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        CATransaction.commit()
        applyVariableBlur()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyVariableBlur()
    }

    // MARK: - Progressive blur

    private func verticalGradient(size: CGSize) -> CIImage? {
        let padding = self.padding
        let bottom = currentEdge == .bottom
        return BlurEdgeMaskCache.shared.image(size: size, padding: padding, bottom: bottom) {
            guard let ctx = CGContext(
                data: nil,
                width: Int(round(size.width)),
                height: Int(round(size.height)),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }

            let colors: [NSColor]
            switch bottom {
            case true:
                colors = [.white, .black]
            case false:
                colors = [.black, .white]
            }
            let cgcolors = colors.map { $0.cgColor } as CFArray

            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceGray(),
                colors: cgcolors,
                locations: [0.0, 1.0]
            ) else { return nil }

            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: -padding),
                end: CGPoint(x: 0, y: size.height + padding),
                options: []
            )

            guard let image = ctx.makeImage() else { return nil }
            return CIImage(cgImage: image)
        }
    }

    private func applyVariableBlur() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let filter = CIFilter(name: "CIMaskedVariableBlur") else { return }
        let maskImage = verticalGradient(size: bounds.size)
        filter.setDefaults()
        filter.setValue(maskImage, forKey: "inputMask")
        filter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        layer?.backgroundFilters = [filter]
    }
}
