import AppKit
import ImageIO
func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return Int(info.phys_footprint)
}
let path = CommandLine.arguments[1]
let mode = CommandLine.arguments[2]
let n = 10
var kept: [Any] = []
let before = footprint()
var t = CFAbsoluteTimeGetCurrent()
for _ in 0 ..< n {
    autoreleasepool {
        let thumbSize = CGSize(width: 140, height: 160)
        let ctx = CGContext(data: nil, width: Int(thumbSize.width), height: Int(thumbSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if mode == "full" {
            let image = NSImage(contentsOfFile: path)!
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            ctx.draw(cg, in: CGRect(origin: .zero, size: thumbSize))
            kept.append(image)
        } else {
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
            let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary)!
            ctx.draw(small, in: CGRect(origin: .zero, size: thumbSize))
            kept.append(NSImage(cgImage: small, size: NSSize(width: 800, height: 1600)))
        }
        kept.append(ctx.makeImage()!)
    }
}
let elapsed = CFAbsoluteTimeGetCurrent() - t
print("\(mode): \(n) theme thumbs keep +\((footprint() - before) / 1024) KB, \(String(format: "%.1f", elapsed * 1000 / Double(n))) ms each")
