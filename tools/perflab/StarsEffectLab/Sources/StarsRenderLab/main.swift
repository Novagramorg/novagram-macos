import AppKit
import QuartzCore
import Metal
import CryptoKit
import ImageIO
import Effects
import TGUIKit

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
System.updateScaleFactor(2)
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
let directory = URL(fileURLWithPath: CommandLine.arguments.last!)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let size = CGSize(width: 400, height: 160)
var results: [[String: Any]] = []

func capture(_ texture: MTLTexture) -> Data {
    let bytesPerRow = texture.width * 4
    let buffer = device.makeBuffer(length: bytesPerRow * texture.height, options: .storageModeShared)!
    let command = queue.makeCommandBuffer()!
    let blit = command.makeBlitCommandEncoder()!
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * texture.height)
    blit.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    precondition(command.status == .completed)
    return Data(bytes: buffer.contents(), count: bytesPerRow * texture.height)
}

for scenario in ["steady", "resized", "recolored", "pause_resume"] {
    for baseline in [true, false] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)!
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor
        root.beginTime = 1000
        renderer.layer = root
        renderer.bounds = root.bounds
        var layers: [CALayer] = []
        var update: [() -> Void] = []
        var playback: [(Bool) -> Void] = []
        for index in 0..<4 {
            let finalSize = CGSize(width: scenario == "resized" ? 64 : 40, height: scenario == "resized" ? 64 : 40)
            let color: NSColor = scenario == "recolored" ? .systemBlue : .systemYellow
            let layer: CALayer
            if baseline {
                let effect = ReferenceStarsEffectLayer()
                effect.update(color: color, size: finalSize)
                layer = effect
                playback.append { effect.isPlaying = $0 }
            } else {
                let effect = CandidateStarsEffectLayer()
                if scenario == "resized" { effect.update(color: color, size: CGSize(width: 25, height: 25)) }
                if scenario == "recolored" { effect.update(color: .red, size: finalSize) }
                effect.update(color: color, size: finalSize)
                layer = effect
                update.append { effect.update(color: color, size: finalSize) }
                playback.append { effect.isPlaying = $0 }
            }
            layer.frame = CGRect(origin: CGPoint(x: 30 + index * 90, y: 50), size: finalSize)
            let emitter = layer.sublayers!.compactMap { $0 as? CAEmitterLayer }.first!
            emitter.seed = UInt32(100 + index)
            root.addSublayer(layer)
            layers.append(layer)
        }
        CATransaction.flush()
        for frame in 0...300 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if frame % 5 == 0 { update.forEach { $0() } }
            if scenario == "pause_resume" {
                if frame == 60 { playback.forEach { $0(false) } }
                if frame == 240 { playback.forEach { $0(true) } }
            }
            CATransaction.commit()
            CATransaction.flush()
            renderer.beginFrame(atTime: 1000 + Double(frame) / 60, timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
            let fence = queue.makeCommandBuffer()!
            fence.commit(); fence.waitUntilCompleted()
            if [30, 180, 300].contains(frame) {
                let data = capture(texture)
                var pixels = 0
                data.withUnsafeBytes { raw in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    for index in stride(from: 0, to: bytes.count, by: 4) {
                        if abs(Int(bytes[index]) - Int(bytes[0])) > 4 || abs(Int(bytes[index + 1]) - Int(bytes[1])) > 4 || abs(Int(bytes[index + 2]) - Int(bytes[2])) > 4 { pixels += 1 }
                    }
                }
                let variant = baseline ? "baseline" : "candidate"
                let name = "\(variant)-\(scenario)-\(frame)"
                let image = CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: texture.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
                let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name + ".png") as CFURL, "public.png" as CFString, 1, nil)!
                CGImageDestinationAddImage(destination, image, nil)
                precondition(CGImageDestinationFinalize(destination))
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                results.append(["variant": variant, "scenario": scenario, "frame": frame, "particle_pixels": pixels, "sha256": hash])
                print("\(name): \(pixels) particle pixels")
            }
        }
        withExtendedLifetime(layers) {}
    }
}
let data = try JSONSerialization.data(withJSONObject: ["results": results], options: [.prettyPrinted, .sortedKeys])
try data.write(to: directory.appendingPathComponent("renders.json"))
