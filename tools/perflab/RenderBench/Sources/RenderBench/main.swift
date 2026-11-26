import AppKit
import QuartzCore
import Metal
import TGUIKit
import SwiftSignalKit

struct Options {
    var variants: [String] = ["loaded", "shimmer", "static", "silhouette", "replica", "tguikit", "line", "section"]
    var frames: Int = 600
    var warmup: Int = 60
    var speed: CGFloat = 1800
    var runs: Int = 3
    var mode: String = "scroll"
    var placeholderFraction: Double = 1.0
    var snapshotDirectory: String?
    var compare: [String]?
    var roundedShapes: Bool = false
    var size: CGFloat = 30

    static func parse() -> Options {
        var options = Options()
        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let name = arguments.removeFirst()
            let value = arguments.isEmpty ? "" : arguments.removeFirst()
            switch name {
            case "--variants":
                options.variants = value.split(separator: ",").map(String.init)
            case "--frames":
                options.frames = Int(value) ?? options.frames
            case "--speed":
                options.speed = CGFloat(Double(value) ?? Double(options.speed))
            case "--runs":
                options.runs = Int(value) ?? options.runs
            case "--mode":
                options.mode = value
            case "--placeholders":
                options.placeholderFraction = Double(value) ?? 1.0
            case "--snapshots":
                options.snapshotDirectory = value
            case "--compare":
                options.compare = value.split(separator: ",").map(String.init)
                options.roundedShapes = true
            case "--size":
                options.size = CGFloat(Double(value) ?? 30)
            case "--rounded":
                options.roundedShapes = value == "1"
            default:
                print("unknown argument \(name)")
                exit(1)
            }
        }
        return options
    }
}

let options = Options.parse()
let viewportSize = CGSize(width: 360, height: 520)
let cellSize = CGSize(width: options.size + 10, height: options.size + 4)
let perLine = Int(floor((viewportSize.width - 20) / (options.size + 10)))
let linesPerSection = 30
let sectionCount = 6
let emojiSize = CGSize(width: options.size, height: options.size)
let shimmerBase = NSColor(rgb: 0x748391)
let foregroundColor = shimmerBase.withAlphaComponent(0.2)
let shimmeringColor = shimmerBase.withAlphaComponent(0.35)
let baseTime = floor(CACurrentMediaTime())

func emojiRect(line: Int, column: Int) -> CGRect {
    return CGRect(x: 10 + CGFloat(column) * cellSize.width, y: CGFloat(line) * cellSize.height, width: cellSize.width, height: cellSize.height).insetBy(dx: 2, dy: 2)
}

func centered(_ size: CGSize, in bounds: CGRect) -> CGRect {
    return CGRect(x: bounds.minX + round((bounds.width - size.width) / 2), y: bounds.minY + round((bounds.height - size.height) / 2), width: size.width, height: size.height)
}

func silhouetteImage(index: Int, color: NSColor) -> CGImage? {
    return generateImage(emojiSize, scale: 2.0, rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        context.setFillColor(color.cgColor)
        if options.roundedShapes {
            let radius = min(min(4, size.height / 2), size.width / 2)
            let path = CGMutablePath()
            path.addRoundedRect(in: CGRect(origin: .zero, size: size), cornerWidth: radius, cornerHeight: radius)
            context.addPath(path)
        } else {
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: CGFloat(index % 5), dy: CGFloat((index / 5) % 4))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: rect.width / 3, cornerHeight: rect.height / 3, transform: nil))
        }
        context.fillPath()
    })
}

func loadedImage(index: Int) -> CGImage? {
    let hue = CGFloat(index % 17) / 17.0
    return generateImage(emojiSize, scale: 2.0, rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1.0).cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
    })
}

let sweepImage: CGImage? = generateImage(CGSize(width: 320, height: 16), opaque: false, scale: 1.0, rotatedContext: { size, context in
    context.clear(CGRect(origin: .zero, size: size))
    var locations: [CGFloat] = [0.0, 0.5, 1.0]
    let colors = [shimmeringColor.withAlphaComponent(0).cgColor, shimmeringColor.cgColor, shimmeringColor.withAlphaComponent(0).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: &locations)!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
})

func addSweep(to host: CALayer, width: CGFloat, height: CGFloat) {
    let sweep = SimpleLayer()
    sweep.contents = sweepImage
    sweep.frame = CGRect(x: -320, y: 0, width: 320, height: height)
    let animation = CABasicAnimation(keyPath: "position.x")
    animation.fromValue = 0.0
    animation.toValue = width + 320
    animation.isAdditive = true
    animation.duration = 1.5
    animation.repeatCount = .infinity
    animation.beginTime = 1.0
    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
    sweep.add(animation, forKey: "shimmer")
    host.addSublayer(sweep)
}

