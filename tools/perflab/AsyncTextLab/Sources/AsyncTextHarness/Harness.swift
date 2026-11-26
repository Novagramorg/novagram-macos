import Cocoa
import TGUIKit

public enum AsyncTextFixtures {
    public static var alignFrames = false
    public static var extraHeight: CGFloat = 0
    public static var forcedColor: NSColor?
    public static func advance(_ y: inout CGFloat, by height: CGFloat) {
        y += height + 4
        if alignFrames { y = ceil(y) }
    }
    public static let paragraphs: [String] = [
        "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. How vexingly quick daft zebras jump!",
        "Съешь же ещё этих мягких французских булок, да выпей чаю. В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!",
        "مرحبا بالعالم، هذا نص تجريبي لاختبار الاتجاه من اليمين إلى اليسار مع English words mixed in.",
        "中文 日本語 한글 café ffi fl — numbers 1234567890, punctuation: ¡¿«»‹›…",
        "👩🏽‍💻 👨‍👩‍👧‍👦 🦆 🇦🇪 emoji and text with a link https://telegram.org inside",
    ]

    public static func layout(_ index: Int, width: CGFloat, paragraphs count: Int) -> TextViewLayout {
        let text = NSMutableAttributedString()
        for i in 0..<count {
            let p = paragraphs[(index + i) % paragraphs.count]
            let font: NSFont = i % 3 == 1 ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
            let color: NSColor = forcedColor ?? (i % 4 == 2 ? NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1) : NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1))
            text.append(NSAttributedString(string: p + (i + 1 < count ? "\n" : ""), attributes: [.font: font, .foregroundColor: color]))
        }
        let layout = TextViewLayout(text, alignment: .left)
        layout.measure(width: width)
        return layout
    }
}

public final class AsyncTextWindow {
    public let window: NSWindow
    public let host: View
    public init(size: NSSize, colorSpace: NSColorSpace?) {
        window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let colorSpace { window.colorSpace = colorSpace }
        host = View(frame: NSRect(origin: .zero, size: size))
        host.backgroundColor = .white
        window.contentView = host
        window.orderFrontRegardless()
    }

    public func capture() -> CGImage? {
        CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])
    }

    public func close() {
        window.orderOut(nil)
        window.close()
    }
}

public func rgba(_ image: CGImage) -> [UInt8] {
    let width = image.width, height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return data
}

public func spinRunLoop(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.current.run(mode: .default, before: min(end, Date().addingTimeInterval(0.002)))
    }
}

public final class AsyncTextScene {
    public let layers: [TextViewLayer]
    public init(in host: NSView, count: Int, width: CGFloat, paragraphs: Int, async: Bool, scale: CGFloat) {
        var y: CGFloat = 4
        var layers: [TextViewLayer] = []
        for i in 0..<count {
            let layout = AsyncTextFixtures.layout(i, width: width, paragraphs: paragraphs)
            let layer = TextViewLayer()
            layer.drawsAsynchronously = async
            layer.contentsScale = scale
            layer.update(layout)
            layer.frame = CGRect(x: 6, y: y, width: layout.layoutSize.width, height: layout.layoutSize.height + AsyncTextFixtures.extraHeight)
            AsyncTextFixtures.advance(&y, by: layer.frame.height)
            host.layer?.addSublayer(layer)
            layers.append(layer)
        }
        self.layers = layers
    }
    public func remove() {
        layers.forEach { $0.removeFromSuperlayer() }
    }
}

public enum ManualTextRaster {
    public static var prepare: ((CGContext) -> Void)?
    public struct Job {
        public let layout: TextViewLayout
        public let bounds: CGSize
        public let scale: CGFloat
        public let flipped: Bool
        public let colorSpace: CGColorSpace
        public var format: Format = .bgra8
        public init(layout: TextViewLayout, bounds: CGSize, scale: CGFloat, flipped: Bool, colorSpace: CGColorSpace, format: Format = .bgra8) {
            self.layout = layout; self.bounds = bounds; self.scale = scale; self.flipped = flipped; self.colorSpace = colorSpace; self.format = format
        }
    }

