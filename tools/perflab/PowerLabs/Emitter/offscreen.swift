import AppKit
import QuartzCore
import Metal

let particle: CGImage = {
    let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 16, height: 16))
    return ctx.makeImage()!
}()
func makeEmitter(size: CGSize, birthRate: Float, velocity: CGFloat, scale: CGFloat) -> CAEmitterLayer {
    let layer = CAEmitterLayer(); let cell = CAEmitterCell()
    cell.contents = particle; cell.birthRate = birthRate; cell.lifetime = 1.5; cell.velocity = velocity
    cell.scale = scale; cell.scaleRange = 0.02; cell.alphaRange = 0.1; cell.emissionRange = .pi * 2
    cell.color = NSColor.systemYellow.cgColor
    layer.emitterCells = [cell]; layer.emitterShape = .circle; layer.emitterMode = .surface
    layer.emitterSize = size; layer.frame = CGRect(origin: .zero, size: size)
    layer.emitterPosition = CGPoint(x: size.width / 2, y: size.height / 2)
    return layer
}
let size = CGSize(width: 560, height: 160)
let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width * 2), height: Int(size.height * 2), mipmapped: false)
d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
let texture = device.makeTexture(descriptor: d)!

func run(_ variant: String) -> (ms: Double, dirtyFrames: Int, frames: Int) {
    let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
    let root = CALayer(); root.frame = CGRect(origin: .zero, size: size); root.backgroundColor = NSColor.white.cgColor
    renderer.layer = root; renderer.bounds = root.bounds
    CATransaction.flush()
    var emitters: [CAEmitterLayer] = []
    for i in 0 ..< 12 {
        let a = makeEmitter(size: CGSize(width: 25, height: 25), birthRate: 6, velocity: 0.1, scale: 0.09)
        a.frame.origin = CGPoint(x: 10 + CGFloat(i) * 45, y: 100)
        let b = makeEmitter(size: CGSize(width: 40, height: 30), birthRate: 20, velocity: 10, scale: 0.1)
        b.frame.origin = CGPoint(x: 10 + CGFloat(i) * 45, y: 30)
        root.addSublayer(a); root.addSublayer(b); emitters += [a, b]
    }
    if variant == "frozenAtStart" || variant == "frozenAtStartAhead" {
        emitters.forEach { layer in
            let t0 = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0; layer.timeOffset = t0 + (variant == "frozenAtStartAhead" ? 1.5 : 0)
        }
    }
    CATransaction.flush()
    let start = CACurrentMediaTime()
    var t = start
    for _ in 0 ..< 240 {
        renderer.beginFrame(atTime: t, timeStamp: nil); renderer.render(); renderer.endFrame(); t += 1.0 / 120.0
    }
    if variant == "frozen" {
        emitters.forEach { layer in
            let t0 = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0; layer.timeOffset = t0
        }
        CATransaction.flush()
    }
    if variant == "paused" {
        emitters.forEach { $0.birthRate = 0 }
        CATransaction.flush()
        for _ in 0 ..< 240 {
            renderer.beginFrame(atTime: t, timeStamp: nil); renderer.render(); renderer.endFrame(); t += 1.0 / 120.0
        }
    }
    var total = 0.0, dirty = 0
    let frames = 720
    for _ in 0 ..< frames {
        let c0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        renderer.beginFrame(atTime: t, timeStamp: nil)
        let b = renderer.updateBounds()
        if !b.isEmpty && !b.isNull { dirty += 1; renderer.addUpdate(b); renderer.render() }
        renderer.endFrame()
        let cb = queue.makeCommandBuffer()!; cb.commit(); cb.waitUntilCompleted()
        total += Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - c0) / 1e6
        t += 1.0 / 120.0
    }
    renderer.beginFrame(atTime: t, timeStamp: nil); renderer.addUpdate(renderer.bounds); renderer.render(); renderer.endFrame()
    let cb = queue.makeCommandBuffer()!; cb.commit(); cb.waitUntilCompleted()
    let bpr = texture.width * 4
    let buf = device.makeBuffer(length: bpr * texture.height, options: .storageModeShared)!
    let cb2 = queue.makeCommandBuffer()!; let blit = cb2.makeBlitCommandEncoder()!
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buf, destinationOffset: 0, destinationBytesPerRow: bpr, destinationBytesPerImage: bpr * texture.height)
    blit.endEncoding(); cb2.commit(); cb2.waitUntilCompleted()
    let p = buf.contents().assumingMemoryBound(to: UInt8.self)
    var nonWhite = 0
    for i in stride(from: 0, to: bpr * texture.height, by: 4) where abs(Int(p[i]) - Int(p[0])) > 8 || abs(Int(p[i+1]) - Int(p[1])) > 8 || abs(Int(p[i+2]) - Int(p[2])) > 8 { nonWhite += 1 }
    print("  \(variant): particle pixels on screen \(nonWhite)")
    return (total / Double(frames), dirty, frames)
}
for round in 0 ..< 1 {
    for v in ["playing", "frozen", "frozenAtStart", "frozenAtStartAhead"] {
        let r = run(v)
        print(String(format: "round %d %@: %.3f ms/frame, frames needing a render %d of %d", round, v, r.ms, r.dirtyFrames, r.frames))
    }
}
