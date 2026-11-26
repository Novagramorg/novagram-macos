import Cocoa
import XCTest
import QuartzCore
import Metal
import TGUIKit
import ProgressReference

extension ProgressTests {
    func testAnimatedMetalFramesMatch() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var changingScenarios = 0
        for scenario in ["playback", "paused", "width", "ranges"] {
            let (old, new) = pair(8)
            var variants: [[Data]] = []
            for (index, bar) in ([old, new] as [any ProgressBar]).enumerated() {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                bar.roundCorners = true
                bar.scrubberImage = icon()
                bar.layout()
                bar.progress(0.1)
                bar.fetching(0.8)
                window.displayIfNeeded()
                func clearAnimations(_ layer: CALayer) {
                    layer.removeAllAnimations()
                    layer.sublayers?.forEach(clearAnimations)
                }
                clearAnimations(bar.layer!)
                if scenario == "playback" || scenario == "paused" {
                    bar.set(progress: 0.1, animated: true, duration: 4, beginTime: 0.01, offset: scenario == "paused" ? 2 : 0, speed: scenario == "paused" ? 0 : 1, seekId: 1, repeatForever: false)
                } else if scenario == "width" {
                    bar.set(progress: 0.9, animated: true, duration: 4, timingFunction: .linear, bounce: false)
                } else {
                    bar.progress(0.4)
                    bar.set(fetchingProgressRanges: [0..<1, 0.2..<0.9], animated: true)
                }
                window.displayIfNeeded()
                var animations: [(CALayer, String, CAAnimation)] = []
                func collect(_ layer: CALayer) {
                    for key in layer.animationKeys() ?? [] {
                        animations.append((layer, key, layer.animation(forKey: key)!.copy() as! CAAnimation))
                    }
                    layer.sublayers?.forEach(collect)
                }
                collect(bar.layer!)
                XCTAssertFalse(animations.isEmpty)
                let renderLayer = bar.layer!
                bar.removeFromSuperview()
                let root = CALayer()
                root.frame = bar.bounds
                let startTime = CACurrentMediaTime()
                root.backgroundColor = NSColor.black.cgColor
                renderLayer.frame = bar.bounds
                root.addSublayer(renderLayer)
                CATransaction.commit()
                CATransaction.flush()

                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 320, height: 30, mipmapped: false)
                descriptor.usage = [.renderTarget, .shaderRead]
                descriptor.storageMode = .private
                let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
                let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
                renderer.layer = root
                renderer.bounds = bar.bounds
                CATransaction.flush()
                var frames: [Data] = []
                for time in [Double(0.1), 1, 2, 3] {
                    for (layer, key, original) in animations {
                        let animation = original.copy() as! CAAnimation
                        animation.speed = 0
                        animation.beginTime = 0
                        animation.timeOffset = original.timeOffset + time * Double(original.speed)
                        if scenario == "ranges" { animation.duration = 4 }
                        animation.fillMode = .both
                        animation.isRemovedOnCompletion = false
                        layer.add(animation, forKey: key)
                    }
                    CATransaction.flush()
                    renderer.beginFrame(atTime: startTime + time, timeStamp: nil)
                    renderer.addUpdate(renderer.bounds)
                    renderer.render()
                    renderer.endFrame()
                    let fence = queue.makeCommandBuffer()!
                    fence.commit(); fence.waitUntilCompleted()
                    let buffer = try XCTUnwrap(device.makeBuffer(length: 320 * 30 * 4, options: .storageModeShared))
                    let command = queue.makeCommandBuffer()!
                    let blit = command.makeBlitCommandEncoder()!
                    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: 320, height: 30, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: 1280, destinationBytesPerImage: 38400)
                    blit.endEncoding(); command.commit(); command.waitUntilCompleted()
                    XCTAssertEqual(command.status, .completed)
                    let data = Data(bytes: buffer.contents(), count: 38400)
                    XCTAssertTrue(data.contains { $0 != 0 && $0 != 255 }, scenario)
                    frames.append(data)
                    if let path = ProcessInfo.processInfo.environment["PROGRESS_RENDER_DIR"] {
                        let directory = URL(fileURLWithPath: path)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let image = CGImage(width: 320, height: 30, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1280, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
                        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(index == 0 ? "baseline" : "candidate")-\(scenario)-\(time).png"))
                    }
                }
                variants.append(frames)
                bar.removeFromSuperview()
            }
            for (a, b) in zip(variants[0], variants[1]) { XCTAssertEqual(a, b, scenario) }
            if scenario != "paused" {
                XCTAssertNotEqual(variants[1][0], variants[1][3], scenario)
                changingScenarios += 1
            } else {
                XCTAssertEqual(variants[1][0], variants[1][3])
            }
        }
        XCTAssertEqual(changingScenarios, 3)
    }
}