    public enum Format: String, CaseIterable {
        case bgra8, rgba16f, rgba16
    }

    public static func render(_ job: Job) -> CGImage? {
        let width = Int(ceil(job.bounds.width * job.scale)), height = Int(ceil(job.bounds.height * job.scale))
        guard width > 0, height > 0 else { return nil }
        let bpc: Int, info: UInt32
        switch job.format {
        case .bgra8:
            bpc = 8; info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        case .rgba16f:
            bpc = 16; info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue | CGBitmapInfo.floatComponents.rawValue
        case .rgba16:
            bpc = 16; info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        }
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: bpc, bytesPerRow: 0, space: job.colorSpace, bitmapInfo: info) else { return nil }
        if job.flipped {
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.scaleBy(x: job.scale, y: job.scale)
        prepare?(ctx)
        let drawer = TextViewLayer()
        drawer.contentsScale = job.scale
        drawer.update(job.layout)
        drawer.frame = CGRect(origin: .zero, size: job.bounds)
        drawer.draw(in: ctx)
        return ctx.makeImage()
    }
}

public extension ManualTextRaster {
    static func format(for window: NSWindow) -> Format {
        window.canRepresent(.p3) ? .rgba16 : .bgra8
    }
    static func colorSpace(for window: NSWindow) -> CGColorSpace? {
        window.colorSpace?.cgColorSpace
    }
}

public final class ManualTextScene {
    public let layers: [SimpleLayer]
    public init(in host: NSView, count: Int, width: CGFloat, paragraphs: Int, scale: CGFloat, colorSpace: CGColorSpace, flipped: Bool?, queue: DispatchQueue?, format: ManualTextRaster.Format = .bgra8, gravity: CALayerContentsGravity = .resize) {
        var y: CGFloat = 4
        var layers: [SimpleLayer] = []
        var jobs: [(SimpleLayer, Job)] = []
        for i in 0..<count {
            let layout = AsyncTextFixtures.layout(i, width: width, paragraphs: paragraphs)
            let layer = SimpleLayer()
            layer.contentsScale = scale
            layer.contentsGravity = gravity
            layer.frame = CGRect(x: 6, y: y, width: layout.layoutSize.width, height: layout.layoutSize.height + AsyncTextFixtures.extraHeight)
            AsyncTextFixtures.advance(&y, by: layer.frame.height)
            host.layer?.addSublayer(layer)
            layers.append(layer)
            jobs.append((layer, Job(layout: layout, bounds: layer.bounds.size, scale: scale, flipped: flipped ?? layer.contentsAreFlipped(), colorSpace: colorSpace, format: format)))
        }
        self.layers = layers
        if let queue {
            let group = DispatchGroup()
            var images = [CGImage?](repeating: nil, count: jobs.count)
            let lock = NSLock()
            for (index, job) in jobs.enumerated() {
                queue.async(group: group) {
                    let image = ManualTextRaster.render(job.1)
                    lock.lock(); images[index] = image; lock.unlock()
                }
            }
            group.wait()
            for (index, job) in jobs.enumerated() { job.0.contents = images[index] }
        } else {
            for job in jobs { job.0.contents = ManualTextRaster.render(job.1) }
        }
    }
    public func remove() { layers.forEach { $0.removeFromSuperlayer() } }
}

public typealias Job = ManualTextRaster.Job

public final class ContextProbeLayer: CALayer {
    public static var log: [String] = []
    public override func draw(in ctx: CGContext) {
        ContextProbeLayer.log.append("cs=\(ctx.colorSpace.map { String(describing: $0.name ?? ("unnamed" as CFString)) + " model=\($0.model.rawValue)" } ?? "nil") bpc=\(ctx.bitsPerComponent) bpp=\(ctx.bitsPerPixel) info=\(ctx.bitmapInfo.rawValue) alpha=\(ctx.alphaInfo.rawValue) w=\(ctx.width) h=\(ctx.height) ctm=\(ctx.ctm) fmt=\(contentsFormat.rawValue) flipped=\(contentsAreFlipped())")
    }
}

