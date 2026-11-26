import AppKit
import CryptoKit
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let bundle = Bundle(path: CommandLine.arguments[1])!
func digest(_ image: NSImage) -> String {
    var rect = CGRect(origin: .zero, size: image.size)
    let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    return "\(cg.width)x\(cg.height) " + SHA256.hash(data: Data(bytes: ctx.data!, count: cg.width * cg.height * 4)).map { String(format: "%02x", $0) }.joined()
}
let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
    NSColor.black.setFill()
    rect.insetBy(dx: 4, dy: 4).fill()
    return true
}
let named = image.setName("Icon_CopyCode")
let baseline = digest(bundle.image(forResource: "Icon_CopyCode")!)
let loaded = digest(bundle.image(forResource: "Icon_CopyCode")!)
print("baseline \(baseline)\nregistered \(named)\nafter \(loaded)\nsynthetic \(digest(image))")
