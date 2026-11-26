import AppKit
import QuartzCore
import Metal

let size = CGSize(width: 300, height: 400)
let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width), height: Int(size.height), mipmapped: false)
d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
let texture = device.makeTexture(descriptor: d)!

func dots(_ t: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0 ..< 3 {
        let phase = (t + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
        let r = 2 + 1.5 * sin(phase * .pi * 2)
        p.addEllipse(in: CGRect(x: 4 + CGFloat(i) * 8 - r, y: 10 - r, width: r * 2, height: r * 2))
    }
    return p
}
func run(_ frozen: Bool) -> (Double, Int) {
    let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
    let root = CALayer(); root.frame = CGRect(origin: .zero, size: size); root.backgroundColor = NSColor.white.cgColor
    renderer.layer = root; renderer.bounds = root.bounds
    CATransaction.flush()
    var layers: [CAShapeLayer] = []
    for row in 0 ..< 8 {
        let l = CAShapeLayer(); l.frame = CGRect(x: 20, y: 20 + CGFloat(row) * 45, width: 30, height: 20); l.fillColor = NSColor.systemBlue.cgColor
        let a = CAKeyframeAnimation(keyPath: "path"); a.values = (0 ..< 42).map { dots(CGFloat($0) / 42) }; a.duration = 0.7; a.repeatCount = .infinity; a.isRemovedOnCompletion = false
        l.add(a, forKey: "path"); root.addSublayer(l); layers.append(l)
    }
    CATransaction.flush()
    if frozen {
        for l in layers { let t = l.convertTime(CACurrentMediaTime(), from: nil); l.speed = 0; l.timeOffset = t }
        CATransaction.flush()
    }
    var t = CACurrentMediaTime()
    for _ in 0 ..< 60 { renderer.beginFrame(atTime: t, timeStamp: nil); renderer.addUpdate(renderer.bounds); renderer.render(); renderer.endFrame(); t += 1 / 120 }
    var total = 0.0, dirty = 0
    for _ in 0 ..< 720 {
        let c0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        renderer.beginFrame(atTime: t, timeStamp: nil)
        let b = renderer.updateBounds()
        if !b.isEmpty && !b.isNull { dirty += 1; renderer.addUpdate(b); renderer.render() }
        renderer.endFrame()
        let cb = queue.makeCommandBuffer()!; cb.commit(); cb.waitUntilCompleted()
        total += Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - c0) / 1e6
        t += 1 / 120
    }
    return (total / 720, dirty)
}
for _ in 0 ..< 2 {
    for f in [false, true] {
        let r = run(f)
        print(String(format: "8 typing indicators %@: %.3f ms/frame, frames needing a render %d of 720", f ? "frozen" : "playing", r.0, r.1))
    }
}