public final class FillProbeLayer: CALayer {
    public static let colors: [CGColor] = [
        CGColor(srgbRed: 13.0 / 255, green: 13.0 / 255, blue: 18.0 / 255, alpha: 1),
        CGColor(srgbRed: 26.0 / 255, green: 102.0 / 255, blue: 230.0 / 255, alpha: 1),
        CGColor(srgbRed: 128.0 / 255, green: 128.0 / 255, blue: 128.0 / 255, alpha: 1),
        CGColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1),
        CGColor(srgbRed: 26.0 / 255, green: 102.0 / 255, blue: 230.0 / 255, alpha: 0.5),
    ]
    public static func draw(in ctx: CGContext) {
        for (i, color) in colors.enumerated() {
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: CGFloat(i) * 20 + 2, y: 2, width: 16, height: 16))
            ctx.fill(CGRect(x: CGFloat(i) * 20 + 2.25, y: 22.25, width: 15.5, height: 15.5))
        }
    }
    public override func draw(in ctx: CGContext) { FillProbeLayer.draw(in: ctx) }
}

import Metal

public final class BackgroundDisplayContext {
    public let renderer: CARenderer?
    public let root = CALayer()
    public init(colorSpace: CGColorSpace?) {
        if let colorSpace, let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            let texture = device.makeTexture(descriptor: descriptor)!
            let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue, kCARendererColorSpace as String: colorSpace])
            renderer.layer = root
            renderer.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
            self.renderer = renderer
        } else {
            renderer = nil
        }
    }
}

public enum BackgroundDisplay {
    public static func render(layout: TextViewLayout, bounds: CGSize, scale: CGFloat, flipped: Bool, format: CALayerContentsFormat?, context: BackgroundDisplayContext? = nil) -> Any? {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let layer = TextViewLayer()
        layer.contentsScale = scale
        if let format { layer.contentsFormat = format }
        layer.isGeometryFlipped = flipped
        layer.update(layout)
        layer.frame = CGRect(origin: .zero, size: bounds)
        context?.root.addSublayer(layer)
        layer.displayIfNeeded()
        CATransaction.commit()
        if let renderer = context?.renderer {
            CATransaction.flush()
            renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
        }
        let contents = layer.contents
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeFromSuperlayer()
        CATransaction.commit()
        return contents
    }
}

public final class BackgroundDisplayScene {
    public let layers: [SimpleLayer]
    public private(set) var contentsTypes: [String] = []
    public init(in host: NSView, count: Int, width: CGFloat, paragraphs: Int, scale: CGFloat, format: CALayerContentsFormat?, queue: DispatchQueue, colorSpace: CGColorSpace? = nil) {
        var y: CGFloat = 4
        var layers: [SimpleLayer] = []
        var jobs: [(TextViewLayout, CGSize, Bool)] = []
        for i in 0..<count {
            let layout = AsyncTextFixtures.layout(i, width: width, paragraphs: paragraphs)
            let layer = SimpleLayer()
            layer.contentsScale = scale
            layer.frame = CGRect(x: 6, y: y, width: layout.layoutSize.width, height: layout.layoutSize.height + AsyncTextFixtures.extraHeight)
            AsyncTextFixtures.advance(&y, by: layer.frame.height)
            host.layer?.addSublayer(layer)
            layers.append(layer)
            jobs.append((layout, layer.bounds.size, layer.contentsAreFlipped()))
        }
        self.layers = layers
        let group = DispatchGroup()
        var results = [Any?](repeating: nil, count: jobs.count)
        let lock = NSLock()
        for (index, job) in jobs.enumerated() {
            queue.async(group: group) {
                let context = colorSpace.map { BackgroundDisplayContext(colorSpace: $0) }
                let contents = BackgroundDisplay.render(layout: job.0, bounds: job.1, scale: scale, flipped: job.2, format: format, context: context)
                lock.lock(); results[index] = contents; lock.unlock()
            }
        }
        group.wait()
        for (index, layer) in layers.enumerated() {
            layer.contents = results[index]
            contentsTypes.append(results[index].map { String(describing: type(of: $0)) } ?? "nil")
        }
    }
    public func remove() { layers.forEach { $0.removeFromSuperlayer() } }
}
