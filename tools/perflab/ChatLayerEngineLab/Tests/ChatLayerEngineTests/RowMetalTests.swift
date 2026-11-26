import Cocoa
import XCTest
import Metal
import TGUIKit
@testable import ChatLayerEngine

extension RowTests {
    func testOverlappingRowsAndAnimatedMetalFrames() throws {
        try compareOverlappingRowsAndAnimatedMetalFrames(quote: false)
    }

    func testQuotedRowsAndAnimatedMetalFrames() throws {
        try compareOverlappingRowsAndAnimatedMetalFrames(quote: true)
    }

    func testFoldedAndExpandedRowsAndAnimatedMetalFrames() throws {
        for folded in [false, true] {
            try compareOverlappingRowsAndAnimatedMetalFrames(quote: true, folded: folded)
        }
    }

    func testCodeHeadersAndAnimatedMetalFrames() throws {
        for folded in [nil, false, true] as [Bool?] {
            try compareOverlappingRowsAndAnimatedMetalFrames(quote: true, folded: folded, codeHeader: true)
        }
    }

    private func compareOverlappingRowsAndAnimatedMetalFrames(quote: Bool, folded: Bool? = nil, codeHeader: Bool = false) throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let fixture = PlainRowFixture(quote: quote, folded: folded, codeHeader: codeHeader)
        let size = NSSize(width: fixture.size.width, height: fixture.size.height + 60)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        for includeEmoji in [false, true] {
        for overlaps in [false, true] {
            var variants: [[Data]] = []
            for candidate in [false, true] {
                let native = NativePlainRow(PlainRowFixture(includeEmoji: includeEmoji, quote: quote, folded: folded, codeHeader: codeHeader)), layered = LayerPlainRow(PlainRowFixture(includeEmoji: includeEmoji, quote: quote, folded: folded, codeHeader: codeHeader))
                XCTAssertEqual(native.views["body"]?.frame, layered.nodes["body"]?.frame)
                if folded != nil {
                    let body = try XCTUnwrap(layered.nodes["body"] as? ChatLayerMessageTextNode)
                    let text = try XCTUnwrap(body.textNodes.first)
                    XCTAssertFalse(text.drawingLayer.canDrawBlocks)
                    XCTAssertEqual(text.drawingLayer.mask != nil, folded == true)
                }
                let host: View = candidate ? layered.view : native.view
                host.setFrameSize(size)
                window.contentView = host
                if overlaps {
                    let frame = NSRect(x: 10, y: 130, width: 160, height: 45)
                    let color = NSColor.red.withAlphaComponent(0.5)
                    if candidate {
                        let node = ChatLayerNode(id: "overlap")
                        node.frame = frame; node.layer.backgroundColor = color.cgColor
                        let bubble = layered.nodes["bubble"]!
                        var children = bubble.children
                        children.insert(node, at: 4)
                        try bubble.setChildren(children)
                    } else {
                        let view = View(frame: frame)
                        view.backgroundColor = color
                        native.views["bubble"]!.addSubview(view, positioned: .above, relativeTo: native.views["body"]!)
                    }
                }
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                func prepare(_ layer: CALayer) {
                    layer.removeAllAnimations()
                    if !(layer.delegate is NSView) { layer.displayIfNeeded() }
                    layer.sublayers?.forEach(prepare)
                }
                prepare(host.layer!)
                let target = candidate ? layered.nodes["bubble"]!.layer : native.views["bubble"]!.layer!
                let animation = CABasicAnimation(keyPath: "position")
                animation.fromValue = target.position
                animation.toValue = NSPoint(x: target.position.x + 18, y: target.position.y + 42)
                animation.duration = 4
                animation.speed = 0
                animation.fillMode = .both
                animation.isRemovedOnCompletion = false
                let opacity = CABasicAnimation(keyPath: "opacity")
                opacity.fromValue = 1
                opacity.toValue = 0.35
                opacity.duration = 4
                opacity.speed = 0
                opacity.fillMode = .both
                opacity.isRemovedOnCompletion = false
                let renderLayer = host.layer!
                window.contentView = nil
                let root = CALayer()
                root.frame = NSRect(origin: .zero, size: size)
                root.backgroundColor = NSColor.white.cgColor
                root.addSublayer(renderLayer)
                renderLayer.frame = root.bounds
                let width = Int(size.width), height = Int(size.height)
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
                descriptor.usage = [.renderTarget, .shaderRead]
                descriptor.storageMode = .private
                let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
                let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
                renderer.layer = root
                renderer.bounds = root.bounds
                var frames: [Data] = []
                for time in [0.1, 1.0, 2.0, 3.0] {
                    animation.timeOffset = time
                    opacity.timeOffset = time
                    target.add(animation, forKey: "move")
                    target.add(opacity, forKey: "fade")
                    CATransaction.flush()
                    renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
                    renderer.addUpdate(renderer.bounds)
                    renderer.render()
                    renderer.endFrame()
                    let count = width * height * 4
                    let buffer = try XCTUnwrap(device.makeBuffer(length: count, options: .storageModeShared))
                    let command = try XCTUnwrap(queue.makeCommandBuffer())
                    let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
                    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: count)
                    blit.endEncoding(); command.commit(); command.waitUntilCompleted()
                    XCTAssertEqual(command.status, .completed)
                    let data = Data(bytes: buffer.contents(), count: count)
                    XCTAssertTrue(data.contains { $0 > 0 && $0 < 240 })
                    let directory = URL(fileURLWithPath: "/tmp/chat-layer-engine-metal")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
                    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(candidate ? "layers" : "views")-header-\(codeHeader)-folded-\(String(describing: folded))-quote-\(quote)-emoji-\(includeEmoji)-\(overlaps)-\(time).png"))
                    frames.append(data)
                }
                XCTAssertNotEqual(frames.first, frames.last)
                variants.append(frames)
            }
            for i in 0..<4 {
                let differences = zip(variants[0][i], variants[1][i]).enumerated().filter { $0.element.0 != $0.element.1 }
                let maximum = differences.map { abs(Int($0.element.0) - Int($0.element.1)) }.max() ?? 0
                print("METAL_PARITY code_header=\(codeHeader) folded=\(String(describing: folded)) quote=\(quote) emoji=\(includeEmoji) overlap=\(overlaps) frame=\(i) differing_bytes=\(differences.count) max_channel_difference=\(maximum)")
                if includeEmoji {
                    XCTAssertLessThanOrEqual(maximum, 3)
                    XCTAssertLessThanOrEqual(differences.count, 400)
                } else {
                    XCTAssertLessThanOrEqual(maximum, 1)
                    XCTAssertLessThanOrEqual(differences.count, 140)
                }
            }
        }
        }
    }
}