func replicaAnimation(width: CGFloat, frameRate: Float?) -> CAAnimation {
    let travel = width + 320
    let center = width / 2
    let animation = CAKeyframeAnimation(keyPath: "opacity")
    animation.values = [0.2, 0.2, 0.48, 0.2, 0.2]
    animation.keyTimes = [0, center / travel, (center + 160) / travel, (center + 320) / travel, 1].map { NSNumber(value: Double($0)) }
    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
    animation.duration = 1.5
    animation.repeatCount = .infinity
    animation.beginTime = 1.0
    if let frameRate = frameRate, #available(macOS 12.0, *) {
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate / 2, maximum: frameRate, preferred: frameRate)
    }
    return animation
}

final class Scene {
    let top = CALayer()
    let root = CALayer()
    let document = CALayer()
    var holders: [Any] = []
    let documentHeight: CGFloat

    init() {
        let lines = linesPerSection * sectionCount
        self.documentHeight = CGFloat(lines) * cellSize.height
        self.top.bounds = CGRect(x: 0, y: 0, width: viewportSize.width * 2, height: viewportSize.height * 2)
        self.top.position = CGPoint(x: viewportSize.width, y: viewportSize.height)
        self.root.bounds = CGRect(origin: .zero, size: viewportSize)
        self.root.position = self.top.position
        self.root.transform = CATransform3DMakeScale(2, 2, 1)
        self.root.masksToBounds = true
        self.root.backgroundColor = NSColor.white.cgColor
        self.top.addSublayer(self.root)
        self.document.anchorPoint = .zero
        self.document.bounds = CGRect(x: 0, y: 0, width: viewportSize.width, height: self.documentHeight)
        self.document.position = .zero
        self.root.addSublayer(self.document)
    }

    private func makeShimmerHost(frame: CGRect, in parent: CALayer) -> CALayer {
        let host = CALayer()
        host.frame = frame
        let fill = CALayer()
        fill.frame = host.bounds
        fill.backgroundColor = foregroundColor.cgColor
        host.addSublayer(fill)
        addSweep(to: host, width: host.bounds.width, height: host.bounds.height)
        let mask = CALayer()
        mask.frame = host.bounds
        host.mask = mask
        parent.addSublayer(host)
        return mask
    }

    func populate(variant: String, placeholderFraction: Double) {
        var index = 0
        for section in 0 ..< sectionCount {
            let sectionLayer = CALayer()
            sectionLayer.frame = CGRect(x: 0, y: CGFloat(section * linesPerSection) * cellSize.height, width: viewportSize.width, height: CGFloat(linesPerSection) * cellSize.height)
            self.document.addSublayer(sectionLayer)
            let sectionMask = variant == "section" ? self.makeShimmerHost(frame: sectionLayer.bounds, in: sectionLayer) : nil
            for line in 0 ..< linesPerSection {
                let lineMask = variant == "line" ? self.makeShimmerHost(frame: CGRect(x: 0, y: CGFloat(line) * cellSize.height, width: viewportSize.width, height: cellSize.height), in: sectionLayer) : nil
                for column in 0 ..< perLine {
                    let rect = emojiRect(line: line, column: column)
                    let container = SimpleLayer()
                    container.frame = rect
                    container.masksToBounds = true
                    sectionLayer.addSublayer(container)
                    let isPlaceholder = Double((index * 7919) % 1000) / 1000.0 < placeholderFraction
                    defer { index += 1 }
                    if variant == "loaded" || !isPlaceholder {
                        container.contents = loadedImage(index: index)
                        container.contentsGravity = .center
                        continue
                    }
                    let aspect = centered(emojiSize, in: container.bounds)
                    switch variant {
                    case "shimmer", "static":
                        let shimmer = ShimmerLayer()
                        container.addSublayer(shimmer)
                        shimmer.update(backgroundColor: nil, foregroundColor: foregroundColor, shimmeringColor: shimmeringColor, data: nil, size: emojiSize, imageSize: CGSize(width: 512, height: 512))
                        shimmer.updateAbsoluteRect(container.bounds, within: emojiSize)
                        shimmer.frame = aspect
                        if variant == "static" {
                            shimmer.sublayers?[1].isHidden = true
                        }
                        self.holders.append(shimmer)
                    case "silhouette":
                        let layer = SimpleLayer()
                        layer.frame = aspect
                        layer.contents = silhouetteImage(index: index, color: foregroundColor)
                        container.addSublayer(layer)
                    case "tguikit":
                        let shimmer = SilhouetteShimmerLayer()
                        container.addSublayer(shimmer)
                        shimmer.update(foregroundColor: foregroundColor, shimmeringColor: shimmeringColor, data: nil, size: emojiSize, imageSize: CGSize(width: 512, height: 512))
                        shimmer.frame = aspect
                        self.holders.append(shimmer)
                    case "replica", "replica30":
                        let layer = SimpleLayer()
                        layer.frame = aspect
                        layer.contents = silhouetteImage(index: index, color: shimmerBase.withAlphaComponent(1.0))
                        layer.opacity = 0.2
                        layer.add(replicaAnimation(width: aspect.width, frameRate: variant == "replica30" ? 30 : nil), forKey: "shimmer")
                        container.addSublayer(layer)
                    case "line", "section":
                        let piece = CALayer()
                        piece.contents = silhouetteImage(index: index, color: .black)
                        if let lineMask = lineMask {
                            piece.frame = CGRect(x: rect.minX + aspect.minX, y: aspect.minY + 2, width: aspect.width, height: aspect.height)
                            lineMask.addSublayer(piece)
                        } else if let sectionMask = sectionMask {
                            piece.frame = CGRect(x: rect.minX + aspect.minX, y: rect.minY + aspect.minY, width: aspect.width, height: aspect.height)
                            sectionMask.addSublayer(piece)
                        }
                    default:
                        print("unknown variant \(variant)")
                        exit(1)
                    }
                }
            }
        }
    }

