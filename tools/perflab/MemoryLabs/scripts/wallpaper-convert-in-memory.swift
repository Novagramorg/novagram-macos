import AppKit
import QuartzCore
import ImageIO

func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return Int(info.phys_footprint)
}

func to8bit(_ image: CGImage) -> CGImage? {
    let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()
}

func rgba8(_ image: CGImage) -> [UInt8] {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
}

let path = CommandLine.arguments[1] + "/light16.png"
let mode = CommandLine.arguments[2]

if mode == "check" {
    let original = NSImage(contentsOfFile: path)!
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    var t = CFAbsoluteTimeGetCurrent()
    let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!
    let decodeMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
    t = CFAbsoluteTimeGetCurrent()
    let eight = to8bit(decoded)!
    let convertMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
    let a = rgba8(decoded), b = rgba8(eight)
    var maxDiff = 0, diffCount = 0
    for i in 0 ..< a.count { let d = abs(Int(a[i]) - Int(b[i])); if d > 0 { diffCount += 1 }; maxDiff = max(maxDiff, d) }
    let converted = NSImage(cgImage: eight, size: original.size)
    print("depth=\(props[kCGImagePropertyDepth] ?? "?") space=\(decoded.colorSpace?.name ?? "nil" as CFString) nsimage size=\(original.size) converted size=\(converted.size)")
    print("decode16 \(String(format: "%.1f", decodeMs)) ms, convert \(String(format: "%.1f", convertMs)) ms; max channel diff \(maxDiff)/255 over \(diffCount) of \(a.count) channels")
    let src8 = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1] + "/light8.png") as CFURL, nil)!
    t = CFAbsoluteTimeGetCurrent()
    _ = CGImageSourceCreateImageAtIndex(src8, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!
    print("decode8 \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t) * 1000)) ms")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSMakeRect(0, 0, 900, 700), styleMask: [.titled], backing: .buffered, defer: false)
window.contentView!.wantsLayer = true
window.orderFrontRegardless()
let host = CALayer()
host.frame = window.contentView!.bounds
window.contentView!.layer!.addSublayer(host)
CATransaction.flush()
RunLoop.current.run(until: Date().addingTimeInterval(1.0))
let before = footprint()
let image: NSImage = autoreleasepool {
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    return NSImage(cgImage: to8bit(decoded)!, size: NSImage(contentsOfFile: path)!.size)
}
host.contentsGravity = .resizeAspectFill
host.contents = image
CATransaction.flush()
RunLoop.current.run(until: Date().addingTimeInterval(1.5))
print("converted-in-memory: footprint +\((footprint() - before) / 1024) KB after display")
