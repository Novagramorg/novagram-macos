import AppKit
import QuartzCore

func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return kr == KERN_SUCCESS ? Int(info.phys_footprint) : -1
}

func write8bit(_ src: String, _ dst: String) {
    let image = NSImage(contentsOfFile: src)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dst) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

let dir = CommandLine.arguments[1]
let mode = CommandLine.arguments[2]
let path = dir + (mode == "16" ? "/light16.png" : "/light8.png")
if mode == "convert" { write8bit(dir + "/light16.png", dir + "/light8.png"); exit(0) }

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
let started = CFAbsoluteTimeGetCurrent()
let image = NSImage(contentsOfFile: path)!
let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
host.contentsGravity = .resizeAspectFill
host.contents = image
CATransaction.flush()
RunLoop.current.run(until: Date().addingTimeInterval(1.5))
let shown = footprint()
let elapsed = CFAbsoluteTimeGetCurrent() - started
print("\(mode)-bit file: cg bpc=\(cg.bitsPerComponent) bpp=\(cg.bitsPerPixel) \(cg.width)x\(cg.height); footprint +\((shown - before) / 1024) KB after display; load+display \(Int(elapsed * 1000)) ms")
