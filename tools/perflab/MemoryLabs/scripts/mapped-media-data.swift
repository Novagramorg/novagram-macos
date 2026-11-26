import AppKit
import ImageIO
func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return Int(info.phys_footprint)
}
let dir = CommandLine.arguments[1]
if CommandLine.arguments[2] == "make" {
    for i in 0 ..< 60 {
        let ctx = CGContext(data: nil, width: 1280, height: 960, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for j in 0 ..< 400 { ctx.setFillColor(CGColor(srgbRed: CGFloat((i * 7 + j) % 255) / 255, green: CGFloat(j % 200) / 255, blue: 0.5, alpha: 1)); ctx.fillEllipse(in: CGRect(x: (j * 37) % 1280, y: (j * 53) % 960, width: 60, height: 40)) }
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(dir)/p\(i).jpg") as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
    exit(0)
}
let mapped = CommandLine.arguments[2] == "mapped"
var kept: [Data] = []
let before = footprint()
var decodeTime = 0.0
for i in 0 ..< 60 {
    let t = CFAbsoluteTimeGetCurrent()
    let data = try! Data(contentsOf: URL(fileURLWithPath: "\(dir)/p\(i).jpg"), options: mapped ? [.mappedIfSafe] : [])
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640] as CFDictionary)!
    _ = thumb.width
    decodeTime += CFAbsoluteTimeGetCurrent() - t
    kept.append(data)
}
let total = kept.reduce(0) { $0 + $1.count }
print("\(mapped ? "mapped" : "heap  "): 60 photos (\(total / 1024) KB compressed) keep footprint +\((footprint() - before) / 1024) KB; read+decode \(String(format: "%.2f", decodeTime * 1000 / 60)) ms each")