    func setOffset(_ offset: CGFloat) {
        self.document.position = CGPoint(x: 0, y: -offset)
    }
}

struct FrameStats {
    var times: [Double]
    var cpu: Double

    func percentile(_ p: Double) -> Double {
        let sorted = self.times.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
    }

    var mean: Double {
        return self.times.reduce(0, +) / Double(self.times.count)
    }

    var renderedFrames: Int {
        return self.times.filter { $0 > 0.0002 }.count
    }
}

func cpuTime() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6 + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
}

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    print("no metal device")
    exit(1)
}
let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(viewportSize.width * 2), height: Int(viewportSize.height * 2), mipmapped: false)
descriptor.usage = [.renderTarget, .shaderRead]
descriptor.storageMode = .private
guard let texture = device.makeTexture(descriptor: descriptor) else {
    print("no texture")
    exit(1)
}

func readPixels() -> [UInt8] {
    let bytesPerRow = texture.width * 4
    let length = bytesPerRow * texture.height
    guard let buffer = device.makeBuffer(length: length, options: .storageModeShared), let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else {
        return []
    }
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: length)
    blit.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: length))
}

func writeSnapshot(_ pixels: [UInt8], to path: String) {
    var pixels = pixels
    let bytesPerRow = texture.width * 4
    pixels.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(data: bytes.baseAddress, width: texture.width, height: texture.height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let image = context.makeImage() else {
            return
        }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

func render(_ renderer: CARenderer, at time: Double) {
    renderer.beginFrame(atTime: time, timeStamp: nil)
    renderer.addUpdate(renderer.bounds)
    renderer.render()
    renderer.endFrame()
    if let fence = queue.makeCommandBuffer() {
        fence.commit()
        fence.waitUntilCompleted()
    }
}

func makeScene(variant: String) -> (Scene, CARenderer) {
    let scene = Scene()
    let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
    renderer.layer = scene.top
    renderer.bounds = scene.top.bounds
    CATransaction.flush()
    render(renderer, at: baseTime)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    scene.populate(variant: variant, placeholderFraction: options.placeholderFraction)
    CATransaction.commit()
    CATransaction.flush()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
    CATransaction.flush()
    return (scene, renderer)
}

func run(variant: String) -> FrameStats {
    let (scene, renderer) = makeScene(variant: variant)
    let travel = scene.documentHeight - viewportSize.height
    var times: [Double] = []
    var cpuStart = 0.0
    for frame in 0 ..< options.warmup + options.frames {
        if frame == options.warmup {
            cpuStart = cpuTime()
        }
        let time = baseTime + 10.0 + Double(frame) / 120.0
        if options.mode == "scroll" {
            let distance = CGFloat(Double(frame) / 120.0) * options.speed
            let phase = distance.truncatingRemainder(dividingBy: travel * 2)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scene.setOffset(phase < travel ? phase : travel * 2 - phase)
            CATransaction.commit()
        }
        CATransaction.flush()
        let frameStart = CACurrentMediaTime()
        renderer.beginFrame(atTime: time, timeStamp: nil)
        if options.mode == "scroll" {
            renderer.addUpdate(renderer.bounds)
        }
        renderer.render()
        renderer.endFrame()
        if let fence = queue.makeCommandBuffer() {
            fence.commit()
            fence.waitUntilCompleted()
        }
        if frame >= options.warmup {
            times.append(CACurrentMediaTime() - frameStart)
        }
    }
    let cpu = cpuTime() - cpuStart
    if let snapshotDirectory = options.snapshotDirectory {
        writeSnapshot(readPixels(), to: "\(snapshotDirectory)/\(variant).png")
    }
    renderer.layer = nil
    CATransaction.flush()
    return FrameStats(times: times, cpu: cpu)
}

func capture(variant: String, times: [Double]) -> [[UInt8]] {
    let (_, renderer) = makeScene(variant: variant)
    var result: [[UInt8]] = []
    for time in times {
        CATransaction.flush()
        render(renderer, at: time)
        result.append(readPixels())
    }
    renderer.layer = nil
    CATransaction.flush()
    return result
}

if options.mode == "create" {
    for variant in ["shimmer", "tguikit", "shimmer", "tguikit"] {
        let count = 2000
        let host = CALayer()
        var layers: [CALayer] = []
        layers.reserveCapacity(count)
        let start = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for _ in 0 ..< count {
            if variant == "shimmer" {
                let shimmer = ShimmerLayer()
                host.addSublayer(shimmer)
                shimmer.update(backgroundColor: nil, foregroundColor: foregroundColor, shimmeringColor: shimmeringColor, data: nil, size: emojiSize, imageSize: CGSize(width: 512, height: 512))
                shimmer.updateAbsoluteRect(CGRect(x: 0, y: 0, width: 36, height: 30), within: emojiSize)
                shimmer.frame = CGRect(x: 3, y: 0, width: 30, height: 30)
                layers.append(shimmer)
            } else {
                let shimmer = SilhouetteShimmerLayer()
                host.addSublayer(shimmer)
                shimmer.update(foregroundColor: foregroundColor, shimmeringColor: shimmeringColor, data: nil, size: emojiSize, imageSize: CGSize(width: 512, height: 512))
                shimmer.frame = CGRect(x: 3, y: 0, width: 30, height: 30)
                layers.append(shimmer)
            }
        }
        let created = CACurrentMediaTime()
        CATransaction.commit()
        CATransaction.flush()
        let committed = CACurrentMediaTime()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
        let drainStart = CACurrentMediaTime()
        CATransaction.flush()
        let drained = CACurrentMediaTime()
        print(String(format: "%-9@ create %.1f us/layer, commit %.1f us/layer, image delivery commit %.1f us/layer", variant as NSString, (created - start) / Double(count) * 1e6, (committed - created) / Double(count) * 1e6, (drained - drainStart) / Double(count) * 1e6))
        layers.removeAll()
    }
    exit(0)
}

if let compare = options.compare, compare.count == 2 {
    let times = (0 ..< 31).map { baseTime + 10.0 + Double($0) * 0.05 }
    let first = capture(variant: compare[0], times: times)
    let second = capture(variant: compare[1], times: times)
    print("compare \(compare[0]) vs \(compare[1]) (channel values 0-255)")
    var worst = 0
    for (index, time) in times.enumerated() {
        let a = first[index]
        let b = second[index]
        var maxDiff = 0
        var sum = 0
        var changed = 0
        for i in 0 ..< min(a.count, b.count) {
            let diff = abs(Int(a[i]) - Int(b[i]))
            maxDiff = max(maxDiff, diff)
            sum += diff
            if diff > 2 {
                changed += 1
            }
        }
        worst = max(worst, maxDiff)
        let center = a.count / 2
        print(String(format: "t=%.2f max=%3d mean=%.3f over2=%6d centerA=%3d centerB=%3d", time - baseTime - 10.0, maxDiff, Double(sum) / Double(a.count), changed, a[center], b[center]))
        if let snapshotDirectory = options.snapshotDirectory, index % 5 == 0 {
            writeSnapshot(a, to: "\(snapshotDirectory)/\(compare[0])-\(index).png")
            writeSnapshot(b, to: "\(snapshotDirectory)/\(compare[1])-\(index).png")
        }
    }
    print("worst channel difference \(worst)")
    exit(0)
}

print("mode=\(options.mode) frames=\(options.frames) speed=\(options.speed) placeholders=\(options.placeholderFraction)")
print("variant        meanMs    p50Ms    p95Ms    maxMs   cpuMs/f  rendered")
for variant in options.variants {
    var results: [FrameStats] = []
    for _ in 0 ..< options.runs {
        results.append(autoreleasepool { run(variant: variant) })
    }
    let sorted = results.sorted(by: { $0.mean < $1.mean })
    let median = sorted[sorted.count / 2]
    print(String(format: "%-12@ %8.3f %8.3f %8.3f %8.3f %9.3f %9d   runs %@", variant as NSString, median.mean * 1000, median.percentile(0.5) * 1000, median.percentile(0.95) * 1000, median.times.max()! * 1000, median.cpu / Double(options.frames) * 1000, median.renderedFrames, results.map { String(format: "%.3f", $0.mean * 1000) }.joined(separator: "/") as NSString))
}
